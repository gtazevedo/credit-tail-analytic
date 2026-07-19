import pandas as pd
import numpy as np
import os
import itertools
from sklearn.preprocessing import RobustScaler
from sklearn.cluster import KMeans
from sklearn.metrics import silhouette_score, davies_bouldin_score, calinski_harabasz_score
import logging

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Features padrão candidatas quando nenhuma for fornecida.
# NOTA: Score_Liquidez foi deliberadamente excluída deste conjunto.
# Ela é uma variável estrutural do ativo (faixa de volume ANBIMA), não do emissor,
# e já é utilizada como filtro de entrada no CreditRiskEngine. Incluí-la como
# feature de clusterização criaria um viés de liquidez nos clusters, que passariam
# a refletir o tamanho das emissões em vez do risco de crédito do emissor.
DEFAULT_CANDIDATE_FEATURES = [
    'Taxa_ZScore',           # Risco relativo ao próprio histórico (anomalia de spread)
    'Volatilidade_EGARCH',   # Risco de mercado dinâmico (volatilidade condicional AR-EGARCH-t)
    'VaR_99',                # Risco de cauda — Valor em Risco 99% (t-Student)
    'Expected_Shortfall_99', # Perda esperada além do VaR (CVaR / Expected Shortfall)
    'Spread_Equivalente',    # Nível absoluto de prêmio de risco (High Grade vs High Yield)
    'Taxa_Ajustada_Prazo',   # Prêmio ajustado pela duration/vencimento
]


class FeatureSelector:
    """
    Otimizador combinatório iterativo para seleção de atributos (Feature Selection) aplicado a 
    modelos de clusterização de risco de crédito (K-Means e HMM).

    Executa uma busca exaustiva (Grid Search) sobre combinações de K features (k ∈ [2, N]),
    avaliando a capacidade de separabilidade cross-sectional dos regimes latentes.
    O modelo seleciona o subconjunto ótimo por meio de uma função score multi-critério baseada
    em três métricas não-supervisionadas clássicas da literatura de análise de clusters:

    1. Silhouette Score (Rousseeuw, 1987): Mede a coesão intra-cluster vs a separabilidade
       inter-cluster no espaço das features escaladas. Varia em [-1, 1]; maior é melhor.
       Ref: Rousseeuw, P.J. (1987). "Silhouettes: A graphical aid to the interpretation and
       validation of cluster analysis". Journal of Computational and Applied Mathematics, 20, 53–65.

    2. Davies-Bouldin Index — DBI (Davies & Bouldin, 1979): Avalia a razão média de dispersão
       intra-cluster pela distância entre centróides. Menor é melhor.
       Ref: Davies, D.L. & Bouldin, D.W. (1979). "A cluster separation measure".
       IEEE Transactions on Pattern Analysis and Machine Intelligence, 1(2), 224–227.

    3. Calinski-Harabasz Index — CH (Calinski & Harabasz, 1974): Mede a razão entre a dispersão
       inter-cluster (between-cluster sum of squares) e a dispersão intra-cluster (within-cluster
       sum of squares), ponderada pelos graus de liberdade. Quanto maior, mais compactos e
       bem-separados são os clusters. Não possui limite superior fixo (escala com N e K);
       a normalização para composição do score global é feita min-max intra-ranking.
       Ref: Caliński, T. & Harabasz, J. (1974). "A dendrite method for cluster analysis".
       Communications in Statistics, 3(1), 1–27.

    NOTA: A versão anterior utilizava uma métrica autoral denominada 'Contagion Variance',
    que media a variância temporal da proporção de ativos em High Risk. Essa métrica foi
    descontinuada por induzir viés de seleção: ao penalizar variância temporal alta, favorecia
    features que geram regimes artificialmente estáveis, suprimindo sinais de stress genuínos.

    A otimização é conduzida estritamente de forma intra-indexador para isolar o mapeamento
    cross-sectional e eliminar o viés de nível nominal (Nominal Rate Bias).
    """

    def __init__(
        self,
        df: pd.DataFrame,
        candidate_features: list = None,
        split_date: str = '2023-01-01',
        filter_low_liquidity: bool = True,
    ):
        """
        Parâmetros
        ----------
        df : pd.DataFrame
            DataFrame processado pelo CreditRiskEngine (com Volatilidade_EGARCH, etc.).
        candidate_features : list, optional
            Features candidatas a serem avaliadas. Padrão: DEFAULT_CANDIDATE_FEATURES.
        split_date : str
            Data de corte para avaliar apenas o In-Sample.
        filter_low_liquidity : bool, default True
            Remove linhas com Score_Liquidez == 1 (Faixa 3 ANBIMA) antes de qualquer
            avaliação, alinhando com o filtro aplicado no EGARCH.
        """
        self.candidate_features = candidate_features or DEFAULT_CANDIDATE_FEATURES
        self.split_date = pd.to_datetime(split_date)
        self.filter_low_liquidity = filter_low_liquidity
        self.best_features: list = []  # preenchido após evaluate_subsets()

        # Aplica filtro de liquidez logo na entrada
        if filter_low_liquidity and 'Score_Liquidez' in df.columns:
            n_antes = len(df)
            df = df[df['Score_Liquidez'] > 1].copy()
            logger.info(
                f"[FeatureSelector] Filtro de liquidez: {n_antes - len(df)} "
                f"linhas removidas (Score_Liquidez == 1)."
            )
        self.df = df

    # -----------------------------------------------------------------------
    # Avaliação de um subconjunto de features (por Indexador_Grupo)
    # -----------------------------------------------------------------------

    def _run_kmeans_for_subset(self, features_subset: list) -> pd.DataFrame:
        """
        Executa K-Means (3 clusters) no pool diário IS para cada Indexador_Grupo
        e retorna os rótulos + métricas associadas.
        """
        grupo_col = 'Indexador_Grupo' if 'Indexador_Grupo' in self.df.columns else None

        df_sorted = self.df.sort_values('Data').dropna(subset=list(features_subset))
        if df_sorted.empty:
            return pd.DataFrame()

        train_df = df_sorted[df_sorted['Data'] < self.split_date]
        if train_df.empty:
            return pd.DataFrame()

        results = []
        grupos = train_df[grupo_col].unique() if grupo_col else ['_all']

        for grupo in grupos:
            grp_train = train_df[train_df[grupo_col] == grupo] if grupo_col else train_df

            X = grp_train[list(features_subset)].values
            if len(X) < 6:          # Mínimo para 3 clusters com silhouette estável
                continue

            scaler = RobustScaler()
            X_sc = scaler.fit_transform(X)

            try:
                km = KMeans(n_clusters=3, random_state=42, n_init=10)
                labels = km.fit_predict(X_sc)
            except Exception as e:
                logger.debug(f"Falha ao treinar KMeans (Grupo: {grupo}, Base_features: {features_subset}): {e}")
                continue

            res = grp_train[['Ticker', 'Data']].copy()
            if grupo_col:
                res['Indexador_Grupo'] = grupo
            res['Cluster'] = labels
            results.append(res)

        return pd.concat(results, ignore_index=True) if results else pd.DataFrame()

    # -----------------------------------------------------------------------
    # Avaliação de todos os subconjuntos
    # -----------------------------------------------------------------------

    def evaluate_subsets(
        self,
        min_features: int = 2,
        max_features: int = None,
        n_jobs: int = 2,
    ) -> pd.DataFrame:
        """
        Itera sobre todas as combinações de features candidatas, avalia as métricas
        de qualidade e retorna um ranking ordenado pelo Global_Score.

        Após a chamada, `self.best_features` é preenchido com o melhor subconjunto.

        Parâmetros
        ----------
        min_features : int
            Tamanho mínimo dos subconjuntos a testar (default: 2).
        max_features : int, optional
            Tamanho máximo (default: len(candidate_features)).
        n_jobs : int, default 2
            Número de núcleos utilizados pelo joblib. Usar -1 para todos os núcleos
            disponíveis (pode causar instabilidade em máquinas com pouca RAM).

        Retorna
        -------
        pd.DataFrame
            Colunas: Features, Num_Features, Silhouette_Score, Davies_Bouldin,
                     CH_Score, Global_Score.
        """
        # Filtra candidatos disponíveis no DataFrame
        available = [f for f in self.candidate_features if f in self.df.columns]
        if len(available) < min_features:
            logger.warning(
                f"[FeatureSelector] Apenas {len(available)} features disponíveis no "
                f"DataFrame. Ajuste candidate_features."
            )
            return pd.DataFrame()

        if max_features is None:
            max_features = len(available)

        all_combinations = []
        for r in range(min_features, max_features + 1):
            all_combinations.extend(list(itertools.combinations(available, r)))

        total = len(all_combinations)
        logger.info(
            f"[FeatureSelector] Testando {total} combinações de features | "
            f"Métricas: Silhouette, Davies-Bouldin, Calinski-Harabasz | n_jobs={n_jobs}"
        )

        grupo_col = 'Indexador_Grupo' if 'Indexador_Grupo' in self.df.columns else None
        df_full = self.df[self.df['Data'] < self.split_date].copy()

        def _eval_combo(i_and_subset):
            i, subset = i_and_subset
            subset = list(subset)
            logger.info(f"  Combinação {i}/{total}: {subset}")

            res_df = self._run_kmeans_for_subset(subset)
            if res_df.empty:
                return None

            sil_list, db_list, ch_list = [], [], []
            grupos_avail = (
                res_df['Indexador_Grupo'].unique()
                if (grupo_col and 'Indexador_Grupo' in res_df.columns)
                else ['_all']
            )
            df_full_sub = df_full.dropna(subset=subset)

            for grupo in grupos_avail:
                g_res  = res_df[res_df['Indexador_Grupo'] == grupo] if grupo_col else res_df
                g_full = df_full_sub[df_full_sub['Indexador_Grupo'] == grupo] if grupo_col else df_full_sub

                merged = g_res.merge(g_full[['Ticker', 'Data'] + subset], on=['Ticker', 'Data'])
                if len(merged) < 6 or merged['Cluster'].nunique() < 2:
                    continue

                X_eval = RobustScaler().fit_transform(merged[subset].values)
                labels = merged['Cluster'].values

                try:
                    sil_list.append(silhouette_score(X_eval, labels))
                    db_list.append(davies_bouldin_score(X_eval, labels))
                    # Calinski-Harabasz Index (CH): razão entre dispersão inter e intra-cluster.
                    # Requer pelo menos 2 clusters e pelo menos 2 observações por cluster.
                    # Ref: Caliński & Harabasz (1974), Communications in Statistics, 3(1), 1–27.
                    ch_list.append(calinski_harabasz_score(X_eval, labels))
                except Exception as e:
                    logger.debug(f"Falha ao calcular métricas de validação (Grupo: {grupo}): {e}")
                    pass

            if not sil_list:
                return None

            return {
                'Features':         ', '.join(subset),
                'Num_Features':     len(subset),
                'Silhouette_Score': float(np.mean(sil_list)),
                'Davies_Bouldin':   float(np.mean(db_list)) if db_list else np.nan,
                'CH_Score':         float(np.mean(ch_list)) if ch_list else np.nan,
            }

        from joblib import Parallel, delayed
        results_raw = Parallel(n_jobs=n_jobs, prefer="threads")(
            delayed(_eval_combo)(combo) for combo in enumerate(all_combinations, 1)
        )
        
        results_list = [r for r in results_raw if r is not None]

        results_df = pd.DataFrame(results_list)
        if results_df.empty:
            logger.warning("[FeatureSelector] Nenhuma combinação gerou métricas válidas.")
            return results_df

        # ---- Score global normalizado ----
        def _safe_norm(series, invert=False):
            rng = series.max() - series.min()
            if rng < 1e-9:
                return pd.Series(0.5, index=series.index)
            norm = (series - series.min()) / rng
            return 1.0 - norm if invert else norm

        sil_norm = _safe_norm(results_df['Silhouette_Score'])
        db_norm  = _safe_norm(results_df['Davies_Bouldin'], invert=True)

        # Calinski-Harabasz: maior é melhor. NaN → substitui por 0 antes de normalizar
        # (evita que combinações sem CH válido recebam score artificialmente alto).
        ch_filled = results_df['CH_Score'].fillna(0)
        ch_norm   = _safe_norm(ch_filled)  # sem invert — CH maior = melhor separação

        # Pesos: Silhouette e DBI com 35% cada; CH com 30%.
        # O CH complementa Silhouette+DBI capturando a razão absoluta de variância entre grupos,
        # sem viés temporal — diferente da antiga Contagion Variance que penalizava sinais de stress.
        results_df['Global_Score'] = (sil_norm * 0.35) + (db_norm * 0.35) + (ch_norm * 0.30)
        results_df = results_df.sort_values('Global_Score', ascending=False).reset_index(drop=True)

        # Preenche self.best_features com o vencedor
        best_row = results_df.iloc[0]
        self.best_features = best_row['Features'].split(', ')
        logger.info(
            f"[FeatureSelector] Melhor subconjunto: {self.best_features} "
            f"(Global_Score={best_row['Global_Score']:.4f} | "
            f"Silhouette={best_row['Silhouette_Score']:.4f} | "
            f"DBI={best_row['Davies_Bouldin']:.4f} | "
            f"CH={best_row['CH_Score']:.1f})"
        )

        return results_df


# ---------------------------------------------------------------------------
# Ponto de entrada standalone
# ---------------------------------------------------------------------------
if __name__ == '__main__':
    from credit_tail_analytics.models.credit_risk.risk_pipeline import CreditRiskEngine
    from credit_tail_analytics.utils import dados_dir
    import warnings
    warnings.filterwarnings('ignore')
    filter_low_liquidity = False

    logger.info("Carregando bases para Feature Selection...")
    hist = pd.read_csv(dados_dir() / 'debentures_historico_bruto.csv')
    cad  = pd.read_csv(dados_dir() / 'cadastro_debentures.csv')

    df = pd.merge(hist, cad[['Ticker', 'Indexador', 'Data_Vencimento']], on='Ticker', how='left')
    df['Data']             = pd.to_datetime(df['Data'])
    df['Data_Vencimento']  = pd.to_datetime(df['Data_Vencimento'])

    datas_atuais = df['Data'].values.astype('datetime64[D]')
    datas_venc   = df['Data_Vencimento'].values.astype('datetime64[D]')
    mascara      = datas_venc > datas_atuais
    df = df[mascara].copy()
    df['DU_Vencimento'] = np.busday_count(
        df['Data'].values.astype('datetime64[D]'),
        df['Data_Vencimento'].values.astype('datetime64[D]'),
    )

    engine = CreditRiskEngine(
        df.dropna(subset=['Data', 'Ticker', 'Indexador', 'PU', 'Taxa_Ativo',
                          'DU_Vencimento', 'Faixa_Volume_ANBIMA']),
        filter_low_liquidity=False,
    )
    engine.build_volatility_features(split_date='2023-01-01')

    selector = FeatureSelector(
        engine.df,
        candidate_features=DEFAULT_CANDIDATE_FEATURES,
        split_date='2023-01-01',
        filter_low_liquidity=False,
    )

    ranking = selector.evaluate_subsets(min_features=2, max_features=4, n_jobs=2)

    out_path = dados_dir() / 'feature_selection_ranking.csv'
    ranking.to_csv(out_path, index=False)
    logger.info(f"Ranking salvo em {out_path}.")
    print("\nTop 5 Conjuntos de Features:")
    print(ranking.head(5).to_string())
    print(f"\nMelhor subconjunto recomendado: {selector.best_features}")
