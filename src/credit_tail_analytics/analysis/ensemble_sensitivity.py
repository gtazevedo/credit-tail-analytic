import logging
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.colors as mcolors
import seaborn as sns
from typing import Optional
import sys
import os

logger = logging.getLogger('EnsembleSensitivity')
logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')


class EnsembleSensitivity:
    '''
    Analise de sensibilidade dos pesos ponderados do modelo Ensemble.

    Para cada par de pesos (w_hmm, w_kmeans) com w_hmm + w_kmeans = 1,
    reconstroi o Credit_Tail_Risk_Score e recalcula o portfolio completo,
    reportando as metricas financeiras de cada configuracao.

    Parametros
    ----------
    df_resultados : pd.DataFrame
        DataFrame com colunas Prob_Crise_HMM, Prob_Crise_KMeans e demais
        colunas necessarias para o BacktestFinanceiro (PU, Retorno_Total, etc.)
    step : float
        Passo da grade de pesos. Padrao 0.10 (10 em 10%).
    ema_window : int
        Janela da EMA suavizadora aplicada ao score sintetico. Padrao 3.
    score_threshold_vermelho : float
        Limiar de score para Vermelho (0-100). Padrao 60.
    score_threshold_amarelo : float
        Limiar de score para Amarelo (0-100). Padrao 35.
    transaction_cost : float
        Custo de transacao por operacao. Padrao 0.005 (0,5%).
    cure_days : int
        Dias de quarentena antes de recomprar um ativo vendido. Padrao 180.
    '''

    def __init__(
        self,
        df_resultados: pd.DataFrame,
        step: float = 0.10,
        ema_window: int = 3,
        score_threshold_vermelho: float = 60.0,
        score_threshold_amarelo: float = 35.0,
        transaction_cost: float = 0.005,
        cure_days: int = 180,
    ):
        self.df_base = df_resultados.copy()
        self.step = step
        self.ema_window = ema_window
        self.thr_verm = score_threshold_vermelho
        self.thr_amar = score_threshold_amarelo
        self.transaction_cost = transaction_cost
        self.cure_days = cure_days

        required = {'Prob_Crise_HMM', 'Prob_Crise_KMeans', 'Ticker', 'Data'}
        missing = required - set(self.df_base.columns)
        if missing:
            raise ValueError(
                f'O DataFrame nao contem as colunas obrigatorias: {missing}. '
                'Verifique se o pipeline de modelos foi executado antes desta analise.'
            )

    def _build_score(self, df: pd.DataFrame, w_hmm: float) -> pd.DataFrame:
        '''Reconstroi o Credit_Tail_Risk_Score para um dado peso w_hmm.'''
        w_km = 1.0 - w_hmm
        alpha = 2.0 / (self.ema_window + 1.0)

        df = df.copy()
        df['_Score_Raw'] = (
            w_hmm * df['Prob_Crise_HMM'] + w_km * df['Prob_Crise_KMeans']
        ) * 100.0

        df.sort_values(['Ticker', 'Data'], inplace=True)
        df['Credit_Tail_Risk_Score'] = (
            df.groupby('Ticker')['_Score_Raw']
            .transform(lambda s: s.ewm(alpha=alpha, adjust=False).mean())
        )

        def _categorize(score):
            if pd.isna(score):
                return 'Inconclusivo'
            if score >= self.thr_verm:
                return 'Vermelho'
            if score >= self.thr_amar:
                return 'Amarelo'
            return 'Verde'

        df['Cluster_Ensemble'] = df['Credit_Tail_Risk_Score'].apply(_categorize)
        return df

    @staticmethod
    def _compute_metrics(equity_curve: pd.Series) -> dict:
        '''Calcula CAGR, Max Drawdown e Calmar Ratio.'''
        if len(equity_curve) < 2:
            return {'CAGR_%': float('nan'), 'Max_Drawdown_%': float('nan'), 'Calmar_Ratio': float('nan')}

        n_anos = len(equity_curve) / 252.0
        ret_total = equity_curve.iloc[-1] / equity_curve.iloc[0]
        cagr = (ret_total ** (1.0 / n_anos) - 1.0) * 100.0

        acum_max = equity_curve.cummax()
        drawdowns = (equity_curve - acum_max) / acum_max * 100.0
        max_dd = drawdowns.min()
        calmar = (cagr / abs(max_dd)) if max_dd < 0 else float('nan')

        return {'CAGR_%': round(cagr, 3), 'Max_Drawdown_%': round(max_dd, 3), 'Calmar_Ratio': round(calmar, 4)}

    def _simulate_portfolio_simple(
        self,
        df: pd.DataFrame,
        stop_regimes: list,
        initial_capital: float = 1_000_000.0,
        cdi_fallback_daily: float = (1 + 0.105) ** (1 / 252) - 1,
    ) -> pd.Series:
        '''Simulacao simplificada de portfolio tatico para uso na grade de sensibilidade.'''
        df = df.copy()
        df['Data'] = pd.to_datetime(df['Data'])
        df.sort_values(['Ticker', 'Data'], inplace=True)

        if 'PU' in df.columns:
            df['_PU_prev'] = df.groupby('Ticker')['PU'].shift(1)
            df['_Ret'] = (df['PU'] / df['_PU_prev'] - 1).fillna(0.0)
        elif 'Retorno_Total' in df.columns:
            df['_Ret'] = df['Retorno_Total'].fillna(0.0)
        else:
            df['_Ret'] = 0.0

        tickers = df['Ticker'].unique()
        capital = {t: 0.0 for t in tickers}
        cash = float(initial_capital)
        dias_cura = {t: None for t in tickers}
        dias_verde = {t: 0 for t in tickers}
        history = []
        is_first = True

        for current_date, group in df.groupby('Data'):
            retornos = dict(zip(group['Ticker'], group['_Ret']))
            regimes = dict(zip(group['Ticker'], group['Cluster_Ensemble']))

            for t, ret in retornos.items():
                if capital.get(t, 0.0) > 0:
                    capital[t] *= (1.0 + ret)
            cash *= (1.0 + cdi_fallback_daily)
            ativos_dia = group['Ticker'].tolist()

            if is_first:
                if ativos_dia:
                    aporte = cash / len(ativos_dia)
                    for t in ativos_dia:
                        capital[t] = capital.get(t, 0.0) + aporte * (1.0 - self.transaction_cost)
                    cash = 0.0
                is_first = False
            else:
                cash_lib = 0.0
                for t, rgm in regimes.items():
                    if rgm in stop_regimes and capital.get(t, 0.0) > 0:
                        dias_cura[t] = 0
                        cash_lib += capital[t] * (1.0 - self.transaction_cost)
                        capital[t] = 0.0
                cash += cash_lib

                for t in dias_cura:
                    if dias_cura[t] is not None:
                        if regimes.get(t, 'Verde') not in stop_regimes:
                            dias_cura[t] += 1
                for t, rgm in regimes.items():
                    dias_verde[t] = (dias_verde.get(t, 0) + 1) if rgm == 'Verde' else 0

                elegiveis = [
                    t for t, rgm in regimes.items()
                    if t in ativos_dia
                    and rgm == 'Verde'
                    and (dias_cura.get(t) is None or dias_cura[t] >= self.cure_days)
                    and dias_verde.get(t, 0) >= 15
                ]
                if cash > 0.01 and elegiveis:
                    aporte = cash / len(elegiveis)
                    for t in elegiveis:
                        capital[t] = capital.get(t, 0.0) + aporte * (1.0 - self.transaction_cost)
                        dias_cura[t] = None
                    cash = 0.0

            history.append(sum(capital.values()) + cash)

        return pd.Series(history, name='equity')

    def run(
        self,
        initial_capital: float = 1_000_000.0,
        stop_mode: str = 'Vermelho',
    ) -> pd.DataFrame:
        '''
        Executa a grade completa de pesos e retorna DataFrame com metricas.

        Parametros
        ----------
        initial_capital : float
        stop_mode       : 'Vermelho' ou 'Amarelo'

        Retorna
        -------
        pd.DataFrame com colunas: w_HMM, w_KMeans, CAGR_%, Max_Drawdown_%, Calmar_Ratio
        '''
        stop_regimes = ['Vermelho'] if stop_mode == 'Vermelho' else ['Vermelho', 'Amarelo']
        pesos = [round(p, 2) for p in np.arange(0.0, 1.0 + self.step / 2, self.step) if 0.0 <= round(p, 2) <= 1.0]

        resultados = []
        logger.info(f'Iniciando grade de sensibilidade: {len(pesos)} configuracoes | modo={stop_mode}')

        for w_hmm in pesos:
            logger.info(f'  Testando w_HMM={w_hmm:.2f} / w_KMeans={1-w_hmm:.2f} ...')
            df_w = self._build_score(self.df_base, w_hmm=w_hmm)
            equity = self._simulate_portfolio_simple(df_w, stop_regimes=stop_regimes, initial_capital=initial_capital)
            metrics = self._compute_metrics(equity)
            resultados.append({'w_HMM': w_hmm, 'w_KMeans': round(1 - w_hmm, 2), **metrics})

        df_grade = pd.DataFrame(resultados)
        self._plot_sensitivity(df_grade, stop_mode=stop_mode)
        return df_grade

    def _plot_sensitivity(self, df_grade: pd.DataFrame, stop_mode: str) -> None:
        '''Gera grafico de barras com resultados da grade de sensibilidade.'''
        fig, axes = plt.subplots(1, 3, figsize=(15, 5))
        fig.suptitle(
            f'Analise de Sensibilidade dos Pesos do Ensemble - Modo: Vende {stop_mode}',
            fontsize=13, fontweight='bold'
        )

        metricas = [
            ('CAGR_%', 'CAGR (%)', 'steelblue'),
            ('Max_Drawdown_%', 'Max Drawdown (%)', 'firebrick'),
            ('Calmar_Ratio', 'Calmar Ratio', 'darkgreen'),
        ]

        for ax, (col, label, cor) in zip(axes, metricas):
            x_labels = [str(w) for w in df_grade['w_HMM']]
            vals = df_grade[col].values
            bars = ax.bar(x_labels, vals, color=cor, alpha=0.8, edgecolor='white')
            ax.set_xlabel('Peso HMM (w_HMM)')
            ax.set_ylabel(label)
            ax.set_title(label)
            ax.tick_params(axis='x', rotation=45)
            ax.grid(axis='y', alpha=0.3)

            if col == 'Calmar_Ratio':
                pass  # Removidas as anotacoes para deixar o grafico puro

        plt.tight_layout()
        # Salva no diretorio de graficos do projeto, se existir
        out_dir = os.path.join(os.path.dirname(__file__), '..', '..', '..', '..', 'graficos')
        os.makedirs(out_dir, exist_ok=True)
        out_path = os.path.join(out_dir, f'sensitivity_ensemble_{stop_mode.lower()}.png')
        plt.savefig(out_path, dpi=180, bbox_inches='tight')
        plt.close()
        logger.info(f'Grafico de sensibilidade salvo em {out_path}')

        # Log da tabela
        idx_best = df_grade['Calmar_Ratio'].idxmax()
        logger.info(f'\nResultado Otimo (Calmar): w_HMM={df_grade.loc[idx_best, "w_HMM"]}, {df_grade.loc[idx_best].to_dict()}')
        logger.info(f'\nTabela completa:\n{df_grade.to_string(index=False)}')


if __name__ == '__main__':
    print('EnsembleSensitivity: modulo carregado com sucesso.')
    print('Para executar, importe e instancie a classe com um df_resultados valido.')
