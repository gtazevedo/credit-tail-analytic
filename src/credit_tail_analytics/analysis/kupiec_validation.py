import os
import logging
import pandas as pd
import numpy as np
from credit_tail_analytics.utils import dados_dir
from credit_tail_analytics.models.credit_risk.risk_pipeline import CreditRiskEngine

logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')
logger = logging.getLogger('KupiecValidation')


class KupiecValidator:
    """
    Executa a validação estatística (Teste POF de Kupiec) para o VaR condicional de 99%
    gerado pelo EGARCH na base de debêntures, focando no período Out-of-Sample (OOS).
    """

    def __init__(self, df_resultados: pd.DataFrame, split_date: str = '2023-01-01', confidence_level: float = 0.99):
        self.df = df_resultados.copy()
        self.split_date = pd.to_datetime(split_date)
        self.confidence_level = confidence_level
        self.alpha = 1.0 - confidence_level

        if 'Data' in self.df.columns:
            self.df['Data'] = pd.to_datetime(self.df['Data'])
            
        # Filtra apenas Out-of-Sample
        self.df_oos = self.df[self.df['Data'] >= self.split_date].copy()

    def run_validation(self) -> pd.DataFrame:
        """Roda o teste de Kupiec agrupado por Indexador_Grupo e Ticker."""
        logger.info(f"Iniciando validação de Kupiec (OOS a partir de {self.split_date.date()})...")

        req_cols = ['Ticker', 'Indexador_Grupo', 'Delta_Spread', 'VaR_99']
        missing = [c for c in req_cols if c not in self.df_oos.columns]
        if missing:
            logger.error(f"Colunas ausentes no DataFrame: {missing}. O teste não pode prosseguir.")
            return pd.DataFrame()

        # Removemos nans
        df_valid = self.df_oos.dropna(subset=['Delta_Spread', 'VaR_99'])

        resultados = []

        for (grupo, ticker), df_t in df_valid.groupby(['Indexador_Grupo', 'Ticker']):
            n_obs = len(df_t)
            if n_obs < 10:
                continue

            failures = np.sum(df_t['Delta_Spread'] > df_t['VaR_99'])
            expected = n_obs * self.alpha
            
            p_value = CreditRiskEngine._kupiec_pof_test(
                retornos=df_t['Delta_Spread'],
                var_limits=df_t['VaR_99'],
                nivel_confianca=self.confidence_level
            )
            
            # Rejeitamos a hipótese nula se p_value < 0.05
            valido = 'SIM' if (p_value >= 0.05 or pd.isna(p_value)) else 'NÃO'
            
            resultados.append({
                'Indexador_Grupo': grupo,
                'Ticker': ticker,
                'N_Observacoes': n_obs,
                'Falhas_Esperadas': round(expected, 2),
                'Falhas_Reais': failures,
                'P_Valor': round(p_value, 4) if not pd.isna(p_value) else np.nan,
                'Modelo_Valido': valido
            })

        df_res = pd.DataFrame(resultados)
        
        # Consolidação geral
        n_total = df_res['N_Observacoes'].sum()
        fail_total = df_res['Falhas_Reais'].sum()
        fail_exp = df_res['Falhas_Esperadas'].sum()
        logger.info(f"Validação Completa | Obs OOS: {n_total} | Falhas Reais: {fail_total} | Esperadas: {fail_exp:.2f}")

        out_path = dados_dir() / 'kupiec_test_results.csv'
        df_res.to_csv(out_path, index=False)
        logger.info(f"Resultados detalhados salvos em {out_path}")
        
        return df_res

if __name__ == '__main__':
    res_path = dados_dir() / 'resultado_frequentist_engine.csv'
    if res_path.exists():
        df_engine = pd.read_csv(res_path)
        validator = KupiecValidator(df_engine)
        validator.run_validation()
    else:
        logger.error(f"Arquivo não encontrado: {res_path}")
