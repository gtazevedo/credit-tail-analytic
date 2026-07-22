import os
import logging
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
from typing import List, Dict, Tuple
from credit_tail_analytics.utils import dados_dir, graficos_dir
import warnings

warnings.filterwarnings('ignore')
logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')
logger = logging.getLogger('BacktestFinanceiro')

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
        df_ev = ev.pu_eventos(timeout=300)  # Alto timeout para carga pesada
        if not df_ev.empty:
            # Tratamento da coluna de PU
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


class BacktestFinanceiro:
    """
    Executa a validação financeira com simulação real de portfólio.
    """
    def __init__(self, df_resultados: pd.DataFrame):
        self.df = df_resultados.copy()
        self.df['Data'] = pd.to_datetime(self.df['Data'])
        self.df.sort_values(by=['Ticker', 'Data'], inplace=True)
        
        # Faz o download e incorpora os eventos
        df_ev = download_eventos_financeiros()
        
        if not df_ev.empty and 'Data' in df_ev.columns and 'Ativo' in df_ev.columns:
            df_ev['Data'] = pd.to_datetime(df_ev['Data'], format='%d/%m/%Y', errors='coerce')
            df_ev_grouped = df_ev.groupby(['Ativo', 'Data'])['Valor_Evento'].sum().reset_index()
            df_ev_grouped.rename(columns={'Ativo': 'Ticker'}, inplace=True)
            
            self.df = pd.merge(self.df, df_ev_grouped, on=['Ticker', 'Data'], how='left')
            self.df['Valor_Evento'] = self.df['Valor_Evento'].fillna(0.0)
        else:
            self.df['Valor_Evento'] = 0.0
            
        # Garante que temos PU
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

        if 'Credit_Tail_Risk_Score' in self.df.columns:
            def categorize_ensemble(score):
                if pd.isna(score): return 'Inconclusivo'
                if score >= 60: return 'Vermelho'
                elif score >= 35: return 'Amarelo'
                else: return 'Verde'
            self.df['Cluster_Ensemble'] = self.df['Credit_Tail_Risk_Score'].apply(categorize_ensemble)

    def plot_matriz_transicao(self):
        logger.info("Gerando Matrizes de Transição Empíricas...")
        for modelo in ['KMeans', 'HMM', 'Ensemble']:
            col = f'Cluster_{modelo}'
            if col not in self.df.columns: continue
                
            self.df[f'{col}_Prev'] = self.df.groupby('Ticker')[col].shift(1)
            mask_valid = (self.df[col].isin(['Verde', 'Amarelo', 'Vermelho']) & 
                          self.df[f'{col}_Prev'].isin(['Verde', 'Amarelo', 'Vermelho']))
            df_valid = self.df[mask_valid]
            
            if df_valid.empty: continue
            
            trans_counts = pd.crosstab(df_valid[f'{col}_Prev'], df_valid[col], normalize='index')
            ordem = ['Verde', 'Amarelo', 'Vermelho']
            trans_counts = trans_counts.reindex(index=ordem, columns=ordem, fill_value=0.0)
            
            fig, ax = plt.subplots(figsize=(6, 5))
            sns.heatmap(trans_counts, annot=True, fmt=".1%", cmap="Blues", cbar=False, vmin=0, vmax=1, ax=ax)
            ax.set_title(f'Matriz de Transição Empírica - {modelo}')
            ax.set_ylabel('Estado Atual (t)')
            ax.set_xlabel('Estado Futuro (t+1)')
            plt.tight_layout()
            
            out_path = graficos_dir() / f'matriz_transicao_{modelo.lower()}.png'
            plt.savefig(str(out_path), dpi=150)
            plt.close()

    def simulate_portfolio(self, initial_capital=1000000.0, cure_days=15):
        logger.info("Rodando simulação de Portfólio (R$ 1MM, Cura 15 dias, Eventos Inclusos)...")
        
        tickers = self.df['Ticker'].unique()
        datas_unicas = sorted(self.df['Data'].unique())
        df_pnl = pd.DataFrame(index=datas_unicas)
        
        # CDI Mock: 0.04% ao dia (aprox. 10.5% ao ano)
        daily_cdi = 0.0004 
        
        # Simula Benchmark
        capital_bnh = {t: 0.0 for t in tickers}
        cash_bnh = initial_capital
        history_bnh = []
        is_first_day = True
        
        for current_date, group in self.df.groupby('Data'):
            retornos = dict(zip(group['Ticker'], group['Retorno_Total']))
            for t in capital_bnh:
                if t in retornos:
                    capital_bnh[t] *= (1.0 + retornos[t])
            cash_bnh *= (1.0 + daily_cdi)
            
            if is_first_day:
                ativos_dia = group['Ticker'].tolist()
                if len(ativos_dia) > 0:
                    aporte = cash_bnh / len(ativos_dia)
                    for t in ativos_dia: capital_bnh[t] += aporte
                    cash_bnh = 0.0
                is_first_day = False
                
            history_bnh.append(sum(capital_bnh.values()) + cash_bnh)
        
        df_pnl['BnH_Cum'] = history_bnh
        
        # Simula Alocadores
        for modelo in ['KMeans', 'HMM', 'Ensemble']:
            col = f'Cluster_{modelo}'
            if col not in self.df.columns:
                continue
                
            capital = {t: 0.0 for t in tickers}
            cash = 0.0
            dias_cura = {t: None for t in tickers}
            history = []
            is_first_day = True
            
            for current_date, group in self.df.groupby('Data'):
                retornos = dict(zip(group['Ticker'], group['Retorno_Total']))
                regimes = dict(zip(group['Ticker'], group[col]))
                
                # 1. Rendimento do capital alocado
                for t in capital:
                    if t in retornos:
                        capital[t] *= (1.0 + retornos[t])
                        
                cash *= (1.0 + daily_cdi)
                
                if is_first_day:
                    ativos_dia = group['Ticker'].tolist()
                    if len(ativos_dia) > 0:
                        aporte = initial_capital / len(ativos_dia)
                        for t in ativos_dia:
                            capital[t] += aporte
                        cash = 0.0
                    is_first_day = False
                else:
                    # 2. Executar Stop (Venda)
                    cash_liberado = 0.0
                    for t, rgm in regimes.items():
                        if rgm == 'Vermelho':
                            dias_cura[t] = 0
                            cash_liberado += capital[t]
                            capital[t] = 0.0
                        else:
                            if dias_cura[t] is not None:
                                dias_cura[t] += 1
                    cash += cash_liberado
                    
                    # 3. Executar Reaplicação (Compra)
                    if cash > 0.01:
                        elegiveis = []
                        for t, rgm in regimes.items():
                            if rgm == 'Verde':
                                if dias_cura[t] is None or dias_cura[t] >= cure_days:
                                    elegiveis.append(t)
                                    
                        if len(elegiveis) > 0:
                            aporte = cash / len(elegiveis)
                            for t in elegiveis:
                                capital[t] += aporte
                            cash = 0.0
                
                history.append(sum(capital.values()) + cash)
                
            df_pnl[f'{modelo}_Cum'] = history
            
        # Gráficos
        plt.figure(figsize=(10, 6))
        plt.plot(df_pnl.index, df_pnl['BnH_Cum'], label='Benchmark (Buy & Hold)', color='gray', linestyle='--')
        
        if 'KMeans_Cum' in df_pnl.columns:
            plt.plot(df_pnl.index, df_pnl['KMeans_Cum'], label='K-Means (Tático)', color='#3498db', alpha=0.8)
        if 'HMM_Cum' in df_pnl.columns:
            plt.plot(df_pnl.index, df_pnl['HMM_Cum'], label='HMM (Tático)', color='#9b59b6', alpha=0.8)
        if 'Ensemble_Cum' in df_pnl.columns:
            plt.plot(df_pnl.index, df_pnl['Ensemble_Cum'], label='Ensemble (Tático)', color='#e74c3c', linewidth=2.5)
            
        plt.title('Simulação de Portfólio - Reinvestimento de Eventos e Stop Loss')
        plt.ylabel('Patrimônio (BRL)')
        plt.grid(True, alpha=0.3)
        plt.legend()
        plt.tight_layout()
        
        out_path = graficos_dir() / 'backtest_pnl_portfolio.png'
        plt.savefig(str(out_path), dpi=200)
        plt.close()
        logger.info(f"Curvas de PnL salvas em {out_path}")

    def generate_early_warning_score(self):
        primeiro_vermelho = []
        for ticker in self.df['Ticker'].unique():
            df_t = self.df[self.df['Ticker'] == ticker]
            
            d_km = df_t[df_t['Cluster_KMeans'] == 'Vermelho']['Data'].min() if 'Cluster_KMeans' in df_t.columns else pd.NaT
            d_hmm = df_t[df_t['Cluster_HMM'] == 'Vermelho']['Data'].min() if 'Cluster_HMM' in df_t.columns else pd.NaT
            d_ens = df_t[df_t['Cluster_Ensemble'] == 'Vermelho']['Data'].min() if 'Cluster_Ensemble' in df_t.columns else pd.NaT
            
            vol_pre = df_t['Volatilidade_EGARCH'].max()
            spread_max = df_t['Taxa_Ativo'].max()
            
            primeiro_vermelho.append({
                'Ticker': ticker, '1o_Alerta_KMeans': d_km, '1o_Alerta_HMM': d_hmm,
                '1o_Alerta_Ensemble': d_ens, 'Max_Volatilidade': vol_pre, 'Max_Spread': spread_max
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
