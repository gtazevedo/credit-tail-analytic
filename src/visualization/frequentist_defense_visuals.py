import os
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
from sklearn.metrics import silhouette_score
import logging
from typing import List

logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')
logger = logging.getLogger('FrequentistDefense')

CLUSTER_PALETTE = {'Verde': '#2ecc71', 'Amarelo': '#f1c40f', 'Vermelho': '#e74c3c'}
CLUSTER_MAP = {'Verde': 1, 'Amarelo': 2, 'Vermelho': 3}

def plot_cross_section(df: pd.DataFrame, out_dir: str):
    logger.info("Gerando Scatter Plot da Última Janela...")
    ultima_janela = df['Data_Janela'].max()
    df_ult = df[df['Data_Janela'] == ultima_janela].copy()
    
    if df_ult.empty: return
    
    plt.figure(figsize=(10, 6))
    sns.scatterplot(
        data=df_ult, 
        x='Volatilidade_EGARCH', 
        y='Taxa_Ajustada_Prazo', 
        hue='Cluster_Risco_KMeans',
        palette=CLUSTER_PALETTE,
        alpha=0.7,
        s=80,
        edgecolor='k'
    )
    plt.title(f"Mapeamento Transversal de Risco de Crédito (Cross-Section: {ultima_janela.date()})")
    plt.xlabel("Volatilidade Condicional Anualizada (EGARCH-t)")
    plt.ylabel("Prêmio de Risco Relativo Ajustado (Taxa / ln(DU))")
    plt.grid(True, linestyle='--', alpha=0.5)
    
    df_vermelhos = df_ult[df_ult['Cluster_Risco_KMeans'] == 'Vermelho']
    for idx, row in df_vermelhos.iterrows():
        plt.annotate(row['Ticker'], (row['Volatilidade_EGARCH'], row['Taxa_Ajustada_Prazo']),
                     xytext=(5, 5), textcoords='offset points', fontsize=9, color='darkred', fontweight='bold')
                     
    plt.tight_layout()
    plt.savefig(os.path.join(out_dir, "01_cross_section_risco.png"), dpi=300)
    plt.close()

def plot_silhouette(df: pd.DataFrame, out_dir: str, split_date: str):
    logger.info("Calculando Silhouette Score Histórico para validação...")
    silhouette_scores = []
    datas = sorted(df['Data_Janela'].unique())
    
    for dt in datas:
        df_dt = df[df['Data_Janela'] == dt].dropna(subset=['Taxa_Ajustada_Prazo', 'Volatilidade_EGARCH', 'Score_Liquidez'])
        if len(df_dt['Cluster_Risco_KMeans'].unique()) > 1:
            X = df_dt[['Taxa_Ajustada_Prazo', 'Volatilidade_EGARCH', 'Score_Liquidez']]
            labels = df_dt['Cluster_Risco_KMeans']
            score = silhouette_score(X, labels)
            silhouette_scores.append((dt, score))
            
    if silhouette_scores:
        df_sil = pd.DataFrame(silhouette_scores, columns=['Data', 'Silhouette_Score'])
        plt.figure(figsize=(12, 5))
        sns.lineplot(data=df_sil, x='Data', y='Silhouette_Score', color='midnightblue', linewidth=2)
        plt.axhline(df_sil['Silhouette_Score'].mean(), color='red', linestyle='--', label=f"Média: {df_sil['Silhouette_Score'].mean():.2f}")
        
        plt.axvline(pd.to_datetime(split_date), color='black', linestyle=':', linewidth=2, label='Início Out-of-Sample')
        
        plt.title("Evolução da Qualidade da Clusterização (Silhouette Score)")
        plt.xlabel("Janela de Tempo")
        plt.ylabel("Silhouette Score (-1 a 1)")
        plt.legend()
        plt.grid(True, alpha=0.3)
        plt.tight_layout()
        plt.savefig(os.path.join(out_dir, "02_silhouette_score_kmeans.png"), dpi=300)
        plt.close()

def plot_contagion(df: pd.DataFrame, out_dir: str, split_date: str):
    logger.info("Gerando Análise de Contágio (Percentual de Cisnes Negros)...")
    df_dist = df.groupby(['Data_Janela', 'Cluster_Risco_KMeans']).size().unstack(fill_value=0)
    df_dist_pct = df_dist.div(df_dist.sum(axis=1), axis=0) * 100
    
    plt.figure(figsize=(12, 6))
    plt.fill_between(df_dist_pct.index, 0, df_dist_pct.get('Verde', 0), color='#2ecc71', alpha=0.6, label='Verde (Normal)')
    plt.fill_between(df_dist_pct.index, df_dist_pct.get('Verde', 0), df_dist_pct.get('Verde', 0) + df_dist_pct.get('Amarelo', 0), color='#f1c40f', alpha=0.6, label='Amarelo (Alerta)')
    plt.fill_between(df_dist_pct.index, df_dist_pct.get('Verde', 0) + df_dist_pct.get('Amarelo', 0), 100, color='#e74c3c', alpha=0.6, label='Vermelho (Estresse)')
    
    plt.axvline(pd.to_datetime(split_date), color='black', linestyle='--', linewidth=2, label='Início Out-of-Sample')
    
    plt.title("Evolução Sistêmica dos Regimes de Crédito (Distribuição de Clusters)")
    plt.xlabel("Período (Janela)")
    plt.ylabel("% de Ativos no Mercado")
    plt.legend(loc='lower right')
    plt.margins(x=0, y=0)
    plt.tight_layout()
    plt.savefig(os.path.join(out_dir, "03_distribuicao_sistemica_clusters.png"), dpi=300)
    plt.close()

def plot_boxplot(df: pd.DataFrame, out_dir: str):
    logger.info("Gerando Boxplot de Distribuição de Prêmio de Risco...")
    ultima_janela = df['Data_Janela'].max()
    df_ult = df[df['Data_Janela'] == ultima_janela].copy()
    
    if df_ult.empty: return
    
    plt.figure(figsize=(10, 6))
    sns.boxplot(data=df_ult, x='Cluster_Risco_KMeans', y='Taxa_Ajustada_Prazo', palette=CLUSTER_PALETTE, order=['Verde', 'Amarelo', 'Vermelho'])
    plt.title("Distribuição do Prêmio de Risco Ajustado por Cluster (Última Janela)")
    plt.xlabel("Regime de Crédito")
    plt.ylabel("Taxa Ajustada pelo Prazo")
    plt.yscale('log')
    plt.grid(True, linestyle='--', alpha=0.4)
    plt.tight_layout()
    plt.savefig(os.path.join(out_dir, "04_boxplot_separacao_clusters.png"), dpi=300)
    plt.close()

def plot_case_study(df: pd.DataFrame, tickers: List[str], title: str, filename: str, out_dir: str, split_date: str):
    logger.info(f"Gerando Estudo de Caso Empírico ({title})...")
    
    plt.figure(figsize=(12, 5))
    
    for ticker in tickers:
        df_ticker = df[df['Ticker'] == ticker].copy()
        if not df_ticker.empty:
            df_ticker = df_ticker.sort_values('Data_Janela')
            df_ticker['Alerta_Numerico'] = df_ticker['Cluster_Risco_KMeans'].map(CLUSTER_MAP)
            plt.plot(df_ticker['Data_Janela'], df_ticker['Alerta_Numerico'], marker='o', linestyle='-', linewidth=2, label=ticker)
    
    plt.axvline(pd.to_datetime(split_date), color='black', linestyle='--', linewidth=2, label='Início Out-of-Sample')
    
    plt.yticks([1, 2, 3], ['Verde\n(Normal)', 'Amarelo\n(Alerta)', 'Vermelho\n(Cisne Negro)'])
    plt.title(f"Estudo de Caso Empírico: {title}\nTrajetória de Rebaixamento de Crédito")
    plt.xlabel("Evolução no Tempo")
    plt.ylabel("Sinal do Motor de Risco")
    plt.legend()
    plt.grid(True, alpha=0.3)
    plt.tight_layout()
    plt.savefig(os.path.join(out_dir, filename), dpi=300)
    plt.close()

def run_defense_visuals():
    base_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    results_path = os.path.join(base_dir, "dados", "resultado_frequentist_engine.csv")
    out_dir = os.path.join(base_dir, "graficos")
    split_date = '2023-01-01'
    
    if not os.path.exists(out_dir):
        os.makedirs(out_dir)

    if not os.path.exists(results_path):
        logger.error(f"Arquivo não encontrado: {results_path}")
        return

    logger.info("Carregando resultados do Motor...")
    df = pd.read_csv(results_path)
    df['Data_Janela'] = pd.to_datetime(df['Data_Janela'])
    
    if 'Cluster_Risco_KMeans' not in df.columns and 'Cluster_Risco' in df.columns:
        df['Cluster_Risco_KMeans'] = df['Cluster_Risco']
        
    # Executando gráficos via funções
    plot_cross_section(df, out_dir)
    plot_silhouette(df, out_dir, split_date)
    plot_contagion(df, out_dir, split_date)
    plot_boxplot(df, out_dir)
    
    # Estudos de Caso (Amostras In-Sample e Out-of-Sample)
    plot_case_study(df, ['LAME29', 'LAMEA1'], "Lojas Americanas", "05_estudo_caso_americanas.png", out_dir, split_date)
    plot_case_study(df, ['CBRDA7', 'CBRDA8'], "GPA / Pão de Açúcar", "06_estudo_caso_pao_de_acucar.png", out_dir, split_date)
    plot_case_study(df, ['LIGHA6', 'LIGHA9'], "Light S.A.", "07_estudo_caso_light.png", out_dir, split_date)
    
    # Novos casos
    plot_case_study(df, ['VVAR11', 'VVAR26', 'VVAR15', 'VVAR25'], "Via Varejo (Casas Bahia)", "08_estudo_caso_via_varejo.png", out_dir, split_date)
    plot_case_study(df, ['RDORB7', 'RDORC7', 'RDORA5'], "Rede D'Or", "09_estudo_caso_rede_dor.png", out_dir, split_date)
    plot_case_study(df, ['SULA19', 'SULA29'], "Sul América", "10_estudo_caso_sulamerica.png", out_dir, split_date)
    plot_case_study(df, ['GOLL11', 'GOLL21', 'GLAS11', 'VRGL11'], "GOL Linhas Aéreas", "11_estudo_caso_gol.png", out_dir, split_date)
    plot_case_study(df, ['APOL11', 'POLI11', 'POLI21', 'PLSH11'], "Polishop", "12_estudo_caso_polishop.png", out_dir, split_date)

    logger.info(f"Visualizações e Testes de Defesa salvos em: {out_dir}")

if __name__ == "__main__":
    run_defense_visuals()
