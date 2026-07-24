import numpy as np
import pandas as pd
import logging
from typing import Dict
from credit_tail_analytics.utils import dados_dir

logger = logging.getLogger(__name__)

INDEXADOR_GRUPO_MAP = {
    'DI_SPREAD':      'CDI_Spread',
    'DI_PERCENTUAL':  'CDI_Percentual',
    'IPCA':           'IPCA',
    'IGPM':           'IGPM',
    'PRE':            'PRE',
}

INDEXADOR_OUTRO = 'Outro'


class DataPreprocessor:
    def __init__(
        self,
        filter_low_liquidity: bool = True,
        split_date: str = '2023-01-01',
    ) -> None:
        self.filter_low_liquidity = filter_low_liquidity
        self.split_date = pd.to_datetime(split_date)
        
        # volume_map: Score_Liquidez mais alto = mais líquido
        self.volume_map: Dict[str, int] = {
            'Até 1MM':         1,   # Faixa 3 ANBIMA — excluída quando filter_low_liquidity=True
            'Entre 1MM e 5MM': 2,
            'Superior a 5MM':  3,
        }

    def process(self, df: pd.DataFrame) -> pd.DataFrame:
        df = self._validate_input(df)
        df = self._feature_engineering(df)
        return df

    def _validate_input(self, df: pd.DataFrame) -> pd.DataFrame:
        df = df.copy()
        required_columns = [
            'Data', 'Ticker', 'Indexador', 'PU',
            'Faixa_Volume_ANBIMA', 'Taxa_Ativo', 'DU_Vencimento'
        ]
        missing = [col for col in required_columns if col not in df.columns]
        if missing:
            raise ValueError(f"Colunas obrigatórias ausentes: {missing}")

        df['Data'] = pd.to_datetime(df['Data'])
        df.sort_values(by=['Ticker', 'Data'], inplace=True)
        df.reset_index(drop=True, inplace=True)
        return df

    def _feature_engineering(self, df: pd.DataFrame) -> pd.DataFrame:
        # 1. Score de liquidez
        df['Score_Liquidez'] = (
            df['Faixa_Volume_ANBIMA'].map(self.volume_map).fillna(1).astype(int)
        )

        # 2. Log-retorno do PU
        df['Log_Retorno'] = np.log(df['PU'] / df.groupby('Ticker')['PU'].shift(1))

        # 3. Reclassificação do Indexador (separa DI% do DI+)
        # Usamos apenas dados In-Sample para evitar data leakage
        mask_is = df['Data'] < self.split_date
        medias_taxa_is = df[mask_is].groupby('Ticker')['Taxa_Ativo'].mean()
        medias_taxa_full = df.groupby('Ticker')['Taxa_Ativo'].transform('mean')
        
        # Mapeia as médias IS e preenche com a média de toda a base (se não houver IS)
        medias_taxa = df['Ticker'].map(medias_taxa_is).fillna(medias_taxa_full)

        is_di = df['Indexador'].str.upper() == 'DI'
        is_percent = medias_taxa > 30
        df.loc[is_di & is_percent,  'Indexador'] = 'DI_Percentual'
        df.loc[is_di & ~is_percent, 'Indexador'] = 'DI_Spread'

        # 4. Dados macroeconômicos (CDI, IPCA, IGPM)
        logger.info("Carregando dados macroeconômicos (dados/macro_data.csv)...")
        try:
            macro_path = str(dados_dir() / 'macro_data.csv')
            df_macro = pd.read_csv(macro_path)
            df_macro['Data'] = pd.to_datetime(df_macro['Data'])
            df = pd.merge(df, df_macro, on='Data', how='left')
            df['CDI_Anual']    = df['CDI_Anual'].ffill()
            df['IPCA_Mensal']  = df['IPCA_Mensal'].ffill()
            df['IGPM_Mensal']  = df['IGPM_Mensal'].ffill()
        except Exception as e:
            logger.warning(f"Falha ao carregar dados macroeconômicos. Erro: {e}")
            df['CDI_Anual']   = 10.4
            df['IPCA_Mensal'] = 0.5
            df['IGPM_Mensal'] = 0.5

        # 5b. Grupo canônico por indexador
        df['Indexador_Grupo'] = (
            df['Indexador']
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

        df['Spread_Equivalente'] = df.apply(calc_spread, axis=1)

        # 7. Taxa ajustada pelo prazo
        du_seguro = np.maximum(df['DU_Vencimento'], 2)
        df['Taxa_Ajustada_Prazo'] = df['Spread_Equivalente'] / np.log(du_seguro)

        # 8. Spread com forward-fill + Z-Score rolante (janela 60 dias)
        df['Spread_Ffill'] = df.groupby('Ticker')['Spread_Equivalente'].ffill()

        def calc_zscore(x):
            r = x.rolling(window=60, min_periods=10)
            return (x - r.mean()) / r.std().replace(0, np.nan)

        df['Taxa_ZScore'] = (
            df.groupby('Ticker')['Spread_Ffill']
            .transform(calc_zscore)
            .fillna(0)
        )

        # 9. Delta_Spread — input do EGARCH
        df['Delta_Spread'] = df.groupby('Ticker')['Spread_Equivalente'].diff()

        # 10. Filtro de liquidez: zera observações de baixa liquidez (Faixa 3 ANBIMA)
        if self.filter_low_liquidity:
            mask_baixa = df['Score_Liquidez'] == 1
            n_removidos = mask_baixa.sum()
            df.loc[mask_baixa, 'Delta_Spread'] = np.nan
            logger.info(
                f"Filtro de liquidez (Faixa 3 ANBIMA): {n_removidos} observações "
                f"removidas do Delta_Spread antes do EGARCH."
            )

        return df
