import numpy as np
import pandas as pd
import scipy.stats as stats
from arch import arch_model
from typing import Tuple, Union
import logging
from credit_tail_analytics.utils import dados_dir
from tqdm import tqdm

logger = logging.getLogger(__name__)

class VolatilityEstimator:
    def __init__(self, save_egarch: bool = False):
        self.save_egarch = save_egarch
        self._volatility_built: bool = False

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
                vol='EGARCH', p=1, o=1, q=1,
                dist='t',
                rescale=False,
            )
            res_is  = model.fit(last_obs=split_idx, disp='off', show_warning=False)
            res_oos = model.fix(res_is.params)

            cond_vol  = res_oos.conditional_volatility
            cond_mean = returns_scaled - res_oos.resid

            nu      = res_is.params.get('nu', 5.0)
            q_alpha = model.distribution.ppf(1 - alpha, nu)
            var_99  = cond_mean + cond_vol * q_alpha
            
            q_t = stats.t.ppf(1 - alpha, df=nu)
            es_t = stats.t.pdf(q_t, df=nu) / alpha * (nu + q_t**2) / (nu - 1)
            
            if nu > 2:
                scale = np.sqrt(nu / (nu - 2))
                es_t_padronizado = es_t / scale
                cond_es = cond_mean + cond_vol * es_t_padronizado
            else:
                cond_es = pd.Series(np.nan, index=returns_scaled.index)

            if self.save_egarch:
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

            # ------------------------------------------------------------------
            # Filtro de sanidade pós-EGARCH
            # O otimizador SLSQP pode convergir para soluções degeneradas quando
            # há saltos extremos de spread (ex: recuperação judicial de um emissor),
            # produzindo vol condicional na casa de milhares e VaR de milhões.
            # Nesses casos nulificamos as estimativas afetadas (→ NaN) para que
            # o ativo seja excluído das métricas de risco mas não do universo.
            # Limites calculados sobre o período IS (sem look-ahead bias).
            # ------------------------------------------------------------------
            try:
                ticker_str = group_df['Ticker'].iloc[0] if 'Ticker' in group_df.columns else '?'
                is_mask    = datas_valid < split_dt

                # P99 da volatilidade IS — teto de referência
                vol_is_p99 = np.nanpercentile((cond_vol / 100).loc[is_mask], 99) if is_mask.any() else np.inf
                # Limiar: 20x o P99 IS. Mitiga falhas de convergência do algoritmo SLSQP
                # sob saltos discretos na microestrutura de ativos ilíquidos.
                vol_teto = max(vol_is_p99 * 20.0, 5.0)  # piso de 5% a.a.

                # Máscara de observações inválidas
                # Filtro de sanidade: Restrição imposta a variâncias divergentes.
                # VaR negativo ocorre quando o carrego (drift) supera o risco em ativos de ultra baixa volatilidade.
                invalid_mask = (cond_vol / 100) > vol_teto

                n_invalid = invalid_mask.sum()
                if n_invalid > 0:
                    logger.warning(
                        f"[EGARCH Sanidade] {ticker_str}: {n_invalid} obs inválidas "
                        f"(Vol>{vol_teto:.2f}) → imputadas (ffill). "
                        f"Vol max raw: {(cond_vol/100).max():.2f}"
                    )
                    vol_series.loc[invalid_mask.index[invalid_mask]] = np.nan
                    var_series.loc[invalid_mask.index[invalid_mask]] = np.nan
                    es_series.loc[invalid_mask.index[invalid_mask]]  = np.nan

                    # Resgata a observação usando o último dia válido (ou próximo)
                    vol_series = vol_series.ffill().bfill()
                    var_series = var_series.ffill().bfill()
                    es_series  = es_series.ffill().bfill()

            except Exception as e_sanity:
                logger.debug(f"[EGARCH Sanidade] Falha no filtro: {e_sanity}")

        except Exception as e:
            logger.debug(f"Falha EGARCH: {e}")
            return vol_series, np.minimum(var_series, 1.0), np.minimum(es_series, 1.0)

        # Restrição do limite superior de perda esperada (100% do principal) para garantir consistência
        # teórica e estabilidade geométrica nas distâncias do espaço latente dos clusters.
        var_series = np.minimum(var_series, 1.0)
        es_series  = np.minimum(es_series, 1.0)

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

    def build_volatility_features(self, df: pd.DataFrame, split_date: str) -> pd.DataFrame:
        """Estima EGARCH para cada Ticker e preenche Volatilidade_EGARCH, VaR_99 e Expected_Shortfall_99."""
        if self._volatility_built:
            logger.info("build_volatility_features() já foi executado — pulando (evita duplo EGARCH).")
            return df
            
        df = df.copy()
        df['Volatilidade_EGARCH'] = np.nan
        df['VaR_99'] = np.nan
        df['Expected_Shortfall_99'] = np.nan

        def run_egarch(group):
            vol, var, es = self._egarch_var(group, split_date)
            return pd.DataFrame({'Volatilidade_EGARCH': vol, 'VaR_99': var, 'Expected_Shortfall_99': es})
        
        tqdm.pandas(desc="Calculando EGARCH por Ticker")
        egarch_res = df.groupby('Ticker').progress_apply(run_egarch)
        
        if isinstance(egarch_res.index, pd.MultiIndex):
            egarch_res = egarch_res.reset_index(level=0, drop=True)
            
        df.drop(columns=['Volatilidade_EGARCH', 'VaR_99', 'Expected_Shortfall_99'], inplace=True)
        df = df.join(egarch_res)
        self._volatility_built = True
        return df
