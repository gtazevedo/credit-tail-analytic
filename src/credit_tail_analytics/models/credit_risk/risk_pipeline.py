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
from tqdm import tqdm

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

    DEFAULT_FEATURES: List[str] = ['Taxa_ZScore', 'Volatilidade_EGARCH']

    def __init__(
        self,
        df: pd.DataFrame,
        features: Optional[List[str]] = None,
        filter_low_liquidity: bool = True,
        save_egarch: bool = False,
        split_date: str = '2023-01-01',
    ) -> None:
        self.df = df.copy()
        self.features: List[str] = features if features is not None else self.DEFAULT_FEATURES
        self.filter_low_liquidity = filter_low_liquidity
        self.save_egarch = save_egarch
        self.split_date = pd.to_datetime(split_date)
        self._volatility_built: bool = False  # evita duplo EGARCH quando build_volatility_features
                                               # é chamado antes de execute_pipeline (feature selection)

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
        self.df['Log_Retorno'] = np.log(self.df['PU'] / self.df.groupby('Ticker')['PU'].shift(1))

        # 3. Reclassificação do Indexador (separa DI% do DI+)
        # Usamos apenas dados In-Sample para evitar data leakage
        mask_is = self.df['Data'] < self.split_date
        medias_taxa_is = self.df[mask_is].groupby('Ticker')['Taxa_Ativo'].mean()
        medias_taxa_full = self.df.groupby('Ticker')['Taxa_Ativo'].transform('mean')
        
        # Mapeia as médias IS e preenche com a média de toda a base (se não houver IS)
        medias_taxa = self.df['Ticker'].map(medias_taxa_is).fillna(medias_taxa_full)

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
        # Calculamos sobre a série ORIGINAL (Spread_Equivalente), sem ffill, 
        # para que o motor não entenda interpolações de liquidez como inércia
        self.df['Delta_Spread'] = self.df.groupby('Ticker')['Spread_Equivalente'].diff()

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
    ) -> Tuple[pd.Series, pd.Series, pd.Series]:
        returns = group_df['Delta_Spread']
        datas   = group_df['Data']

        vol_series = pd.Series(np.nan, index=returns.index)
        var_series = pd.Series(np.nan, index=returns.index)
        es_series  = pd.Series(np.nan, index=returns.index)

        valid_idx = returns.dropna().index
        if len(valid_idx) < 30:
            return vol_series, var_series, es_series

        returns_scaled = returns.loc[valid_idx] * 100
        datas_valid    = datas.loc[valid_idx]

        split_dt  = pd.to_datetime(split_date)
        train_mask = datas_valid < split_dt
        split_idx  = train_mask.sum()

        if split_idx < 25:
            return vol_series, var_series, es_series

        try:
            model = arch_model(
                returns_scaled,
                mean='AR', lags=1,
                #mean='Zero',
                vol='EGARCH', p=1, o=1, q=1,
                dist='t',
                rescale=False,
            )
            res_is  = model.fit(last_obs=split_idx, disp='off', show_warning=False)
            res_oos = model.fix(res_is.params)

            cond_vol  = res_oos.conditional_volatility
            cond_mean = returns_scaled - res_oos.resid
            #cond_mean = 0.0  # Assumimos média zero para o cálculo de risco puro

            nu      = res_is.params.get('nu', 5.0)
            q_alpha = model.distribution.ppf(1 - alpha, nu)
            var_99  = cond_mean + cond_vol * q_alpha
            
            # Expected Shortfall (ES) para t-Student
            # ES_t = pdf(q) / alpha * (nu + q^2) / (nu - 1)
            # Como o modelo usa t padronizada (variância 1), dividimos pelo fator de escala
            q_t = stats.t.ppf(1 - alpha, df=nu)
            es_t = stats.t.pdf(q_t, df=nu) / alpha * (nu + q_t**2) / (nu - 1)
            
            if nu > 2:
                scale = np.sqrt(nu / (nu - 2))
                es_t_padronizado = es_t / scale
                cond_es = cond_mean + cond_vol * es_t_padronizado
            else:
                # O ES diverge ao infinito para nu <= 2 (variância/média infinitas)
                cond_es = pd.Series(np.nan, index=returns_scaled.index)


            if getattr(self, 'save_egarch', False):
                try:
                    ticker = group_df['Ticker'].iloc[0] if 'Ticker' in group_df.columns else 'UNKNOWN'
                    out_dir = dados_dir() / 'egarch'
                    out_dir.mkdir(parents=True, exist_ok=True)
                    
                    with open(out_dir / f"{ticker}_params.txt", 'w') as f:
                        f.write(res_is.summary().as_text())
                    
                    df_series = pd.DataFrame({
                        'Data': datas_valid,
                        'Returns_Scaled': returns_scaled,
                        'Cond_Vol': cond_vol,
                        'Cond_Mean': cond_mean,
                        'VaR_99': var_99,
                        'ES_99': cond_es
                    })
                    df_series.to_csv(out_dir / f"{ticker}_series.csv", index=False)
                except Exception as e:
                    logger.debug(f"Falha ao salvar egarch para {ticker}: {e}")

            vol_series.loc[valid_idx] = cond_vol / 100
            var_series.loc[valid_idx] = var_99  / 100
            es_series.loc[valid_idx]  = cond_es / 100
        except Exception as e:
            logger.debug(f"Falha EGARCH: {e}")
            return vol_series, var_series, es_series

        return vol_series, var_series, es_series

    @staticmethod
    def _kupiec_pof_test(
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

        # Cauda direita: violação ocorre quando retorno (Delta_Spread) é MAIOR que o VaR 99%
        failures   = np.sum(ret > var)
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
        """Estima EGARCH para cada Ticker e preenche Volatilidade_EGARCH, VaR_99 e Expected_Shortfall_99.

        Se já foi chamado anteriormente (flag _volatility_built=True), a função retorna
        imediatamente sem recalcular, evitando duplo EGARCH quando o Feature Selector
        precisa das features antes de execute_pipeline().
        """
        if self._volatility_built:
            logger.info("build_volatility_features() já foi executado — pulando (evita duplo EGARCH).")
            return
        self.df['Volatilidade_EGARCH'] = np.nan
        self.df['VaR_99'] = np.nan
        self.df['Expected_Shortfall_99'] = np.nan

        def run_egarch(group):
            vol, var, es = self._egarch_var(group, split_date)
            return pd.DataFrame({'Volatilidade_EGARCH': vol, 'VaR_99': var, 'Expected_Shortfall_99': es})
        
        # Apply por Ticker
        tqdm.pandas(desc="Calculando EGARCH por Ticker")
        egarch_res = self.df.groupby('Ticker').progress_apply(run_egarch)
        
        # O apply pode retornar um df com multi-index (Ticker, index_original)
        if isinstance(egarch_res.index, pd.MultiIndex):
            egarch_res = egarch_res.reset_index(level=0, drop=True)
            
        # Garante que as colunas existam, descartando as vazias inicializadas e atualizando
        self.df.drop(columns=['Volatilidade_EGARCH', 'VaR_99', 'Expected_Shortfall_99'], inplace=True)
        self.df = self.df.join(egarch_res)
        self._volatility_built = True

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

        O score de risco de cada cluster é calculado como a soma ponderada dos valores
        dos centróides no espaço escalado, com polaridade definida por feature:

        - Polaridade +1.0: valor mais alto = mais risco (ex: Spread, Volatilidade, ES).
        - Polaridade -1.0: valor mais alto = menos risco (ex: Score_Liquidez, onde
          liquidez alta indica menor risco estrutural).

        Isso garante que o mapeamento Verde → Amarelo → Vermelho seja semanticamente
        correto para qualquer combinação de features, inclusive aquelas sem a palavra
        'ZScore' ou 'Volatilidade' no nome (como Expected_Shortfall_99).

        Se nenhuma feature for reconhecida no dicionário, o fallback soma todos os
        centróides com polaridade +1 (comportamento anterior).
        """
        # Dicionário de polaridade semântica por feature.
        # Escopés cobertas: todas as candidatas em DEFAULT_CANDIDATE_FEATURES
        # e Score_Liquidez (mantida aqui por robustez, caso seja passada externamente).
        FEATURE_POLARITY: Dict[str, float] = {
            'Taxa_ZScore':            +1.0,  # spread acima da média histórica = risco
            'Volatilidade_EGARCH':    +1.0,  # volatilidade condicional = risco
            'VaR_99':                 +1.0,  # VaR 99% (valor negativo maior em módulo = mais risco)
            'Expected_Shortfall_99':  +1.0,  # ES: perda esperada além do VaR = risco
            'Spread_Equivalente':     +1.0,  # spread absoluto alto = mais risco
            'Taxa_Ajustada_Prazo':    +1.0,  # prêmio ajustado pela duration alto = mais risco
            'Score_Liquidez':         -1.0,  # liquidez alta → menos risco estrutural (sentido inverso)
        }

        n_clusters = centers.shape[0]
        risk_scores = np.zeros(n_clusters)
        matched = False

        for i, feat in enumerate(feature_names):
            polarity = FEATURE_POLARITY.get(feat)
            if polarity is not None:
                risk_scores += centers[:, i] * polarity
                matched = True

        # Fallback: se nenhuma feature for reconhecida, soma todos os centróides com +1.
        # Emite aviso para facilitar a depuração quando novas features forem adicionadas.
        if not matched:
            logger.warning(
                f"[_label_switching_correction] Nenhuma feature reconhecida no dicionário "
                f"de polaridade: {feature_names}. Usando fallback (soma de todos os centróides)."
            )
            risk_scores = centers.sum(axis=1)

        sorted_ids  = np.argsort(risk_scores)          # menor score → Verde; maior → Vermelho
        label_names = ['Verde', 'Amarelo', 'Vermelho']
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
            distances = kmeans.transform(X_val_sc)

            # Cálculo da distância relativa para o centróide 'Vermelho' (K-Means)
            try:
                red_idx = next(k for k, v in cluster_map.items() if v == 'Vermelho')
                sum_dists = distances.sum(axis=1)
                prob_kmeans = 1.0 - (distances[:, red_idx] / np.maximum(sum_dists, 1e-9))
            except StopIteration:
                prob_kmeans = np.nan

            resultado = val_grupo[['Ticker', 'Data', 'Indexador_Grupo']].copy()
            resultado['Cluster_KMeans'] = [cluster_map[c] for c in raw_labels]
            resultado['Prob_Crise_KMeans'] = prob_kmeans
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
        Treina um GaussianHMM globalmente por 'Indexador_Grupo' (painel de dados),
        mas preserva a ordem temporal das observações de cada Ticker.
        
        Isso permite que o HMM aprenda regimes macroeconômicos consistentes
        (assim como o K-Means), mas aplique probabilidades de transição adequadas.

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

        train_df = df_clean[df_clean['Data'] < split_dt]
        val_df   = df_clean[df_clean['Data'] >= split_dt]

        all_results: List[pd.DataFrame] = []

        for grupo, train_grupo in train_df.groupby('Indexador_Grupo'):
            
            # 1. Prepara dados de treino em Painel (múltiplos Tickers)
            X_train_list = []
            lengths = []
            
            # Usa um único Scaler global por Grupo (mesmo comportamento do K-Means)
            scaler = RobustScaler()
            
            for ticker, df_t in train_grupo.sort_values(['Ticker', 'Data']).groupby('Ticker'):
                X_t = df_t[feats].values
                if len(X_t) > 0:
                    X_train_list.append(X_t)
                    lengths.append(len(X_t))
            
            if not X_train_list:
                logger.warning(f"[HMM] Grupo '{grupo}': sem dados IS. Pulando.")
                continue
                
            X_train_arr = np.vstack(X_train_list)
            
            if len(X_train_arr) < 3:
                logger.warning(f"[HMM] Grupo '{grupo}': dados insuficientes no IS. Pulando.")
                continue
                
            # Escala e treina
            X_train_sc = scaler.fit_transform(X_train_arr)
            
            try:
                hmm = GaussianHMM(
                    n_components=3,
                    covariance_type='diag',  # Alterado de 'full' para 'diag' para evitar overfitting ao ruído
                    n_iter=100,
                    random_state=42,
                )
                hmm.fit(X_train_sc, lengths)
                
                # Mapeia estados
                cluster_map = self._label_switching_correction(hmm.means_, feats)
                vermelho_id = next((k for k, v in cluster_map.items() if v == 'Vermelho'), 2)
                
            except Exception as exc:
                logger.warning(f"[HMM] Grupo '{grupo}': falha na convergência global — {exc}")
                continue

            # -----------------------------------------------------------------------
            # CORREÇÃO PÓS-FIT: Recalibração da Matriz de Transição sem Bordas Inter-Ticker
            # -----------------------------------------------------------------------
            # PROBLEMA CONHECIDO DO hmmlearn:
            # O método fit() do GaussianHMM aceita o parâmetro `lengths` para indicar onde
            # cada sequência individual começa e termina dentro do array concatenado. Isso
            # garante que o E-step (decodificação via Viterbi / forward-backward) respeite
            # os limites de cada Ticker.
            #
            # No entanto, o M-step (atualização dos parâmetros via Expectation-Maximization)
            # ainda acumula pseudo-contagens de transição incluindo o par:
            #   (ultimo_estado_ticker_i, primeiro_estado_ticker_{i+1})
            # Esse par não representa uma transição real, pois pertence a ativos distintos,
            # e contamina a estimativa da matriz transmat_.
            #
            # Ref: Serafini, A. et al. (Issue #289, hmmlearn GitHub, 2016).
            #      "GaussianHMM.fit ignores sequence boundaries in M-step".
            #      Disponível em: https://github.com/hmmlearn/hmmlearn/issues/289
            #      (Acessado em julho de 2026.)
            #
            # Ref: Bilmes, J. (1998). "A gentle tutorial of the EM algorithm and its
            #      application to parameter estimation for Gaussian mixture and hidden
            #      Markov models". ICSI Technical Report TR-97-021. University of
            #      California, Berkeley.
            #
            # ESTRATÉGIA DE CORREÇÃO (sem trocar de biblioteca):
            # 1. Decodificar os estados IS com o modelo treinado.
            # 2. Recontabilizar as transições apenas dentro de cada Ticker (excluindo bordas).
            # 3. Normalizar por linha e sobrescrever hmm.transmat_.
            #
            # Efeito esperado: a diagonal principal (auto-transições) sobe, refletindo a
            # persistência real dos regimes intra-ativo. O sinal de Early Warning melhora
            # porque o Vermelho de um ativo em crise tem maior probabilidade de permanecer
            # Vermelho no período seguinte.
            # -----------------------------------------------------------------------
            try:
                states_is = hmm.predict(X_train_sc, lengths)
                n_states   = hmm.n_components
                trans_counts = np.zeros((n_states, n_states))

                pos = 0
                for length in lengths:
                    seq = states_is[pos : pos + length]
                    # Itera apenas sobre transições DENTRO do Ticker (range exclui borda)
                    for t in range(len(seq) - 1):
                        trans_counts[seq[t], seq[t + 1]] += 1
                    pos += length

                # Laplace smoothing (1e-6) para evitar linhas com soma zero
                trans_counts += 1e-6
                hmm.transmat_ = trans_counts / trans_counts.sum(axis=1, keepdims=True)

                logger.debug(
                    f"[HMM] Grupo '{grupo}': transmat_ recalibrada sem bordas inter-ticker.\n"
                    f"{np.round(hmm.transmat_, 3)}"
                )
            except Exception as exc_tm:
                logger.warning(
                    f"[HMM] Grupo '{grupo}': falha na recalibração de transmat_ — "
                    f"{exc_tm}. Mantendo transmat_ original do fit()."
                )
            # -----------------------------------------------------------------------

            # 2. Predição OOS com Memória Temporal (Viterbi Contínuo)
            val_grupo = val_df[val_df['Indexador_Grupo'] == grupo]
            if val_grupo.empty:
                logger.warning(f"[HMM] Grupo '{grupo}': sem dados OOS.")
                continue
                
            for ticker, df_t_oos in val_grupo.sort_values(['Ticker', 'Data']).groupby('Ticker'):
                result_base = df_t_oos[['Ticker', 'Data', 'Indexador_Grupo']].copy()
                
                # Busca o histórico In-Sample desse ticker para não quebrar a cadeia de Markov
                df_t_is = train_df[(train_df['Indexador_Grupo'] == grupo) & (train_df['Ticker'] == ticker)]
                
                # Concatena a história completa do ativo
                df_t_full = pd.concat([df_t_is, df_t_oos]).sort_values('Data')
                X_full = df_t_full[feats].values
                
                if len(df_t_oos) == 0:
                    continue
                    
                try:
                    X_full_sc = scaler.transform(X_full)
                    # Prediz a série inteira para que o Viterbi flua do IS para o OOS
                    raw_states_full = hmm.predict(X_full_sc)
                    proba_mat_full  = hmm.predict_proba(X_full_sc)
                    
                    # Fatiamos apenas as últimas observações correspondentes ao OOS
                    n_oos = len(df_t_oos)
                    raw_states = raw_states_full[-n_oos:]
                    proba_mat  = proba_mat_full[-n_oos:]
                    
                    result_base['Cluster_HMM'] = [cluster_map[s] for s in raw_states]
                    result_base['Prob_Crise_HMM'] = proba_mat[:, vermelho_id]
                except Exception as exc:
                    result_base['Cluster_HMM']    = 'Inconclusivo'
                    result_base['Prob_Crise_HMM'] = np.nan
                    
                all_results.append(result_base)

            logger.info(f"[HMM] Grupo '{grupo}': Treinado com {len(X_train_arr)} obs. "
                        f"Predito {len(val_grupo)} obs OOS.")

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
            # 1. Ensemble Score: Ponderação 70% HMM e 30% K-Means
            if 'Prob_Crise_HMM' in df_clusters.columns and 'Prob_Crise_KMeans' in df_clusters.columns:
                df_clusters['Credit_Tail_Risk_Score'] = (
                    (0.70 * df_clusters['Prob_Crise_HMM'].fillna(0)) + 
                    (0.30 * df_clusters['Prob_Crise_KMeans'].fillna(0))
                ) * 100
                
                # Suavização Exponencial (EMA) de 10 períodos agrupada por Ticker para remover o ruído
                df_clusters = df_clusters.sort_values(by=['Ticker', 'Data'])
                df_clusters['Credit_Tail_Risk_Score'] = df_clusters.groupby('Ticker')['Credit_Tail_Risk_Score'].transform(
                    lambda x: x.ewm(span=10, min_periods=1, adjust=False).mean()
                )

            aux_cols = ['Ticker', 'Data', 'Taxa_ZScore', 'Volatilidade_EGARCH',
                        'Taxa_Ajustada_Prazo', 'Score_Liquidez', 'VaR_99', 'Expected_Shortfall_99', 'PU', 'Taxa_Ativo', 'Delta_Spread']
            aux_cols = [c for c in aux_cols if c in self.df.columns]
            df_aux = self.df[aux_cols].drop_duplicates(subset=['Ticker', 'Data'])
            df_clusters = pd.merge(df_clusters, df_aux, on=['Ticker', 'Data'], how='left')

        return self.df, df_clusters
