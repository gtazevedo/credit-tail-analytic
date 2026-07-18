import numpy as np
import pandas as pd
import os
import scipy.stats as stats
from arch import arch_model
from sklearn.preprocessing import RobustScaler
from sklearn.cluster import KMeans
from hmmlearn.hmm import GaussianHMM
from typing import Dict, List, Tuple, Union, Optional
import warnings
import logging
from credit_tail_analytics.utils import dados_dir

warnings.filterwarnings("ignore", category=FutureWarning)
warnings.filterwarnings("ignore", category=UserWarning)
logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Mapeamento canônico de grupos de indexador
# Usado para segmentar os modelos por regime de taxa
# ---------------------------------------------------------------------------
INDEXADOR_GRUPO_MAP = {
    'DI_SPREAD':      'CDI_Spread',
    'DI_PERCENTUAL':  'CDI_Percentual',
    'IPCA':           'IPCA',
    'IGPM':           'IGPM',
    'PRE':            'PRE',
}

# Rótulo padrão quando o indexador não cabe em nenhum grupo
INDEXADOR_OUTRO = 'Outro'


class CreditRiskEngine:
    """
    Motor quantitativo para modelagem de risco de cauda e identificação de regimes de crédito 
    (Credit Regime Switching) em debêntures do mercado secundário brasileiro.

    Implementa um pipeline econométrico completo ("End-to-End"):
    1. Feature Engineering e Tratamento de Microestrutura: Filtro de iliquidez baseado na Faixa de 
       Volume ANBIMA, eliminando ruído microestrutural ("marcação constante").
    2. Modelagem da Volatilidade Condicional: Extração de choques via AR(1)-EGARCH(1,1) com inovações 
       t-Student, capturando assimetria e caudas pesadas (Fat Tails). Estimação de VaR Condicional (99%).
    3. Inferência de Regimes Latentes: Comparação cross-sectional de uma abordagem atemporal de aprendizado 
       de máquina (K-Means) contra um modelo estocástico de transição de estados (Hidden Markov Model - HMM) 
       sob a premissa de Markov (Markov assumption).

    A segmentação é estritamente conduzida de forma intra-indexador para isolar os níveis de prêmio de risco 
    macroeconômicos (Cross-sectional mapping).

    Parâmetros
    ----------
    df : pd.DataFrame
        Base diária de debêntures com as colunas obrigatórias.
    features : list, optional
        Features usadas pelos modelos de clusterização. Padrão:
        ['Taxa_ZScore', 'Volatilidade_EGARCH'].
        Ambos K-Means e HMM usam as mesmas features; se apenas um receber
        features via argumento de método, elas prevalecem sobre o padrão.
    filter_low_liquidity : bool, default True
        Quando True, remove do Delta_Spread (input do EGARCH) os dias em que
        a debênture estava na Faixa 3 da ANBIMA ("Até 1MM" — Score_Liquidez=1),
        eliminando zeros artificiais de marcação na curva.
    """

    DEFAULT_FEATURES: List[str] = ['Spread_Equivalente', 'Taxa_Ajustada_Prazo']#['Taxa_ZScore', 'Volatilidade_EGARCH']

    def __init__(
        self,
        df: pd.DataFrame,
        features: Optional[List[str]] = None,
        filter_low_liquidity: bool = True,
    ) -> None:
        self.df = df.copy()
        self.features: List[str] = features if features is not None else self.DEFAULT_FEATURES
        self.filter_low_liquidity = filter_low_liquidity

        # volume_map: Score_Liquidez mais alto = mais líquido
        self.volume_map: Dict[str, int] = {
            'Até 1MM':         1,   # Faixa 3 ANBIMA — excluída quando filter_low_liquidity=True
            'Entre 1MM e 5MM': 2,
            'Superior a 5MM':  3,
        }
        # clustering_models: {indexador_grupo: {'kmeans': ..., 'scaler_k': ...,
        #                                        'hmm': ..., 'scaler_h': ...}}
        self.clustering_models: Dict[str, Dict] = {}

        self._validate_input()
        self._feature_engineering()

    # -----------------------------------------------------------------------
    # VALIDAÇÃO E FEATURE ENGINEERING
    # -----------------------------------------------------------------------

    def _validate_input(self) -> None:
        required_columns = [
            'Data', 'Ticker', 'Indexador', 'PU',
            'Faixa_Volume_ANBIMA', 'Taxa_Ativo', 'DU_Vencimento'
        ]
        missing = [col for col in required_columns if col not in self.df.columns]
        if missing:
            raise ValueError(f"Colunas obrigatórias ausentes: {missing}")

        self.df['Data'] = pd.to_datetime(self.df['Data'])
        self.df.sort_values(by=['Ticker', 'Data'], inplace=True)
        self.df.reset_index(drop=True, inplace=True)

    def _feature_engineering(self) -> None:
        # 1. Score de liquidez
        self.df['Score_Liquidez'] = (
            self.df['Faixa_Volume_ANBIMA'].map(self.volume_map).fillna(1).astype(int)
        )

        # 2. Log-retorno do PU
        self.df['Log_Retorno'] = self.df.groupby('Ticker')['PU'].transform(
            lambda x: np.log(x / x.shift(1))
        )

        # 3. Reclassificação do Indexador (separa DI% do DI+)
        medias_taxa = self.df.groupby('Ticker')['Taxa_Ativo'].transform('mean')
        is_di = self.df['Indexador'].str.upper() == 'DI'
        is_percent = medias_taxa > 30
        self.df.loc[is_di & is_percent,  'Indexador'] = 'DI_Percentual'
        self.df.loc[is_di & ~is_percent, 'Indexador'] = 'DI_Spread'

        # 4. Dados macroeconômicos (CDI, IPCA, IGPM) — vem antes do grupo pois
        #    o merge não altera Indexador, mas mantemos a ordem lógica correta.
        logger.info("Carregando dados macroeconômicos (dados/macro_data.csv)...")
        try:
            macro_path = str(dados_dir() / 'macro_data.csv')
            df_macro = pd.read_csv(macro_path)
            df_macro['Data'] = pd.to_datetime(df_macro['Data'])
            self.df = pd.merge(self.df, df_macro, on='Data', how='left')
            self.df['CDI_Anual']    = self.df['CDI_Anual'].ffill()
            self.df['IPCA_Mensal']  = self.df['IPCA_Mensal'].ffill()
            self.df['IGPM_Mensal']  = self.df['IGPM_Mensal'].ffill()
        except Exception as e:
            logger.warning(f"Falha ao carregar dados macroeconômicos. Erro: {e}")
            self.df['CDI_Anual']   = 10.4
            self.df['IPCA_Mensal'] = 0.5
            self.df['IGPM_Mensal'] = 0.5

        # 5b. Grupo canônico por indexador — calculado APÓS a reclassificação DI%/DI+
        #     e APÓS o merge macro (garante que Indexador está na forma final)
        self.df['Indexador_Grupo'] = (
            self.df['Indexador']
            .str.upper()
            .str.strip()
            .map(lambda x: INDEXADOR_GRUPO_MAP.get(x, INDEXADOR_OUTRO))
        )

        # 6. Spread equivalente (normalizado por indexador)
        def calc_spread(row):
            idx  = str(row['Indexador']).upper()
            taxa = row['Taxa_Ativo']
            cdi  = row['CDI_Anual']
            if pd.isna(taxa) or pd.isna(cdi):
                return np.nan
            if idx in ['DI_SPREAD', 'IPCA', 'IGPM']:
                return taxa
            elif idx == 'DI_PERCENTUAL':
                fator_diario_cdi    = (1 + cdi / 100.0) ** (1 / 252)
                fator_diario_titulo = (fator_diario_cdi - 1) * (taxa / 100.0) + 1
                yield_anualizado    = fator_diario_titulo ** 252 - 1
                return yield_anualizado * 100.0 - cdi
            else:
                return taxa - cdi

        self.df['Spread_Equivalente'] = self.df.apply(calc_spread, axis=1)

        # 7. Taxa ajustada pelo prazo
        du_seguro = np.maximum(self.df['DU_Vencimento'], 2)
        self.df['Taxa_Ajustada_Prazo'] = self.df['Spread_Equivalente'] / np.log(du_seguro)

        # 8. Spread com forward-fill + Z-Score rolante (janela 60 dias)
        self.df['Spread_Ffill'] = self.df.groupby('Ticker')['Spread_Equivalente'].ffill()

        def calc_zscore(x):
            r = x.rolling(window=60, min_periods=10)
            return (x - r.mean()) / r.std().replace(0, np.nan)

        self.df['Taxa_ZScore'] = (
            self.df.groupby('Ticker')['Spread_Ffill']
            .transform(calc_zscore)
            .fillna(0)
        )

        # 9. Delta_Spread — input do EGARCH
        self.df['Delta_Spread'] = self.df.groupby('Ticker')['Spread_Ffill'].transform(
            lambda x: x.diff()
        )

        # 10. Filtro de liquidez: zera observações de baixa liquidez (Faixa 3 ANBIMA)
        if self.filter_low_liquidity:
            mask_baixa = self.df['Score_Liquidez'] == 1
            n_removidos = mask_baixa.sum()
            self.df.loc[mask_baixa, 'Delta_Spread'] = np.nan
            logger.info(
                f"Filtro de liquidez (Faixa 3 ANBIMA): {n_removidos} observações "
                f"removidas do Delta_Spread antes do EGARCH."
            )

    # -----------------------------------------------------------------------
    # EGARCH + VaR
    # -----------------------------------------------------------------------

    def _egarch_var(
        self,
        group_df: pd.DataFrame,
        split_date: str,
        alpha: float = 0.01,
    ) -> Tuple[pd.Series, pd.Series]:
        returns = group_df['Delta_Spread']
        datas   = group_df['Data']

        vol_series = pd.Series(np.nan, index=returns.index)
        var_series = pd.Series(np.nan, index=returns.index)

        valid_idx = returns.dropna().index
        if len(valid_idx) < 30:
            return vol_series, var_series

        returns_scaled = returns.loc[valid_idx] * 100
        datas_valid    = datas.loc[valid_idx]

        split_dt  = pd.to_datetime(split_date)
        train_mask = datas_valid < split_dt
        split_idx  = train_mask.sum()

        if split_idx < 25:
            return vol_series, var_series

        try:
            model = arch_model(
                returns_scaled,
                mean='AR', lags=1,
                vol='EGARCH', p=1, o=1, q=1,
                dist='t',
                rescale=False,
            )
            res_is  = model.fit(last_obs=split_idx, disp='off', show_warning=False)
            res_oos = model.fix(res_is.params)

            cond_vol  = res_oos.conditional_volatility
            cond_mean = res_oos.conditional_mean
            if isinstance(cond_mean, pd.DataFrame):
                cond_mean = cond_mean.iloc[:, 0]

            nu      = res_is.params.get('nu', 5.0)
            q_alpha = model.distribution.ppf(1 - alpha, nu)
            var_99  = cond_mean + cond_vol * q_alpha

            vol_series.loc[valid_idx] = cond_vol / 100
            var_series.loc[valid_idx] = var_99  / 100
        except Exception:
            pass

        return vol_series, var_series

    def _kupiec_pof_test(
        self,
        retornos: Union[pd.Series, np.ndarray],
        var_limits: Union[pd.Series, np.ndarray],
        nivel_confianca: float = 0.99,
    ) -> float:
        ret = np.asarray(retornos)
        var = np.asarray(var_limits)
        mask = ~np.isnan(ret) & ~np.isnan(var)
        ret, var = ret[mask], var[mask]
        n = len(ret)
        if n == 0:
            return np.nan

        failures   = np.sum(ret < var)
        p_expected = 1.0 - nivel_confianca

        if failures == 0:
            lr_stat = -2 * n * np.log(1 - p_expected)
        else:
            failure_rate = failures / n
            if failure_rate >= 1.0:
                lr_stat = -2 * n * np.log(p_expected)
            else:
                num = ((1 - p_expected) ** (n - failures)) * (p_expected ** failures)
                den = ((1 - failure_rate) ** (n - failures)) * (failure_rate ** failures)
                if den <= 0 or num <= 0:
                    return np.nan
                lr_stat = -2 * np.log(num / den)

        return 1.0 - stats.chi2.cdf(lr_stat, df=1)

    def build_volatility_features(self, split_date: str) -> None:
        """Estima EGARCH para cada Ticker e preenche Volatilidade_EGARCH e VaR_99."""
        self.df['Volatilidade_EGARCH'] = np.nan
        self.df['VaR_99']              = np.nan

        for ticker, group in self.df.groupby('Ticker'):
            vol, var = self._egarch_var(
                group[['Data', 'Delta_Spread']], split_date
            )
            self.df.loc[group.index, 'Volatilidade_EGARCH'] = vol
            self.df.loc[group.index, 'VaR_99']              = var

    # -----------------------------------------------------------------------
    # HELPER: Correção Semântica de Labels (Label Switching)
    # -----------------------------------------------------------------------

    @staticmethod
    def _label_switching_correction(
        centers: np.ndarray,
        feature_names: List[str],
    ) -> Dict[int, str]:
        """
        Ordena os centróides pelo score de risco agregado e retorna um dicionário
        {cluster_id_raw → 'Verde'|'Amarelo'|'Vermelho'}.

        O score é calculado como a soma das médias ajustadas de ZScore e
        Volatilidade no espaço escalado dos centróides.
        """
        n_clusters = centers.shape[0]

        # Índices das features de risco no vetor de centróides
        risk_indices = [
            i for i, f in enumerate(feature_names)
            if 'ZScore' in f or 'Volatilidade' in f or 'Ajustada' in f
        ]
        # Fallback: usa todas as features se nenhuma for reconhecida
        if not risk_indices:
            risk_indices = list(range(centers.shape[1]))

        risk_scores   = centers[:, risk_indices].sum(axis=1)
        sorted_ids    = np.argsort(risk_scores)          # menor → maior risco
        label_names   = ['Verde', 'Amarelo', 'Vermelho']

        return {int(sorted_ids[i]): label_names[i] for i in range(n_clusters)}

    # -----------------------------------------------------------------------
    # K-MEANS: Pool Diário por Grupo de Indexador
    # -----------------------------------------------------------------------

    def run_kmeans_regimes(
        self,
        split_date: str,
        features: Optional[List[str]] = None,
    ) -> pd.DataFrame:
        """
        Treina K-Means no pool diário In-Sample (sem agregação temporal)
        e prediz dia a dia no Out-of-Sample, segmentando por Indexador_Grupo.

        Parâmetros
        ----------
        split_date : str
            Data de corte 'YYYY-MM-DD'.
        features : list, optional
            Sobreescreve self.features apenas para esta execução.

        Retorna
        -------
        pd.DataFrame
            Colunas: Ticker, Data, Indexador_Grupo, Cluster_KMeans
        """
        feats = features if features is not None else self.features
        logger.info(f"[K-Means] Features: {feats}")

        # Valida disponibilidade das features
        missing_feats = [f for f in feats if f not in self.df.columns]
        if missing_feats:
            raise ValueError(
                f"[K-Means] Features ausentes no DataFrame: {missing_feats}. "
                "Garanta que build_volatility_features() foi chamado antes."
            )

        subset_cols = feats + ['Ticker', 'Data', 'Indexador_Grupo']
        df_clean    = self.df[subset_cols].dropna(subset=feats).sort_values('Data')
        split_dt    = pd.to_datetime(split_date)

        train_df = df_clean[df_clean['Data'] <  split_dt]
        val_df   = df_clean[df_clean['Data'] >= split_dt]

        all_results: List[pd.DataFrame] = []

        for grupo, train_grupo in train_df.groupby('Indexador_Grupo'):
            X_train = train_grupo[feats].values

            if len(X_train) < 3:
                logger.warning(f"[K-Means] Grupo '{grupo}': dados insuficientes no IS. Pulando.")
                continue

            scaler = RobustScaler()
            X_train_sc = scaler.fit_transform(X_train)

            kmeans = KMeans(n_clusters=3, random_state=42, n_init=10)
            kmeans.fit(X_train_sc)

            # Correção semântica imediatamente após o fit
            cluster_map = self._label_switching_correction(
                kmeans.cluster_centers_, feats
            )

            # Armazena modelo por grupo
            self.clustering_models.setdefault(grupo, {}).update({
                'kmeans':   kmeans,
                'scaler_k': scaler,
                'feat_k':   feats,
                'label_map_k': cluster_map,
            })

            # Predição OOS dia a dia
            val_grupo = val_df[val_df['Indexador_Grupo'] == grupo]
            if val_grupo.empty:
                logger.warning(f"[K-Means] Grupo '{grupo}': sem dados OOS.")
                continue

            X_val_sc = scaler.transform(val_grupo[feats].values)
            raw_labels = kmeans.predict(X_val_sc)

            resultado = val_grupo[['Ticker', 'Data', 'Indexador_Grupo']].copy()
            resultado['Cluster_KMeans'] = [cluster_map[c] for c in raw_labels]
            all_results.append(resultado)

            logger.info(
                f"[K-Means] Grupo '{grupo}': {len(X_train)} obs IS, "
                f"{len(val_grupo)} obs OOS classificadas."
            )

        if not all_results:
            logger.warning("[K-Means] Nenhum resultado produzido.")
            return pd.DataFrame(columns=['Ticker', 'Data', 'Indexador_Grupo', 'Cluster_KMeans'])

        return pd.concat(all_results, ignore_index=True)

    # -----------------------------------------------------------------------
    # HMM: Por Ticker, Respeitando a Série Temporal, por Grupo de Indexador
    # -----------------------------------------------------------------------

    def run_hmm_regimes(
        self,
        split_date: str,
        features: Optional[List[str]] = None,
    ) -> pd.DataFrame:
        """
        Treina um GaussianHMM individualmente para cada Ticker (preservando a
        ordem temporal) e prediz os estados OOS, segmentando por Indexador_Grupo.

        Diferença fundamental vs K-Means: o HMM itera Ticker por Ticker e vê
        a sequência cronológica, capturando persistência/inércia de regime.

        Parâmetros
        ----------
        split_date : str
            Data de corte 'YYYY-MM-DD'.
        features : list, optional
            Sobreescreve self.features apenas para esta execução.

        Retorna
        -------
        pd.DataFrame
            Colunas: Ticker, Data, Indexador_Grupo, Cluster_HMM, Prob_Crise_HMM
        """
        feats = features if features is not None else self.features
        logger.info(f"[HMM] Features: {feats}")

        missing_feats = [f for f in feats if f not in self.df.columns]
        if missing_feats:
            raise ValueError(
                f"[HMM] Features ausentes no DataFrame: {missing_feats}. "
                "Garanta que build_volatility_features() foi chamado antes."
            )

        subset_cols = feats + ['Ticker', 'Data', 'Indexador_Grupo']
        df_clean    = self.df[subset_cols].dropna(subset=feats).sort_values(['Ticker', 'Data'])
        split_dt    = pd.to_datetime(split_date)

        all_results: List[pd.DataFrame] = []

        for (grupo, ticker), df_ticker in df_clean.groupby(['Indexador_Grupo', 'Ticker']):
            df_ticker = df_ticker.sort_values('Data').reset_index(drop=True)

            is_mask  = df_ticker['Data'] <  split_dt
            oos_mask = df_ticker['Data'] >= split_dt

            X_is  = df_ticker.loc[is_mask,  feats].values
            X_oos = df_ticker.loc[oos_mask, feats].values

            # Cria o template de resultado para este ticker
            result_base = df_ticker.loc[oos_mask, ['Ticker', 'Data', 'Indexador_Grupo']].copy()

            # Fallback para tickers sem dados suficientes
            if len(X_is) < 10 or len(X_oos) == 0:
                result_base['Cluster_HMM']   = 'Inconclusivo'
                result_base['Prob_Crise_HMM'] = np.nan
                all_results.append(result_base)
                logger.warning(
                    f"[HMM] {ticker} ({grupo}): IS insuficiente "
                    f"({len(X_is)} obs). Marcado como Inconclusivo."
                )
                continue

            try:
                # Escala pelo IS de cada Ticker (evita data leakage)
                scaler  = RobustScaler()
                X_is_sc = scaler.fit_transform(X_is)

                hmm = GaussianHMM(
                    n_components=3,
                    covariance_type='full',
                    n_iter=100,
                    random_state=42,
                )
                hmm.fit(X_is_sc)

                # Correção semântica: usa as médias dos estados (means_)
                cluster_map = self._label_switching_correction(hmm.means_, feats)

                # Predição OOS
                X_oos_sc  = scaler.transform(X_oos)
                raw_states = hmm.predict(X_oos_sc)
                proba_mat  = hmm.predict_proba(X_oos_sc)   # shape (n_oos, 3)

                # Identifica o índice do estado "Vermelho" para extrair Prob_Crise
                vermelho_id = next(
                    (k for k, v in cluster_map.items() if v == 'Vermelho'), 2
                )

                result_base['Cluster_HMM']    = [cluster_map[s] for s in raw_states]
                result_base['Prob_Crise_HMM'] = proba_mat[:, vermelho_id]

                all_results.append(result_base)

            except Exception as exc:
                result_base['Cluster_HMM']    = 'Inconclusivo'
                result_base['Prob_Crise_HMM'] = np.nan
                all_results.append(result_base)
                logger.warning(
                    f"[HMM] {ticker} ({grupo}): falha na convergência — {exc}. "
                    "Marcado como Inconclusivo."
                )

        if not all_results:
            logger.warning("[HMM] Nenhum resultado produzido.")
            return pd.DataFrame(
                columns=['Ticker', 'Data', 'Indexador_Grupo', 'Cluster_HMM', 'Prob_Crise_HMM']
            )

        df_out = pd.concat(all_results, ignore_index=True)
        n_inc  = (df_out['Cluster_HMM'] == 'Inconclusivo').sum()
        logger.info(
            f"[HMM] Concluído: {len(df_out)} obs OOS classificadas "
            f"({n_inc} Inconclusivo)."
        )
        return df_out

    # -----------------------------------------------------------------------
    # PIPELINE PRINCIPAL
    # -----------------------------------------------------------------------

    def execute_pipeline(
        self,
        split_date: str = '2023-01-01',
        model_type: str = 'both',
        features: Optional[List[str]] = None,
    ) -> Tuple[pd.DataFrame, pd.DataFrame]:
        """
        Executa o pipeline completo: EGARCH → clusterização (K-Means e/ou HMM).

        Parâmetros
        ----------
        split_date : str
            Data de corte Treino/Validação no formato 'YYYY-MM-DD'.
        model_type : str
            'kmeans' | 'hmm' | 'both'. Controla quais modelos são executados.
        features : list, optional
            Sobreescreve self.features para ambos os modelos.

        Retorna
        -------
        (self.df, df_clusters)
            df_clusters contém colunas diárias unificadas de K-Means e/ou HMM.
        """
        if model_type not in ('kmeans', 'hmm', 'both'):
            raise ValueError(f"model_type deve ser 'kmeans', 'hmm' ou 'both'. Recebido: {model_type}")

        logger.info(f"Construindo features de volatilidade (split_date={split_date})...")
        self.build_volatility_features(split_date)

        df_kmeans: Optional[pd.DataFrame] = None
        df_hmm:    Optional[pd.DataFrame] = None

        if model_type in ('kmeans', 'both'):
            logger.info("Executando K-Means (baseline atemporal)...")
            df_kmeans = self.run_kmeans_regimes(split_date, features=features)

        if model_type in ('hmm', 'both'):
            logger.info("Executando HMM (modelo com memória temporal)...")
            df_hmm = self.run_hmm_regimes(split_date, features=features)

        # Merge dos resultados num único DataFrame diário
        merge_keys = ['Ticker', 'Data', 'Indexador_Grupo']

        if df_kmeans is not None and df_hmm is not None:
            df_clusters = pd.merge(df_kmeans, df_hmm, on=merge_keys, how='outer')
        elif df_kmeans is not None:
            df_clusters = df_kmeans
        elif df_hmm is not None:
            df_clusters = df_hmm
        else:
            df_clusters = pd.DataFrame()

        if not df_clusters.empty:
            aux_cols = ['Ticker', 'Data', 'Taxa_ZScore', 'Volatilidade_EGARCH',
                        'Taxa_Ajustada_Prazo', 'Score_Liquidez', 'VaR_99', 'PU', 'Taxa_Ativo']
            aux_cols = [c for c in aux_cols if c in self.df.columns]
            df_aux = self.df[aux_cols].drop_duplicates(subset=['Ticker', 'Data'])
            df_clusters = pd.merge(df_clusters, df_aux, on=['Ticker', 'Data'], how='left')

        return self.df, df_clusters
