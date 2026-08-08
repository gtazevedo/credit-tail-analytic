import os
import logging
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
from typing import Dict
from credit_tail_analytics.utils import dados_dir, graficos_dir
import warnings

warnings.filterwarnings('ignore')
logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')
logger = logging.getLogger('BacktestFinanceiro')


# ---------------------------------------------------------------------------
# CDI histórico real
# ---------------------------------------------------------------------------

def _load_cdi_diario() -> Dict[pd.Timestamp, float]:
    """
    Carrega a série histórica de CDI diário (taxa ao dia) a partir do macro_data.csv.

    O campo CDI_Anual está em % ao ano base 252. A conversão para taxa diária é:
        cdi_diario = (1 + CDI_Anual / 100) ** (1 / 252) - 1

    Retorna
    -------
    dict : {pd.Timestamp → cdi_diario_float}
        Se o arquivo não existir, retorna {} e o fallback de 10.5% a.a. é usado.
    """
    FALLBACK_CDI_AA = 0.105  # 10.5% ao ano — fallback conservador
    try:
        macro_path = dados_dir() / 'macro_data.csv'
        if not macro_path.exists():
            logger.warning(
                f"macro_data.csv não encontrado em {macro_path}. "
                f"Usando CDI fixo de {FALLBACK_CDI_AA*100:.1f}% a.a."
            )
            return {}

        df_macro = pd.read_csv(macro_path, usecols=['Data', 'CDI_Anual'])
        df_macro['Data'] = pd.to_datetime(df_macro['Data'])
        df_macro = df_macro.dropna(subset=['CDI_Anual'])
        df_macro['CDI_Diario'] = (1 + df_macro['CDI_Anual'] / 100) ** (1 / 252) - 1

        cdi_map = df_macro.set_index('Data')['CDI_Diario'].to_dict()
        logger.info(
            f"CDI histórico carregado: {len(cdi_map)} dias | "
            f"Mín: {df_macro['CDI_Anual'].min():.2f}% a.a. | "
            f"Máx: {df_macro['CDI_Anual'].max():.2f}% a.a."
        )
        return cdi_map

    except Exception as e:
        logger.warning(f"Falha ao carregar CDI histórico: {e}. Usando CDI fixo.")
        return {}


# ---------------------------------------------------------------------------
# Eventos financeiros (juros / amortizações)
# ---------------------------------------------------------------------------

def download_eventos_financeiros() -> pd.DataFrame:
    """
    Tenta carregar o cache de eventos. Se não existir, faz o download via pacote
    debentures_dot_com para obter todos os eventos (juros, amortização, etc).
    """
    cache_path = dados_dir() / 'pu_eventos.csv'
    if cache_path.exists():
        logger.info(f"Carregando eventos do cache: {cache_path}")
        return pd.read_csv(cache_path)

    logger.info("Baixando histórico completo de eventos financeiros (pode demorar)...")
    try:
        from debentures_dot_com.eventos_fin import EventosFinanceiros
        ev = EventosFinanceiros()
        df_ev = ev.pu_eventos(timeout=300)
        if not df_ev.empty:
            col_pu = 'PU   de Evento' if 'PU   de Evento' in df_ev.columns else 'PU de Evento'
            if col_pu in df_ev.columns:
                df_ev['Valor_Evento'] = pd.to_numeric(
                    df_ev[col_pu].astype(str).str.replace(',', '.').str.strip(),
                    errors='coerce'
                ).fillna(0.0)
            else:
                df_ev['Valor_Evento'] = 0.0
            df_ev.to_csv(cache_path, index=False)
            logger.info(f"Eventos salvos no cache em {cache_path}")
        return df_ev
    except Exception as e:
        logger.error(f"Erro ao baixar eventos: {e}")
        return pd.DataFrame()


# ---------------------------------------------------------------------------
# Classe principal
# ---------------------------------------------------------------------------

class BacktestFinanceiro:
    """
    Executa a validação financeira com simulação real de portfólio.

    O CDI histórico real (extraído de macro_data.csv) é utilizado para remunerar
    o caixa das estratégias táticas e do benchmark Buy-and-Hold, eliminando a
    distorção causada pelo uso de uma taxa fixa ao longo do período 2018–2026
    (CDI variou de ≈ 2% a.a. em 2021 até ≈ 13,75% a.a. em 2023).
    """

    # Fallback: (1 + 10.5% a.a.)^(1/252) − 1
    _CDI_FALLBACK_DAILY: float = (1 + 0.105) ** (1 / 252) - 1

    def __init__(self, df_resultados: pd.DataFrame):
        self.df = df_resultados.copy()
        self.df['Data'] = pd.to_datetime(self.df['Data'])
        self.df.sort_values(by=['Ticker', 'Data'], inplace=True)

        # Carrega CDI histórico real
        self._cdi_map: Dict[pd.Timestamp, float] = _load_cdi_diario()

        # Incorpora eventos financeiros apenas se o pipeline não os tiver fornecido
        if 'Valor_Evento' not in self.df.columns:
            df_ev = download_eventos_financeiros()
            if not df_ev.empty and 'Data' in df_ev.columns and 'Ativo' in df_ev.columns:
                df_ev['Data'] = pd.to_datetime(df_ev['Data'], format='%d/%m/%Y', errors='coerce')
                df_ev_grouped = df_ev.groupby(['Ativo', 'Data'])['Valor_Evento'].sum().reset_index()
                df_ev_grouped.rename(columns={'Ativo': 'Ticker'}, inplace=True)
                self.df = pd.merge(self.df, df_ev_grouped, on=['Ticker', 'Data'], how='left')
            else:
                self.df['Valor_Evento'] = 0.0
                
        self.df['Valor_Evento'] = self.df['Valor_Evento'].fillna(0.0)

        # Retorno total diário (Mark-to-Market + Evento)
        if 'PU' not in self.df.columns:
            logger.warning("Coluna PU não encontrada. Retornos não poderão ser calculados.")
            self.df['PU'] = 1000.0
            self.df['Retorno_Total'] = 0.0
        else:
            self.df['PU_Prev'] = self.df.groupby('Ticker')['PU'].shift(1)
            self.df['Retorno_Total'] = np.where(
                self.df['PU_Prev'].isna(),
                0.0,
                (self.df['PU'] + self.df['Valor_Evento']) / self.df['PU_Prev'] - 1.0
            )
            self.df['Retorno_Total'] = self.df['Retorno_Total'].fillna(0.0)

        # Cluster_Ensemble a partir do Credit_Tail_Risk_Score
        if 'Credit_Tail_Risk_Score' in self.df.columns:
            def _categorize(score):
                if pd.isna(score):
                    return 'Inconclusivo'
                if score >= 60:
                    return 'Vermelho'
                elif score >= 35:
                    return 'Amarelo'
                return 'Verde'
            self.df['Cluster_Ensemble'] = self.df['Credit_Tail_Risk_Score'].apply(_categorize)

    def _get_cdi_diario(self, date: pd.Timestamp) -> float:
        """Retorna a taxa CDI diária para uma data, com fallback conservador."""
        return self._cdi_map.get(date, self._CDI_FALLBACK_DAILY)

    # ------------------------------------------------------------------
    # Matrizes de Transição Empíricas
    # ------------------------------------------------------------------

    def plot_matriz_transicao(self):
        logger.info("Gerando Matrizes de Transição Empíricas...")
        for modelo in ['KMeans', 'HMM', 'Ensemble']:
            col = f'Cluster_{modelo}'
            if col not in self.df.columns:
                continue

            self.df[f'{col}_Prev'] = self.df.groupby('Ticker')[col].shift(1)
            mask_valid = (
                self.df[col].isin(['Verde', 'Amarelo', 'Vermelho']) &
                self.df[f'{col}_Prev'].isin(['Verde', 'Amarelo', 'Vermelho'])
            )
            df_valid = self.df[mask_valid]
            if df_valid.empty:
                continue

            trans_counts = pd.crosstab(df_valid[f'{col}_Prev'], df_valid[col], normalize='index')
            ordem = ['Verde', 'Amarelo', 'Vermelho']
            trans_counts = trans_counts.reindex(index=ordem, columns=ordem, fill_value=0.0)

            fig, ax = plt.subplots(figsize=(6, 5))
            sns.heatmap(trans_counts, annot=True, fmt=".1%", cmap="Blues",
                        cbar=False, vmin=0, vmax=1, ax=ax)
            ax.set_title(f'Matriz de Transição Empírica — {modelo}')
            ax.set_ylabel('Estado Atual (t)')
            ax.set_xlabel('Estado Futuro (t+1)')
            plt.tight_layout()

            out_path = graficos_dir() / f'matriz_transicao_{modelo.lower()}.png'
            plt.savefig(str(out_path), dpi=150)
            plt.close()

    # ------------------------------------------------------------------
    # Simulação de Portfólio
    # ------------------------------------------------------------------

    def simulate_portfolio(
        self,
        initial_capital: float = 1_000_000.0,
        cure_days: int = 180,
        transaction_cost: float = 0.005,
        meses_payback: int = 3,
    ) -> pd.DataFrame:
        """
        Simula portfólio tático para cada modelo (KMeans, HMM, Ensemble) e o
        benchmark Buy-and-Hold. O CDI usado no caixa é o CDI histórico real
        extraído de macro_data.csv (com fallback de 10.5% ao ano).

        Parâmetros
        ----------
        initial_capital : float — capital inicial (padrão R$ 1.000.000)
        cure_days       : int   — dias de quarentena antes de recomprar ativo vermelho

        Retorna
        -------
        pd.DataFrame — curvas de patrimônio acumulado por data (índice) e modelo (colunas)
        """
        logger.info(
            f"Rodando simulação de Portfólio "
            f"(R$ {initial_capital:,.0f}, Cura {cure_days} dias, CDI Real, Eventos Inclusos)..."
        )

        tickers      = self.df['Ticker'].unique()
        datas_unicas = sorted(self.df['Data'].unique())
        df_pnl       = pd.DataFrame(index=datas_unicas)

        # ---------------------------------------------------------------
        # Benchmark: Buy & Hold (CDI real no caixa)
        # ---------------------------------------------------------------
        capital_bnh  = {t: 0.0 for t in tickers}
        cash_bnh     = initial_capital
        history_bnh  = []
        is_first_day = True

        for current_date, group in self.df.groupby('Data'):
            cdi_dia  = self._get_cdi_diario(pd.Timestamp(current_date))
            retornos = dict(zip(group['Ticker'], group['Retorno_Total']))

            for t in capital_bnh:
                if t in retornos:
                    capital_bnh[t] *= (1.0 + retornos[t])
            cash_bnh *= (1.0 + cdi_dia)

            if is_first_day:
                ativos_dia = group['Ticker'].tolist()
                if ativos_dia:
                    aporte = cash_bnh / len(ativos_dia)
                    for t in ativos_dia:
                        capital_bnh[t] += aporte * (1.0 - transaction_cost)
                    cash_bnh = 0.0
                is_first_day = False

            history_bnh.append(sum(capital_bnh.values()) + cash_bnh)

        df_pnl['BnH_Cum'] = history_bnh

        # ---------------------------------------------------------------
        # Alocadores táticos — CDI real no caixa
        # ---------------------------------------------------------------
        model_configs = [
            ('KMeans', ['Vermelho']),
            ('HMM', ['Vermelho']),
            ('Ensemble', ['Vermelho']),
            ('KMeans_Amarelo', ['Vermelho', 'Amarelo']),
            ('HMM_Amarelo', ['Vermelho', 'Amarelo']),
            ('Ensemble_Amarelo', ['Vermelho', 'Amarelo'])
        ]
        
        for config_name, stop_regimes in model_configs:
            col_base = config_name.replace('_Amarelo', '')
            col = f'Cluster_{col_base}'
            if col not in self.df.columns:
                continue

            capital      = {t: 0.0 for t in tickers}
            cash         = 0.0
            dias_cura    = {t: None for t in tickers}
            dias_verde   = {t: 0 for t in tickers}
            history      = []
            is_first_day = True

            for current_date, group in self.df.groupby('Data'):
                cdi_dia  = self._get_cdi_diario(pd.Timestamp(current_date))
                retornos = dict(zip(group['Ticker'], group['Retorno_Total']))
                regimes  = dict(zip(group['Ticker'], group[col]))
                taxas    = dict(zip(group['Ticker'], group['Taxa_Ativo'])) if 'Taxa_Ativo' in group.columns else {}

                # 1. Mark-to-Market dos ativos alocados
                for t in capital:
                    if t in retornos:
                        capital[t] *= (1.0 + retornos[t])

                # 2. Caixa rende CDI real
                cash *= (1.0 + cdi_dia)

                if is_first_day:
                    ativos_dia = group['Ticker'].tolist()
                    if ativos_dia:
                        aporte = initial_capital / len(ativos_dia)
                        for t in ativos_dia:
                            capital[t] += aporte * (1.0 - transaction_cost)
                        cash = 0.0
                    is_first_day = False
                else:
                    # 3. Stop (Venda) — regime Vermelho
                    cash_liberado = 0.0
                    for t, rgm in regimes.items():
                        if rgm in stop_regimes:
                            dias_cura[t] = 0
                            cash_liberado += capital[t] * (1.0 - transaction_cost)
                            capital[t] = 0.0
                    
                    # Atualiza dias de cura para todos os ativos
                    for t in dias_cura:
                        if dias_cura[t] is not None:
                            # Se não está em stop_regime hoje (ou não tem regime hoje), incrementa
                            if t not in regimes or regimes[t] not in stop_regimes:
                                dias_cura[t] += 1

                    # Atualiza inércia de dias verdes
                    for t, rgm in regimes.items():
                        if rgm == 'Verde':
                            dias_verde[t] += 1
                        else:
                            dias_verde[t] = 0
                                
                    cash += cash_liberado

                    # 4. Reaplicação (Compra) — regime Verde após quarentena
                    limite_spread = (transaction_cost * (12.0 / meses_payback)) * 100.0
                    elegiveis = []
                    for t, rgm in regimes.items():
                        if rgm == 'Verde' and (dias_cura[t] is None or dias_cura[t] >= cure_days):
                            if dias_verde[t] >= 15:
                                taxa = taxas.get(t, 0.0)
                                if pd.notna(taxa) and taxa >= limite_spread:
                                    elegiveis.append(t)
                    if cash > 0.01 and elegiveis:
                        aporte = cash / len(elegiveis)
                        for t in elegiveis:
                            capital[t] += aporte * (1.0 - transaction_cost)
                            dias_cura[t] = None  # zera quarentena ao reentrar
                        cash = 0.0

                history.append(sum(capital.values()) + cash)

            df_pnl[f'{config_name}_Cum'] = history

        # ---------------------------------------------------------------
        # Gráfico das curvas de PnL
        # ---------------------------------------------------------------
        fig, ax = plt.subplots(figsize=(12, 6))
        estilos = {
            'BnH_Cum':              ('black', '--', 'Benchmark (Buy & Hold)', 1.5),
            'HMM_Amarelo_Cum':      ('#27ae60', '-', 'HMM (Vende Amarelo)', 1.5),
            'HMM_Cum':              ('#2ecc71', ':', 'HMM (Vende Vermelho)', 1.5),
            'KMeans_Amarelo_Cum':   ('#c0392b', '-', 'K-Means (Vende Amarelo)', 1.5),
            'KMeans_Cum':           ('#e74c3c', ':', 'K-Means (Vende Vermelho)', 1.5),
            'Ensemble_Amarelo_Cum': ('#2980b9', '-', 'Ensemble (Vende Amarelo)', 1.5),
            'Ensemble_Cum':         ('#3498db', ':', 'Ensemble (Vende Vermelho)', 1.5),
        }
        for col, (cor, ls, label, lw) in estilos.items():
            if col in df_pnl.columns:
                ax.plot(df_pnl.index, df_pnl[col], label=label, color=cor,
                        linestyle=ls, linewidth=lw, alpha=0.9)

        ax.set_title('Simulação de Portfólio — CDI Real, Reinvestimento de Eventos e Stop Loss')
        ax.set_ylabel('Patrimônio (BRL)')
        ax.grid(True, alpha=0.3)
        ax.legend()
        plt.tight_layout()

        out_path = graficos_dir() / 'backtest_pnl_portfolio.png'
        plt.savefig(str(out_path), dpi=200)
        plt.close()
        logger.info(f"Curvas de PnL salvas em {out_path}")

        # ---------------------------------------------------------------
        # Métricas financeiras
        # ---------------------------------------------------------------
        df_metrics = self.compute_performance_metrics(df_pnl)
        logger.info(f"\n{df_metrics.to_string()}")

        return df_pnl

    # ------------------------------------------------------------------
    # Métricas de Performance
    # ------------------------------------------------------------------

    def compute_performance_metrics(self, df_pnl: pd.DataFrame) -> pd.DataFrame:
        """
        Calcula métricas financeiras padrão para cada estratégia simulada.

        Métricas calculadas
        -------------------
        - Retorno_Total_%       : retorno acumulado total do período
        - CAGR_%                : Compound Annual Growth Rate (retorno anualizado)
        - Volatilidade_Anual_%  : std dos retornos diários × √252 × 100
        - Sharpe_Ratio          : (retorno médio diário − CDI médio diário) / vol_diária × √252
        - Max_Drawdown_%        : maior queda pico-a-vale em % do pico
        - Calmar_Ratio          : CAGR% / |Max_Drawdown%|
        - CDI_Medio_Anual_%     : CDI médio do período (como referência de risk-free)

        Parâmetros
        ----------
        df_pnl : pd.DataFrame — curvas de patrimônio (índice = datas, colunas = estratégias)

        Retorna
        -------
        pd.DataFrame com linhas = estratégias, colunas = métricas
        """
        registros = []

        # CDI médio diário do período como risk-free para o Sharpe
        datas_pnl  = pd.to_datetime(df_pnl.index)
        cdi_diarios = [self._get_cdi_diario(d) for d in datas_pnl]
        rf_medio    = float(np.mean(cdi_diarios)) if cdi_diarios else self._CDI_FALLBACK_DAILY

        for col in df_pnl.columns:
            serie = df_pnl[col].dropna()
            if len(serie) < 2:
                continue

            retornos_diarios = serie.pct_change().dropna()
            n_dias  = len(serie)
            n_anos  = n_dias / 252.0

            retorno_total = (serie.iloc[-1] / serie.iloc[0] - 1) * 100
            cagr          = ((serie.iloc[-1] / serie.iloc[0]) ** (1 / n_anos) - 1) * 100
            vol_anual     = retornos_diarios.std() * np.sqrt(252) * 100

            # Sharpe: excesso de retorno diário médio / vol diária × √252
            excesso_medio = retornos_diarios.mean() - rf_medio
            vol_diaria    = retornos_diarios.std()
            sharpe        = (excesso_medio / vol_diaria * np.sqrt(252)) if vol_diaria > 0 else np.nan

            # Max Drawdown pico-a-vale
            acum_max  = serie.cummax()
            drawdowns = (serie - acum_max) / acum_max * 100
            max_dd    = drawdowns.min()

            calmar = (cagr / abs(max_dd)) if max_dd < 0 else np.nan

            nome = col.replace('_Cum', '')
            registros.append({
                'Estrategia':           nome,
                'Retorno_Total_%':      round(retorno_total, 2),
                'CAGR_%':               round(cagr, 2),
                'Volatilidade_Anual_%': round(vol_anual, 2),
                'Sharpe_Ratio':         round(sharpe, 3) if not np.isnan(sharpe) else np.nan,
                'Max_Drawdown_%':       round(max_dd, 2),
                'Calmar_Ratio':         round(calmar, 3) if not np.isnan(calmar) else np.nan,
                'CDI_Medio_Anual_%':    round(rf_medio * 252 * 100, 2),
            })

        df_metrics = pd.DataFrame(registros).set_index('Estrategia')

        out_path = dados_dir() / 'metricas_backtest.csv'
        df_metrics.to_csv(out_path)
        logger.info(f"Métricas de performance salvas em {out_path}")

        return df_metrics

    # ------------------------------------------------------------------
    # Early Warning Score
    # ------------------------------------------------------------------

    def generate_early_warning_score(self):
        primeiro_vermelho = []
        for ticker in self.df['Ticker'].unique():
            df_t = self.df[self.df['Ticker'] == ticker]

            d_km  = df_t[df_t['Cluster_KMeans']    == 'Vermelho']['Data'].min() if 'Cluster_KMeans'    in df_t.columns else pd.NaT
            d_hmm = df_t[df_t['Cluster_HMM']       == 'Vermelho']['Data'].min() if 'Cluster_HMM'       in df_t.columns else pd.NaT
            d_ens = df_t[df_t['Cluster_Ensemble']   == 'Vermelho']['Data'].min() if 'Cluster_Ensemble'  in df_t.columns else pd.NaT

            vol_pre    = df_t['Volatilidade_EGARCH'].max() if 'Volatilidade_EGARCH' in df_t.columns else np.nan
            spread_max = df_t['Taxa_Ativo'].max()          if 'Taxa_Ativo'          in df_t.columns else np.nan

            primeiro_vermelho.append({
                'Ticker':             ticker,
                '1o_Alerta_KMeans':   d_km,
                '1o_Alerta_HMM':      d_hmm,
                '1o_Alerta_Ensemble': d_ens,
                'Max_Volatilidade':   vol_pre,
                'Max_Spread':         spread_max,
            })

        df_ew = pd.DataFrame(primeiro_vermelho)
        df_ew = df_ew.dropna(subset=['1o_Alerta_KMeans', '1o_Alerta_HMM'], how='all')
        out_path = dados_dir() / 'tabela_early_warning.csv'
        df_ew.to_csv(str(out_path), index=False)


if __name__ == '__main__':
    res_path = dados_dir() / 'resultado_frequentist_engine.csv'
    if res_path.exists():
        df_res = pd.read_csv(res_path)
        bt = BacktestFinanceiro(df_res)
        bt.plot_matriz_transicao()
        bt.simulate_portfolio()
        bt.generate_early_warning_score()
    else:
        logger.error(f"Arquivo não encontrado: {res_path}. Rode o engine primeiro.")
