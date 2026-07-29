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
            
            from credit_tail_analytics.models.credit_risk.volatility import VolatilityEstimator
            p_value_pof = VolatilityEstimator._kupiec_pof_test(
                retornos=df_t['Delta_Spread'],
                var_limits=df_t['VaR_99'],
                nivel_confianca=self.confidence_level
            )
            
            p_value_cc = self._christoffersen_cc_test(
                retornos=df_t['Delta_Spread'].values,
                var_limits=df_t['VaR_99'].values,
            )

            p_value_joint = self._joint_test(
                retornos=df_t['Delta_Spread'].values,
                var_limits=df_t['VaR_99'].values,
                nivel_confianca=self.confidence_level,
            )

            # Rejeitamos a hipótese nula se p_value < 0.05
            valido_pof  = 'SIM' if (pd.isna(p_value_pof)  or p_value_pof  >= 0.05) else 'NÃO'
            valido_cc   = 'SIM' if (pd.isna(p_value_cc)   or p_value_cc   >= 0.05) else 'NÃO'
            valido_joint = 'SIM' if (pd.isna(p_value_joint) or p_value_joint >= 0.05) else 'NÃO'
            
            resultados.append({
                'Indexador_Grupo':  grupo,
                'Ticker':           ticker,
                'N_Observacoes':    n_obs,
                'Falhas_Esperadas': round(expected, 2),
                'Falhas_Reais':     failures,
                # POF — Proportion of Failures (Kupiec, 1995)
                'P_Valor_POF':      round(p_value_pof,   4) if not pd.isna(p_value_pof)   else np.nan,
                'POF_Valido':       valido_pof,
                # CC — Conditional Coverage (Christoffersen, 1998)
                'P_Valor_CC':       round(p_value_cc,    4) if not pd.isna(p_value_cc)    else np.nan,
                'CC_Valido':        valido_cc,
                # Joint = POF ∩ CC (χ² com 2 g.l.)
                'P_Valor_Joint':    round(p_value_joint, 4) if not pd.isna(p_value_joint) else np.nan,
                'Joint_Valido':     valido_joint,
            })

        df_res = pd.DataFrame(resultados)

        if df_res.empty:
            logger.warning("Nenhum ticker com observações suficientes para validação.")
            return df_res
        
        # Consolidação geral
        n_total    = df_res['N_Observacoes'].sum()
        fail_total = df_res['Falhas_Reais'].sum()
        fail_exp   = df_res['Falhas_Esperadas'].sum()
        pct_valido_pof   = (df_res['POF_Valido']   == 'SIM').mean() * 100
        pct_valido_cc    = (df_res['CC_Valido']    == 'SIM').mean() * 100
        pct_valido_joint = (df_res['Joint_Valido'] == 'SIM').mean() * 100

        logger.info(
            f"Validação Completa | Obs OOS: {n_total} | Falhas Reais: {fail_total} | "
            f"Esperadas: {fail_exp:.2f}"
        )
        logger.info(
            f"Taxa de aprovação → POF: {pct_valido_pof:.1f}% | "
            f"CC: {pct_valido_cc:.1f}% | Joint: {pct_valido_joint:.1f}%"
        )

        # Também mantém coluna legada 'Modelo_Valido' (= Joint_Valido) para compatibilidade
        df_res['Modelo_Valido'] = df_res['Joint_Valido']

        out_path = dados_dir() / 'kupiec_test_results.csv'
        df_res.to_csv(out_path, index=False)
        logger.info(f"Resultados detalhados salvos em {out_path}")
        
        return df_res

    # ------------------------------------------------------------------
    # Teste de Christoffersen (1998) — Independência Condicional (CC)
    # ------------------------------------------------------------------
    @staticmethod
    def _christoffersen_cc_test(
        retornos: np.ndarray,
        var_limits: np.ndarray,
    ) -> float:
        """
        Teste de Cobertura Condicional de Christoffersen (1998).

        Verifica se as violações do VaR são *serialmente independentes*, ou seja,
        se a probabilidade de uma violação hoje não depende de ter havido violação ontem.
        Uma sequência de violações agrupadas no tempo (clustering) viola essa hipótese —
        situação comum em períodos de estresse que um bom modelo deveria capturar.

        H0: π_01 = π_11  (independência)
        LR_cc ~ χ²(1)

        Ref: Christoffersen, P.F. (1998). "Evaluating interval forecasts".
             International Economic Review, 39(4), 841–862.

        Parâmetros
        ----------
        retornos   : np.ndarray — série de retornos/Delta_Spread
        var_limits : np.ndarray — série de limites VaR

        Retorna
        -------
        float : p-valor do teste CC (NaN se não há violações suficientes)
        """
        import scipy.stats as stats

        ret = np.asarray(retornos)
        var = np.asarray(var_limits)
        mask = ~np.isnan(ret) & ~np.isnan(var)
        ret, var = ret[mask], var[mask]
        n = len(ret)
        if n < 2:
            return np.nan

        # Sequência binária de violações (1 = violou, 0 = não violou)
        hits = (ret > var).astype(int)

        # Contagens da matriz de transição 2x2
        n00 = np.sum((hits[:-1] == 0) & (hits[1:] == 0))  # 0 → 0
        n01 = np.sum((hits[:-1] == 0) & (hits[1:] == 1))  # 0 → 1
        n10 = np.sum((hits[:-1] == 1) & (hits[1:] == 0))  # 1 → 0
        n11 = np.sum((hits[:-1] == 1) & (hits[1:] == 1))  # 1 → 1

        # Probabilidades de transição
        total_0 = n00 + n01
        total_1 = n10 + n11

        if total_0 == 0 or total_1 == 0:
            return np.nan  # Todos violaram ou nenhum violou

        pi_01 = n01 / total_0   # P(violação | sem violação ontem)
        pi_11 = n11 / total_1   # P(violação | com violação ontem)
        pi    = (n01 + n11) / (n - 1)  # Probabilidade marginal de violação

        # Verossimilhança H0 (independência: pi_01 = pi_11 = pi)
        if pi <= 0 or pi >= 1:
            return np.nan
        log_L0 = (
            (n00 + n10) * np.log(1 - pi) +
            (n01 + n11) * np.log(pi)
        )

        # Verossimilhança H1 (transições distintas)
        eps = 1e-12
        pi_01_c = np.clip(pi_01, eps, 1 - eps)
        pi_11_c = np.clip(pi_11, eps, 1 - eps)
        log_L1 = (
            n00 * np.log(1 - pi_01_c) + n01 * np.log(pi_01_c) +
            n10 * np.log(1 - pi_11_c) + n11 * np.log(pi_11_c)
        )

        lr_cc = -2 * (log_L0 - log_L1)
        if lr_cc < 0:
            lr_cc = 0.0

        return float(1.0 - stats.chi2.cdf(lr_cc, df=1))

    # ------------------------------------------------------------------
    # Joint Test: POF + CC  (χ² com 2 graus de liberdade)
    # ------------------------------------------------------------------
    @staticmethod
    def _joint_test(
        retornos: np.ndarray,
        var_limits: np.ndarray,
        nivel_confianca: float = 0.99,
    ) -> float:
        """
        Teste conjunto de cobertura incondicional (POF) e independência condicional (CC).

        LR_joint = LR_pof + LR_cc  ~  χ²(2)

        Ref: Christoffersen (1998), eq. 10.

        Parâmetros
        ----------
        retornos        : np.ndarray
        var_limits      : np.ndarray
        nivel_confianca : float

        Retorna
        -------
        float : p-valor do teste conjunto (NaN se inválido)
        """
        import scipy.stats as stats
        from credit_tail_analytics.models.credit_risk.volatility import VolatilityEstimator

        ret = np.asarray(retornos)
        var = np.asarray(var_limits)
        mask = ~np.isnan(ret) & ~np.isnan(var)
        ret, var = ret[mask], var[mask]
        n = len(ret)
        if n < 2:
            return np.nan

        alpha      = 1.0 - nivel_confianca
        failures   = np.sum(ret > var)
        p_expected = alpha

        # --- LR_pof (replicado inline para evitar importação circular) ---
        if failures == 0:
            lr_pof = -2 * n * np.log(1 - p_expected)
        else:
            failure_rate = failures / n
            if failure_rate >= 1.0:
                lr_pof = -2 * n * np.log(p_expected)
            else:
                num = ((1 - p_expected) ** (n - failures)) * (p_expected ** failures)
                den = ((1 - failure_rate) ** (n - failures)) * (failure_rate ** failures)
                if den <= 0 or num <= 0:
                    return np.nan
                lr_pof = -2 * np.log(num / den)

        # --- LR_cc ---
        hits = (ret > var).astype(int)
        n00 = np.sum((hits[:-1] == 0) & (hits[1:] == 0))
        n01 = np.sum((hits[:-1] == 0) & (hits[1:] == 1))
        n10 = np.sum((hits[:-1] == 1) & (hits[1:] == 0))
        n11 = np.sum((hits[:-1] == 1) & (hits[1:] == 1))

        total_0 = n00 + n01
        total_1 = n10 + n11
        if total_0 == 0 or total_1 == 0:
            return np.nan

        pi_01 = n01 / total_0
        pi_11 = n11 / total_1
        pi    = (n01 + n11) / (n - 1)

        if pi <= 0 or pi >= 1:
            return np.nan

        log_L0 = (n00 + n10) * np.log(1 - pi) + (n01 + n11) * np.log(pi)
        eps     = 1e-12
        log_L1  = (
            n00 * np.log(np.clip(1 - pi_01, eps, 1)) + n01 * np.log(np.clip(pi_01, eps, 1)) +
            n10 * np.log(np.clip(1 - pi_11, eps, 1)) + n11 * np.log(np.clip(pi_11, eps, 1))
        )
        lr_cc = max(-2 * (log_L0 - log_L1), 0.0)

        lr_joint = lr_pof + lr_cc
        return float(1.0 - stats.chi2.cdf(lr_joint, df=2))


if __name__ == '__main__':
    res_path = dados_dir() / 'resultado_frequentist_engine.csv'
    if res_path.exists():
        df_engine = pd.read_csv(res_path)
        validator = KupiecValidator(df_engine)
        validator.run_validation()
    else:
        logger.error(f"Arquivo não encontrado: {res_path}")
