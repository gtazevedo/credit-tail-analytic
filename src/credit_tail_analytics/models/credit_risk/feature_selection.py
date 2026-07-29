import pandas as pd
import numpy as np
import itertools
from sklearn.preprocessing import RobustScaler
from sklearn.cluster import KMeans
from sklearn.metrics import silhouette_score, davies_bouldin_score, calinski_harabasz_score
import logging
from typing import Dict, List, Optional, Tuple

# Sem logging.basicConfig — configuração delegada ao caller (run_frequentist_engine, etc.)
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
    'Spread_Range_Intraday', # Variabilidade do Bid-Ask intraday (Pânico de Market Makers)
    'Spread_Skew_Intraday',  # Direcionalidade do fluxo de ordens (pressão compradora/vendedora)
]


class FeatureSelector:
    """
    Otimizador combinatório iterativo para seleção de atributos (Feature Selection) aplicado a
    modelos de clusterização de risco de crédito (K-Means e HMM).

    Executa uma busca exaustiva (Grid Search) sobre combinações de K features (k ∈ [2, N]),
    avaliando a capacidade de separabilidade cross-sectional dos regimes latentes.
    O modelo seleciona o subconjunto ótimo por meio do método de agregação de ranks de Borda,
    baseado em três métricas não-supervisionadas clássicas da literatura de análise de clusters:

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
       bem-separados são os clusters.
       Ref: Caliński, T. & Harabasz, J. (1974). "A dendrite method for cluster analysis".
       Communications in Statistics, 3(1), 1–27.

    Agregação por Borda Count (Borda, 1781):
    Em vez de normalizar os valores de cada métrica e ponderar com pesos arbitrários
    (min-max interdependente entre combinações), as combinações são ordenadas por rank
    em cada métrica individualmente. O Borda Score final é a soma dos ranks invertidos:
        Borda_Score = Σ (N + 1 − rank_i)
    Isso garante que o ranking seja determinístico e independente do conjunto de combinações
    testadas — um subconjunto não muda de posição apenas por adicionar/remover outros candidatos.
    Ref: de Borda, J.C. (1781). "Mémoire sur les élections au scrutin". Histoire de l'Académie
    Royale des Sciences.

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
    # Avaliação de um único subconjunto de features — método estático
    # (picklável pelo loky/cloudpickle para paralelismo por processo)
    # -----------------------------------------------------------------------

    @staticmethod
    def _eval_single_combo(
        subset: List[str],
        df_is: pd.DataFrame,
        grupo_col: Optional[str],
    ) -> Optional[Dict]:
        """
        Ajusta K-Means (3 clusters) e calcula as três métricas de qualidade para um
        subconjunto de features, agrupando por Indexador_Grupo.

        O ajuste e a avaliação são feitos sobre os **mesmos** dados escalados (X_sc),
        eliminando a necessidade de um merge posterior para recuperar os valores X.

        Parâmetros
        ----------
        subset    : List[str]     — subconjunto de features a testar
        df_is     : pd.DataFrame  — dados In-Sample (já filtrados por split_date)
        grupo_col : str | None    — coluna de agrupamento ('Indexador_Grupo' ou None)

        Retorna
        -------
        dict com as métricas médias por grupo, ou None se não houver dados suficientes.
        """
        df_sub = df_is.dropna(subset=subset)
        if df_sub.empty:
            return None

        sil_list: List[float] = []
        db_list:  List[float] = []
        ch_list:  List[float] = []

        grupos = df_sub[grupo_col].unique() if grupo_col else ['_all']

        for grupo in grupos:
            grp = df_sub[df_sub[grupo_col] == grupo] if grupo_col else df_sub
            X   = grp[subset].values

            if len(X) < 6:  # Mínimo para 3 clusters com silhouette estável
                continue

            X_sc = RobustScaler().fit_transform(X)

            try:
                km     = KMeans(n_clusters=3, random_state=42, n_init=10)
                labels = km.fit_predict(X_sc)
            except Exception:
                continue

            if len(np.unique(labels)) < 2:
                continue

            # Silhouette: calcula exato para grupos pequenos (≤ 5 000 obs);
            # usa amostragem apenas para grupos grandes, evitando variância de Monte Carlo
            # em grupos com poucas observações onde sample_size=10000 seria desnecessário.
            samp = min(len(X_sc), 5_000) if len(X_sc) > 5_000 else None

            try:
                sil_list.append(silhouette_score(X_sc, labels, sample_size=samp, random_state=42))
                db_list.append(davies_bouldin_score(X_sc, labels))
                # CH: razão entre dispersão inter e intra-cluster. Ref: Caliński & Harabasz (1974).
                ch_list.append(calinski_harabasz_score(X_sc, labels))
            except Exception:
                continue

        if not sil_list:
            return None

        return {
            'Features':         ', '.join(subset),
            'Num_Features':     len(subset),
            'Silhouette_Score': float(np.mean(sil_list)),
            'Davies_Bouldin':   float(np.mean(db_list)),
            'CH_Score':         float(np.mean(ch_list)),
        }

    # -----------------------------------------------------------------------
    # Avaliação de todos os subconjuntos
    # -----------------------------------------------------------------------

    def evaluate_subsets(
        self,
        min_features: int = 2,
        max_features: int = None,
        n_jobs: int = 2,
        required_features: list = None,
    ) -> pd.DataFrame:
        """
        Itera sobre todas as combinações de features candidatas, avalia as métricas
        de qualidade e retorna um ranking ordenado pelo Borda Score.

        Após a chamada, `self.best_features` é preenchido com o melhor subconjunto.

        Parâmetros
        ----------
        min_features : int
            Tamanho mínimo dos subconjuntos a testar (default: 2).
        max_features : int, optional
            Tamanho máximo (default: len(candidate_features)).
        n_jobs : int, default 2
            Número de processos paralelos (loky backend). Use -1 para todos os núcleos.
            O backend de processos (loky) é usado em vez de threads para contornar o GIL
            do CPython nas operações pandas. KMeans e métricas sklearn liberam o GIL
            internamente (Cython + OpenMP), mas o overhead de processo é amortizado
            pela maior carga computacional por combinação.
        required_features : list, optional
            Features que *devem* estar presentes em toda combinação avaliada.
            Padrão: ['Taxa_ZScore'].

            Motivação: features como Volatilidade_EGARCH e VaR_99 são altamente
            correlacionadas (VaR é função direta da vol condicional). Um conjunto
            {Volatilidade_EGARCH, VaR_99} produz Silhouette/CH altos por separabilidade
            geométrica, mas opera em espaço quase unidimensional e perde o sinal
            econômico de anomalia de spread (Taxa_ZScore). Forçar Taxa_ZScore garante
            que a dimensão de nível de risco relativo ao histórico esteja sempre presente.

        Retorna
        -------
        pd.DataFrame
            Colunas: Features, Num_Features, Silhouette_Score, Davies_Bouldin,
                     CH_Score, Borda_Score.
        """
        # Features obrigatórias em toda combinação (default: Taxa_ZScore)
        if required_features is None:
            required_features = ['Taxa_ZScore']
        required_available = [f for f in required_features if f in self.df.columns]
        if required_available:
            logger.info(
                f"[FeatureSelector] Features obrigatórias: {required_available} "
                f"(toda combinação deve conter pelo menos uma delas)"
            )

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

        # Gera combinações e filtra as que não incluem nenhuma required_feature
        all_combinations = list(itertools.chain.from_iterable(
            itertools.combinations(available, r)
            for r in range(min_features, max_features + 1)
        ))

        if required_available:
            req_set = set(required_available)
            all_combinations = [
                combo for combo in all_combinations
                if req_set.intersection(combo)  # ao menos uma required está presente
            ]
            logger.info(
                f"[FeatureSelector] {len(all_combinations)} combinações após filtro de "
                f"required_features (de um total inicial de "
                f"{sum(len(list(itertools.combinations(available, r))) for r in range(min_features, max_features+1))})"
            )

        total = len(all_combinations)
        if total == 0:
            logger.warning("[FeatureSelector] Nenhuma combinação válida após filtro de required_features.")
            return pd.DataFrame()

        logger.info(
            f"[FeatureSelector] Testando {total} combinações de features | "
            f"Métricas: Silhouette (Borda), Davies-Bouldin (Borda), "
            f"Calinski-Harabasz-log (Borda) | n_jobs={n_jobs}"
        )

        grupo_col = 'Indexador_Grupo' if 'Indexador_Grupo' in self.df.columns else None

        # Pré-filtra IS uma única vez fora do loop — evita re-filtrar em cada combo
        df_is = self.df[self.df['Data'] < self.split_date].copy()

        if df_is.empty:
            logger.warning("[FeatureSelector] Nenhum dado In-Sample encontrado.")
            return pd.DataFrame()

        from joblib import Parallel, delayed
        results_raw = Parallel(n_jobs=n_jobs, prefer="processes")(
            delayed(FeatureSelector._eval_single_combo)(list(subset), df_is, grupo_col)
            for i, subset in enumerate(all_combinations, 1)
        )

        results_list = [r for r in results_raw if r is not None]

        results_df = pd.DataFrame(results_list)
        if results_df.empty:
            logger.warning("[FeatureSelector] Nenhuma combinação gerou métricas válidas.")
            return results_df

        # ---- Agregação por Borda Count com log-normalização do CH ----
        # O índice Calinski-Harabasz cresce quadraticamente com N e K, produzindo
        # valores absolutos muito maiores que Silhouette ([-1,1]) e DBI ([0,∞)).
        # Sem normalização, o CH domina o rank de Borda mesmo quando a diferença
        # entre combinações é proporcional — favorecendo features correlacionadas
        # de alta variância (Volatilidade_EGARCH + VaR_99) em detrimento de features
        # com sinal econômico distinto (Taxa_ZScore).
        # A transformação log1p(CH) preserva a ordenação ordinal do CH e aproxima
        # sua distribuição de cauda pesada da escala do Silhouette e DBI.
        #
        # Ref: de Borda, J.C. (1781). Mémoire sur les élections au scrutin.
        #      Histoire de l'Académie Royale des Sciences.
        n = len(results_df)

        # Silhouette:            maior é melhor → rank ascending=False
        # Davies-Bouldin:        menor é melhor → rank ascending=True
        # CH (log-normalizado):  maior é melhor → rank ascending=False
        #                        NaN → 0 antes do log (pior posição)
        sil_rank = results_df['Silhouette_Score'].rank(ascending=False, method='average')
        dbi_rank = results_df['Davies_Bouldin'].rank(ascending=True,   method='average')
        ch_log   = np.log1p(results_df['CH_Score'].fillna(0))
        ch_rank  = pd.Series(ch_log).rank(ascending=False, method='average')

        results_df['CH_Score_Log'] = ch_log.values
        results_df['Borda_Score']  = (n + 1 - sil_rank) + (n + 1 - dbi_rank) + (n + 1 - ch_rank)
        results_df = results_df.sort_values('Borda_Score', ascending=False).reset_index(drop=True)

        # Preenche self.best_features com o vencedor
        best_row = results_df.iloc[0]
        self.best_features = best_row['Features'].split(', ')
        logger.info(
            f"[FeatureSelector] Melhor subconjunto: {self.best_features} "
            f"(Borda={best_row['Borda_Score']:.1f} | "
            f"Silhouette={best_row['Silhouette_Score']:.4f} | "
            f"DBI={best_row['Davies_Bouldin']:.4f} | "
            f"CH={best_row['CH_Score']:.1f} | log(CH)={best_row['CH_Score_Log']:.2f})"
        )

        return results_df


# ---------------------------------------------------------------------------
# Ponto de entrada standalone
# ---------------------------------------------------------------------------
if __name__ == '__main__':
    import logging as _logging
    _logging.basicConfig(level=_logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

    from credit_tail_analytics.models.credit_risk.risk_pipeline import CreditRiskEngine
    from credit_tail_analytics.utils import dados_dir
    import warnings
    warnings.filterwarnings('ignore')
    filter_low_liquidity = False

    logger.info("Carregando bases para Feature Selection...")
    hist = pd.read_csv(dados_dir() / 'debentures_historico_bruto.csv')
    cad  = pd.read_csv(dados_dir() / 'cadastro_debentures.csv')

    df = pd.merge(hist, cad[['Ticker', 'Indexador', 'Data_Vencimento']], on='Ticker', how='left')
    df['Data']            = pd.to_datetime(df['Data'])
    df['Data_Vencimento'] = pd.to_datetime(df['Data_Vencimento'])

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
