import os
import logging
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
from typing import List, Dict, Tuple
from credit_tail_analytics.utils import dados_dir, graficos_dir
from credit_tail_analytics.visualization.frequentist_defense_visuals import EVENTOS_CREDITO

logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')
logger = logging.getLogger('BacktestFinanceiro')

CLUSTER_NUMERIC = {'Verde': 1, 'Amarelo': 2, 'Vermelho': 3, 'Inconclusivo': 0}

class BacktestFinanceiro:
    """
    Executa a validação cruzada financeira e econométrica do HMM vs K-Means.
    Gera:
    1. Matriz de Transição Empírica (Heatmap)
    2. Curvas de PnL (Buy & Hold vs K-Means vs HMM)
    3. Tabela de Early Warning Score (Lead Time)
    """

    def __init__(self, df_resultados: pd.DataFrame):
        self.df = df_resultados.copy()
        
        # Garante ordenação cronológica por ativo
        self.df['Data'] = pd.to_datetime(self.df['Data'])
        self.df.sort_values(by=['Ticker', 'Data'], inplace=True)
        
        # Garante que temos PU para calcular PnL real
        if 'PU' not in self.df.columns:
            logger.warning("Coluna PU não encontrada. Retornos não poderão ser calculados perfeitamente.")
            self.df['PU'] = 1000.0 # Placeholder estático se faltar
            self.df['Retorno_Ativo'] = 0.0
        else:
            # Shift no PU para calcular o pct_change corretamente por ativo
            self.df['Retorno_Ativo'] = self.df.groupby('Ticker')['PU'].pct_change().fillna(0.0)

    def plot_matriz_transicao(self):
        """
        Calcula e plota a matriz de transição empírica (dia a dia) para K-Means e HMM.
        """
        logger.info("Gerando Matrizes de Transição Empíricas...")
        
        for modelo in ['KMeans', 'HMM']:
            col = f'Cluster_{modelo}'
            if col not in self.df.columns:
                continue
                
            self.df[f'{col}_Prev'] = self.df.groupby('Ticker')[col].shift(1)
            
            # Filtra apenas transições válidas e exclui Inconclusivo
            mask_valid = (
                self.df[col].isin(['Verde', 'Amarelo', 'Vermelho']) & 
                self.df[f'{col}_Prev'].isin(['Verde', 'Amarelo', 'Vermelho'])
            )
            df_valid = self.df[mask_valid]
            
            # Conta transições e normaliza por linha (probabilidade)
            trans_counts = pd.crosstab(df_valid[f'{col}_Prev'], df_valid[col], normalize='index')
            
            # Garante a ordem [Verde, Amarelo, Vermelho]
            ordem = ['Verde', 'Amarelo', 'Vermelho']
            trans_counts = trans_counts.reindex(index=ordem, columns=ordem, fill_value=0.0)
            
            # Plota Heatmap
            fig, ax = plt.subplots(figsize=(6, 5))
            sns.heatmap(
                trans_counts, annot=True, fmt=".1%", cmap="Blues", 
                cbar=False, vmin=0, vmax=1, ax=ax
            )
            ax.set_title(f'Matriz de Transição Empírica - {modelo}')
            ax.set_ylabel('Estado Atual (t)')
            ax.set_xlabel('Estado Futuro (t+1)')
            plt.tight_layout()
            
            out_path = graficos_dir() / f'matriz_transicao_{modelo.lower()}.png'
            plt.savefig(str(out_path), dpi=150)
            plt.close()
            logger.info(f"Matriz de transição {modelo} salva em {out_path}")

    def simulate_portfolio(self):
        """
        Simula a curva de patrimônio de carteiras baseadas nos sinais dos modelos.
        - Sem Recompra: Stop out permanente quando vai para Vermelho.
        - Com Recompra: Volta ao ativo se ficar Verde.
        """
        logger.info("Rodando simulação de Backtest Financeiro de Portfólio (HMM vs KMeans)...")
        
        tickers = self.df['Ticker'].unique()
        
        # Inicializa portfólios (Patrimônio 1.0 no dia 0)
        datas_unicas = sorted(self.df['Data'].unique())
        df_pnl = pd.DataFrame(index=datas_unicas)
        
        # Buy & Hold (benchmark)
        df_pnl['Retorno_Medio_Mercado'] = self.df.groupby('Data')['Retorno_Ativo'].mean()
        df_pnl['BnH_Cum'] = (1 + df_pnl['Retorno_Medio_Mercado']).cumprod()
        
        # Alocadores: K-Means e HMM
        for modelo in ['KMeans', 'HMM']:
            col = f'Cluster_{modelo}'
            if col not in self.df.columns:
                continue
                
            sinal_sem_recompra = []
            sinal_com_recompra = []
            
            for ticker in tickers:
                df_ticker = self.df[self.df['Ticker'] == ticker].copy()
                
                is_alocado_sr = True
                is_alocado_cr = True
                
                s_sr = []
                s_cr = []
                
                for _, row in df_ticker.iterrows():
                    regime = row[col]
                    
                    if regime == 'Vermelho':
                        is_alocado_sr = False
                        is_alocado_cr = False
                    elif regime == 'Verde' and not is_alocado_cr:
                        is_alocado_cr = True
                        
                    s_sr.append(1.0 if is_alocado_sr else 0.0)
                    s_cr.append(1.0 if is_alocado_cr else 0.0)
                    
                # Desloca o sinal em 1 dia (vende amanhã ao preço de amanhã se hoje foi vermelho)
                s_sr = [1.0] + s_sr[:-1]
                s_cr = [1.0] + s_cr[:-1]
                
                df_ticker['Sinal_Sem_Recompra'] = s_sr
                df_ticker['Sinal_Com_Recompra'] = s_cr
                
                df_ticker['Retorno_Efetivo_SR'] = df_ticker['Retorno_Ativo'] * df_ticker['Sinal_Sem_Recompra']
                df_ticker['Retorno_Efetivo_CR'] = df_ticker['Retorno_Ativo'] * df_ticker['Sinal_Com_Recompra']
                
                sinal_sem_recompra.append(df_ticker[['Data', 'Retorno_Efetivo_SR']])
                sinal_com_recompra.append(df_ticker[['Data', 'Retorno_Efetivo_CR']])
                
            df_sr_all = pd.concat(sinal_sem_recompra)
            df_cr_all = pd.concat(sinal_com_recompra)
            
            df_pnl[f'Retorno_Diario_{modelo}_SR'] = df_sr_all.groupby('Data')['Retorno_Efetivo_SR'].mean()
            df_pnl[f'Retorno_Diario_{modelo}_CR'] = df_cr_all.groupby('Data')['Retorno_Efetivo_CR'].mean()
            
            df_pnl[f'{modelo}_Sem_Recompra_Cum'] = (1 + df_pnl[f'Retorno_Diario_{modelo}_SR']).cumprod()
            df_pnl[f'{modelo}_Com_Recompra_Cum'] = (1 + df_pnl[f'Retorno_Diario_{modelo}_CR']).cumprod()
            
        fig, axes = plt.subplots(1, 2, figsize=(16, 6))
        
        # Grafico 1: Sem Recompra
        axes[0].plot(df_pnl.index, df_pnl['BnH_Cum'], label='Benchmark (Buy & Hold)', color='gray', linestyle='--')
        if 'KMeans_Sem_Recompra_Cum' in df_pnl.columns:
            axes[0].plot(df_pnl.index, df_pnl['KMeans_Sem_Recompra_Cum'], label='K-Means (Sem Recompra)', color='#3498db')
        if 'HMM_Sem_Recompra_Cum' in df_pnl.columns:
            axes[0].plot(df_pnl.index, df_pnl['HMM_Sem_Recompra_Cum'], label='HMM (Sem Recompra)', color='#9b59b6', linewidth=2)
            
        axes[0].set_title('Estratégia: Stop Definitivo (Sem Recompra)')
        axes[0].set_ylabel('Patrimônio Acumulado')
        axes[0].grid(True, alpha=0.3)
        axes[0].legend()
        
        # Grafico 2: Com Recompra
        axes[1].plot(df_pnl.index, df_pnl['BnH_Cum'], label='Benchmark (Buy & Hold)', color='gray', linestyle='--')
        if 'KMeans_Com_Recompra_Cum' in df_pnl.columns:
            axes[1].plot(df_pnl.index, df_pnl['KMeans_Com_Recompra_Cum'], label='K-Means (Com Recompra)', color='#3498db')
        if 'HMM_Com_Recompra_Cum' in df_pnl.columns:
            axes[1].plot(df_pnl.index, df_pnl['HMM_Com_Recompra_Cum'], label='HMM (Com Recompra)', color='#9b59b6', linewidth=2)
            
        axes[1].set_title('Estratégia: Tática de Valor (Recompra no Verde)')
        axes[1].grid(True, alpha=0.3)
        axes[1].legend()
        
        plt.tight_layout()
        out_path = graficos_dir() / 'backtest_pnl_portfolio.png'
        plt.savefig(str(out_path), dpi=150)
        plt.close()
        logger.info(f"Curvas de PnL salvas em {out_path}")

    def generate_early_warning_score(self):
        """
        Calcula o Lead Time para os ativos da amostra.
        """
        logger.info("Gerando Tabela de Early Warning Score...")
        
        primeiro_vermelho = []
        for ticker in self.df['Ticker'].unique():
            df_t = self.df[self.df['Ticker'] == ticker]
            
            d_km = df_t[df_t['Cluster_KMeans'] == 'Vermelho']['Data'].min() if 'Cluster_KMeans' in df_t.columns else pd.NaT
            d_hmm = df_t[df_t['Cluster_HMM'] == 'Vermelho']['Data'].min() if 'Cluster_HMM' in df_t.columns else pd.NaT
            
            # Spread e Vol antes da crise
            vol_pre = df_t['Volatilidade_EGARCH'].max()
            spread_max = df_t['Taxa_Ativo'].max()
            
            primeiro_vermelho.append({
                'Ticker': ticker,
                '1o_Alerta_KMeans': d_km,
                '1o_Alerta_HMM': d_hmm,
                'Max_Volatilidade': vol_pre,
                'Max_Spread': spread_max
            })
            
        df_ew = pd.DataFrame(primeiro_vermelho)
        df_ew = df_ew.dropna(subset=['1o_Alerta_KMeans', '1o_Alerta_HMM'], how='all')
        
        out_path = dados_dir() / 'tabela_early_warning.csv'
        df_ew.to_csv(str(out_path), index=False)
        logger.info(f"Early warning salvo em {out_path}")

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
