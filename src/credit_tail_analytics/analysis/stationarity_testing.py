"""
stationarity_testing.py
-----------------------
Classe para testes de estacionariedade (ADF) nos spreads das debentures,
como pre-requisito para a aplicacao dos modelos GARCH.

H0 (ADF): A serie possui raiz unitaria (nao-estacionaria)
H1 (ADF): A serie e estacionaria

Uso:
    from credit_tail_analytics.analysis.stationarity_testing import StationarityTester

    tester = StationarityTester(df_spreads, coluna_spread='Delta_Spread', coluna_ticker='Ticker')
    df_resultado = tester.run()
    tester.plot_summary()
"""

import logging
import warnings
import os
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
from typing import Optional

warnings.filterwarnings('ignore')
logger = logging.getLogger('StationarityTester')
logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')


class StationarityTester:
    """
    Executa o Teste de Dickey-Fuller Aumentado (ADF) em series temporais de spread
    para verificar a pre-condicao de estacionariedade exigida pelos modelos GARCH.

    H0 (nula)      : A serie possui raiz unitaria (e nao-estacionaria)
    H1 (alternativa): A serie e estacionaria (rejeita H0)

    A rejeicao de H0 (p-valor < alpha) valida a aplicacao do GARCH/EGARCH.

    Parametros
    ----------
    df : pd.DataFrame
        DataFrame com colunas de data, ticker e spread.
    coluna_spread : str
        Nome da coluna com a serie de spread (ou delta spread) a ser testada.
    coluna_ticker : str
        Nome da coluna identificadora do ativo.
    coluna_data   : str
        Nome da coluna de data.
    coluna_indexador : str, opcional
        Se fornecida, agrupa os resultados por indexador (CDI, IPCA, etc.).
    alpha : float
        Nivel de significancia para rejeicao de H0. Padrao 0.05 (5%).
    max_lags : int, opcional
        Numero maximo de defasagens no ADF. Se None, usa criterio automatico (AIC).
    min_obs : int
        Numero minimo de observacoes para aplicar o teste. Padrao 30.
    """

    def __init__(
        self,
        df: pd.DataFrame,
        coluna_spread: str = 'Delta_Spread',
        coluna_ticker: str = 'Ticker',
        coluna_data: str = 'Data',
        coluna_indexador: Optional[str] = 'Indexador',
        alpha: float = 0.05,
        max_lags: Optional[int] = None,
        min_obs: int = 30,
    ):
        self.df = df.copy()
        self.coluna_spread = coluna_spread
        self.coluna_ticker = coluna_ticker
        self.coluna_data = coluna_data
        self.coluna_indexador = coluna_indexador
        self.alpha = alpha
        self.max_lags = max_lags
        self.min_obs = min_obs
        self.df_resultados: Optional[pd.DataFrame] = None

        # Valida colunas obrigatorias
        for c in [coluna_spread, coluna_ticker, coluna_data]:
            if c not in self.df.columns:
                raise ValueError(
                    f"Coluna obrigatoria '{c}' nao encontrada no DataFrame. "
                    f"Colunas disponíveis: {list(self.df.columns)}"
                )

        self.df[self.coluna_data] = pd.to_datetime(self.df[self.coluna_data])
        logger.info(
            f'StationarityTester inicializado: {self.df[self.coluna_ticker].nunique()} ativos | '
            f'coluna={self.coluna_spread} | alpha={self.alpha}'
        )

    # ------------------------------------------------------------------
    # ADF ativo a ativo
    # ------------------------------------------------------------------

    def _testar_ativo(self, ticker: str, serie: pd.Series) -> dict:
        """Aplica o ADF a uma serie temporal e retorna o resultado estruturado."""
        try:
            from statsmodels.tsa.stattools import adfuller
        except ImportError:
            raise ImportError(
                "O pacote statsmodels e necessario. Instale com: pip install statsmodels"
            )

        serie = serie.dropna()

        if len(serie) < self.min_obs:
            return {
                'Ticker': ticker,
                'N_Obs': len(serie),
                'ADF_Statistic': float('nan'),
                'p_valor': float('nan'),
                'Lags_Usados': float('nan'),
                'Critico_1%': float('nan'),
                'Critico_5%': float('nan'),
                'Critico_10%': float('nan'),
                'Estacionaria': float('nan'),
                'Status': 'Insuficiente (<30 obs)',
            }

        try:
            resultado = adfuller(
                serie.values,
                maxlag=self.max_lags,
                autolag='AIC' if self.max_lags is None else None,
                regression='c',  # constante sem tendencia (adequado para Delta Spread)
            )
            adf_stat = resultado[0]
            p_val = resultado[1]
            n_lags = resultado[2]
            criticos = resultado[4]

            estacionaria = p_val < self.alpha

            return {
                'Ticker': ticker,
                'N_Obs': len(serie),
                'ADF_Statistic': round(adf_stat, 4),
                'p_valor': round(p_val, 6),
                'Lags_Usados': n_lags,
                'Critico_1%': round(criticos.get('1%', float('nan')), 4),
                'Critico_5%': round(criticos.get('5%', float('nan')), 4),
                'Critico_10%': round(criticos.get('10%', float('nan')), 4),
                'Estacionaria': estacionaria,
                'Status': f'Rejeita H0 (p={p_val:.4f})' if estacionaria else f'Nao rejeita H0 (p={p_val:.4f})',
            }

        except Exception as e:
            return {
                'Ticker': ticker,
                'N_Obs': len(serie),
                'ADF_Statistic': float('nan'),
                'p_valor': float('nan'),
                'Lags_Usados': float('nan'),
                'Critico_1%': float('nan'),
                'Critico_5%': float('nan'),
                'Critico_10%': float('nan'),
                'Estacionaria': float('nan'),
                'Status': f'Erro: {str(e)[:60]}',
            }

    # ------------------------------------------------------------------
    # Execucao Principal
    # ------------------------------------------------------------------

    def run(self) -> pd.DataFrame:
        """
        Aplica o ADF a todos os ativos e retorna um DataFrame com os resultados.

        Retorna
        -------
        pd.DataFrame com uma linha por ativo, contendo a estatistica ADF,
        o p-valor, o numero de lags e o resultado da hipotese.
        """
        tickers = self.df[self.coluna_ticker].unique()
        resultados = []

        logger.info(f'Iniciando testes ADF para {len(tickers)} ativos...')
        for i, ticker in enumerate(tickers, 1):
            df_t = self.df[self.df[self.coluna_ticker] == ticker].sort_values(self.coluna_data)
            serie = df_t[self.coluna_spread]
            resultado = self._testar_ativo(ticker, serie)

            # Inclui indexador se disponivel
            if self.coluna_indexador and self.coluna_indexador in self.df.columns:
                idx_val = df_t[self.coluna_indexador].iloc[0] if not df_t.empty else 'N/A'
                resultado['Indexador'] = idx_val

            resultados.append(resultado)
            if i % 100 == 0:
                logger.info(f'  Progresso: {i}/{len(tickers)} ativos testados...')

        self.df_resultados = pd.DataFrame(resultados)

        # Salva CSV
        out_csv = os.path.join(
            os.path.dirname(__file__), '..', '..', '..', '..', 'dados', 'adf_stationarity_results.csv'
        )
        os.makedirs(os.path.dirname(out_csv), exist_ok=True)
        self.df_resultados.to_csv(out_csv, index=False)
        logger.info(f'Resultados ADF salvos em {out_csv}')

        self._log_summary()
        return self.df_resultados

    # ------------------------------------------------------------------
    # Sumarizacao e Visualizacao
    # ------------------------------------------------------------------

    def _log_summary(self):
        """Loga o resumo agregado dos testes."""
        if self.df_resultados is None:
            return

        df = self.df_resultados.dropna(subset=['Estacionaria'])
        total = len(df)
        estacionarias = df['Estacionaria'].sum()
        pct = 100 * estacionarias / total if total > 0 else 0

        logger.info(
            f'\n{"="*60}\n'
            f'RESUMO DOS TESTES ADF — {self.coluna_spread}\n'
            f'  Total de ativos testados: {total}\n'
            f'  Estacionarias (rejeita H0): {int(estacionarias)} ({pct:.1f}%)\n'
            f'  Nao-estacionarias:           {int(total - estacionarias)} ({100-pct:.1f}%)\n'
            f'  Nivel de significancia: {self.alpha*100:.0f}%\n'
            f'{"="*60}'
        )

        if self.coluna_indexador and self.coluna_indexador in df.columns:
            resumo_idx = df.groupby('Indexador')['Estacionaria'].agg(['sum', 'count'])
            resumo_idx['Taxa_Estacionaria_%'] = (resumo_idx['sum'] / resumo_idx['count'] * 100).round(1)
            resumo_idx.columns = ['Estacionarias', 'Total', 'Taxa_Estacionaria_%']
            logger.info(f'\nResumo por Indexador:\n{resumo_idx.to_string()}')

    def get_summary_by_indexador(self) -> pd.DataFrame:
        """Retorna DataFrame com taxa de estacionariedade por indexador."""
        if self.df_resultados is None:
            raise RuntimeError("Execute run() antes de chamar este metodo.")

        df = self.df_resultados.dropna(subset=['Estacionaria'])
        if self.coluna_indexador and self.coluna_indexador in df.columns:
            grp = df.groupby('Indexador')['Estacionaria'].agg(['sum', 'count']).reset_index()
            grp.columns = ['Indexador', 'Estacionarias', 'Total']
            grp['Nao_Estacionarias'] = grp['Total'] - grp['Estacionarias']
            grp['Taxa_Estacionaria_%'] = (grp['Estacionarias'] / grp['Total'] * 100).round(1)
            return grp
        else:
            total = len(df)
            est = int(df['Estacionaria'].sum())
            return pd.DataFrame([{
                'Total': total,
                'Estacionarias': est,
                'Nao_Estacionarias': total - est,
                'Taxa_Estacionaria_%': round(100 * est / total, 1)
            }])

    def plot_summary(self, output_dir: str = '.') -> None:
        """
        Gera graficos de barra com a taxa de estacionariedade por indexador
        e histograma dos p-valores.
        """
        if self.df_resultados is None:
            raise RuntimeError("Execute run() antes de plotar.")

        os.makedirs(output_dir, exist_ok=True)
        df = self.df_resultados.dropna(subset=['Estacionaria', 'p_valor'])

        fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(12, 5))
        fig.suptitle(f'Testes de Estacionariedade ADF — {self.coluna_spread}', fontsize=13, fontweight='bold')

        # Taxa de estacionariedade por indexador
        resumo = self.get_summary_by_indexador()
        if 'Indexador' in resumo.columns:
            bars = ax1.bar(resumo['Indexador'], resumo['Taxa_Estacionaria_%'],
                           color=['steelblue', 'forestgreen', 'darkorange', 'mediumpurple'][:len(resumo)],
                           alpha=0.85, edgecolor='white')
            for bar, val in zip(bars, resumo['Taxa_Estacionaria_%']):
                ax1.text(bar.get_x() + bar.get_width() / 2, bar.get_height() + 1,
                         f'{val:.1f}%', ha='center', fontsize=10, fontweight='bold')
        else:
            pct = resumo['Taxa_Estacionaria_%'].iloc[0]
            ax1.bar(['Total'], [pct], color='steelblue', alpha=0.85)

        ax1.axhline(y=100 * (1 - self.alpha), color='firebrick', linestyle='--', alpha=0.7,
                    label=f'Referencia 5% ({100*(1-self.alpha):.0f}%)')
        ax1.set_ylim(0, 110)
        ax1.set_ylabel('Taxa de Estacionariedade (%)')
        ax1.set_title('Taxa de Rejeicao de H0 por Indexador')
        ax1.legend()
        ax1.grid(axis='y', alpha=0.3)

        # Histograma dos p-valores
        ax2.hist(df['p_valor'].clip(0, 0.5), bins=30, color='steelblue', alpha=0.8, edgecolor='white')
        ax2.axvline(x=self.alpha, color='firebrick', linestyle='--', linewidth=2,
                    label=f'alpha = {self.alpha}')
        ax2.set_xlabel('p-valor (ADF)')
        ax2.set_ylabel('Frequencia')
        ax2.set_title('Distribuicao dos p-valores ADF')
        ax2.legend()
        ax2.grid(alpha=0.3)

        plt.tight_layout()
        out_path = os.path.join(output_dir, 'adf_stationarity_summary.png')
        plt.savefig(out_path, dpi=180, bbox_inches='tight')
        plt.close()
        logger.info(f'Grafico ADF salvo em {out_path}')


if __name__ == '__main__':
    print('stationarity_testing: use StationarityTester(df, coluna_spread=\"Delta_Spread\").')
