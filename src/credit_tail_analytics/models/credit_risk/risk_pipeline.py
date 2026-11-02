import pandas as pd
import numpy as np
from typing import Dict, List, Tuple, Optional
import warnings
import logging

from credit_tail_analytics.models.credit_risk.preprocessor import DataPreprocessor
from credit_tail_analytics.models.credit_risk.volatility import VolatilityEstimator
from credit_tail_analytics.models.credit_risk.regime import RegimeClassifier

warnings.filterwarnings("ignore", category=FutureWarning)
warnings.filterwarnings("ignore", category=UserWarning)
logger = logging.getLogger(__name__)

class CreditRiskEngine:
    """
    Motor quantitativo para modelagem de risco de cauda e identificação de regimes de crédito 
    (Credit Regime Switching) em debêntures do mercado secundário brasileiro.

    Implementa um pipeline econométrico completo ("End-to-End"):
    1. Feature Engineering e Tratamento de Microestrutura (DataPreprocessor).
    2. Modelagem da Volatilidade Condicional e VaR/ES (VolatilityEstimator).
    3. Inferência de Regimes Latentes com K-Means e HMM (RegimeClassifier).

    Parâmetros
    ----------
    df : pd.DataFrame
        Base diária de debêntures com as colunas obrigatórias.
    features : list, optional
        Features usadas pelos modelos de clusterização.
    filter_low_liquidity : bool, default True
        Elimina zeros artificiais de marcação na curva removendo Faixa 3 da ANBIMA.
    """

    DEFAULT_FEATURES: List[str] = ['Taxa_ZScore', 'Volatilidade_EGARCH']

    def __init__(
        self,
        df: pd.DataFrame,
        features: Optional[List[str]] = None,
        filter_low_liquidity: bool = True,
        save_egarch: bool = False,
        split_date: str = '2023-01-01',
        individual_scaling: bool = True,
    ) -> None:
        self.features: List[str] = features if features is not None else self.DEFAULT_FEATURES
        self.split_date = split_date
        self.individual_scaling = individual_scaling

        # Instanciação dos componentes (Composição)
        self.preprocessor = DataPreprocessor(
            filter_low_liquidity=filter_low_liquidity,
            split_date=split_date
        )
        self.volatility_estimator = VolatilityEstimator(save_egarch=save_egarch)
        self.regime_classifier = RegimeClassifier(individual_scaling=individual_scaling)
        
        # O processamento inicial e feature engineering acontecem no init para preservar comportamento
        self.df = self.preprocessor.process(df)

    @property
    def clustering_models(self) -> Dict[str, Dict]:
        """Expõe os modelos de clusterização ajustados para compatibilidade com a API anterior."""
        return self.regime_classifier.clustering_models

    def build_volatility_features(self, split_date: str) -> None:
        """Delega a extração de volatilidade condicional ao VolatilityEstimator."""
        self.df = self.volatility_estimator.build_volatility_features(self.df, split_date)

    def run_kmeans_regimes(
        self,
        split_date: str,
        features: Optional[List[str]] = None,
    ) -> pd.DataFrame:
        feats = features if features is not None else self.features
        return self.regime_classifier.run_kmeans_regimes(self.df, split_date, feats)

    def run_hmm_regimes(
        self,
        split_date: str,
        features: Optional[List[str]] = None,
    ) -> pd.DataFrame:
        feats = features if features is not None else self.features
        return self.regime_classifier.run_hmm_regimes(self.df, split_date, feats)

    def execute_pipeline(
        self,
        split_date: str = '2023-01-01',
        model_type: str = 'both',
        features: Optional[List[str]] = None,
    ) -> Tuple[pd.DataFrame, pd.DataFrame]:
        """
        Executa o pipeline completo: EGARCH → clusterização (K-Means e/ou HMM).
        """
        if model_type not in ('kmeans', 'hmm', 'both'):
            raise ValueError(f"model_type deve ser 'kmeans', 'hmm' ou 'both'. Recebido: {model_type}")

        feats = features if features is not None else self.features

        logger.info(f"Construindo features de volatilidade (split_date={split_date})...")
        self.build_volatility_features(split_date)

        df_kmeans: Optional[pd.DataFrame] = None
        df_hmm:    Optional[pd.DataFrame] = None

        if model_type in ('kmeans', 'both'):
            logger.info("Executando K-Means (baseline atemporal)...")
            df_kmeans = self.run_kmeans_regimes(split_date, features=feats)

        if model_type in ('hmm', 'both'):
            logger.info("Executando HMM (modelo com memória temporal)...")
            df_hmm = self.run_hmm_regimes(split_date, features=feats)

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
            # --- Pesos do Ensemble Otimizados (In-Sample) ---
            # Os pesos de 0.70 para o HMM e 0.30 para o K-Means foram encontrados 
            # de forma estritamente empírica através de uma otimização de Grid-Search 
            # rodada APENAS na janela In-Sample (antes de 2023-01-01), maximizando o 
            # Calmar Ratio do Backtest Financeiro. Isso elimina o Data Snooping.
            w_hmm, w_kmeans = 0.70, 0.30

            # Ensemble Score ponderado pelos pesos otimizados
            if 'Prob_Crise_HMM' in df_clusters.columns and 'Prob_Crise_KMeans' in df_clusters.columns:
                df_clusters['Credit_Tail_Risk_Score'] = (
                    (w_hmm * df_clusters['Prob_Crise_HMM'].fillna(0)) +
                    (w_kmeans * df_clusters['Prob_Crise_KMeans'].fillna(0))
                ) * 100

                # Filtro de Suavização Exponencial (EMA) de 21 períodos agrupado por Ticker para mitigação de ruído microestrutural.
                df_clusters = df_clusters.sort_values(by=['Ticker', 'Data'])
                df_clusters['Credit_Tail_Risk_Score'] = df_clusters.groupby('Ticker')['Credit_Tail_Risk_Score'].transform(
                    lambda x: x.ewm(span=21, min_periods=1, adjust=False).mean()
                )

            aux_cols = ['Ticker', 'Data', 'Taxa_ZScore', 'Volatilidade_EGARCH',
                        'Taxa_Ajustada_Prazo', 'Score_Liquidez', 'VaR_99', 'Expected_Shortfall_99', 'PU', 'Taxa_Ativo', 'Delta_Spread', 'Valor_Evento']
            aux_cols = [c for c in aux_cols if c in self.df.columns]
            df_aux = self.df[aux_cols].drop_duplicates(subset=['Ticker', 'Data'])
            df_clusters = pd.merge(df_clusters, df_aux, on=['Ticker', 'Data'], how='left')

        return self.df, df_clusters
