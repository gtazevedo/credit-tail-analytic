import os
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
from sklearn.metrics import silhouette_score
import logging

logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')
logger = logging.getLogger('FrequentistDefense')

def run_defense_visuals():
    base_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    results_path = os.path.join(base_dir, "dados", "resultado_frequentist_engine.csv")
    out_dir = os.path.join(base_dir, "graficos")
    
    if not os.path.exists(out_dir):
        os.makedirs(out_dir)

    if not os.path.exists(results_path):
        logger.error(f"Arquivo não encontrado: {results_path}")
        return

    logger.info("Carregando resultados do Rolling K-Means (Frequentist Engine)...")
    df = pd.read_csv(results_path)
    df['Data_Janela'] = pd.to_datetime(df['Data_Janela'])
    
    cluster_palette = {'Verde': '#2ecc71', 'Amarelo': '#f1c40f', 'Vermelho': '#e74c3c'}
    
    # ---------------------------------------------------------
    # 1. SCATTER PLOT DA ÚLTIMA JANELA
    # ---------------------------------------------------------
    logger.info("Gerando Scatter Plot da Última Janela...")
    ultima_janela = df['Data_Janela'].max()
    df_ult = df[df['Data_Janela'] == ultima_janela].copy()
    
    plt.figure(figsize=(10, 6))
    sns.scatterplot(
        data=df_ult, 
        x='Volatilidade_EGARCH', 
        y='Taxa_Ajustada_Prazo', 
        hue='Cluster_Risco',
        palette=cluster_palette,
        alpha=0.7,
        s=80,
        edgecolor='k'
    )
    plt.title(f"Mapeamento Transversal de Risco de Crédito (Cross-Section: {ultima_janela.date()})\nClusterização K-Means (Bypass da ETTJ)")
    plt.xlabel("Volatilidade Condicional Anualizada (EGARCH-t)")
    plt.ylabel("Prêmio de Risco Relativo Ajustado (Taxa / ln(DU))")
    plt.grid(True, linestyle='--', alpha=0.5)
    
    # Destacar os Cisnes Negros
    df_vermelhos = df_ult[df_ult['Cluster_Risco'] == 'Vermelho']
    for idx, row in df_vermelhos.iterrows():
        plt.annotate(row['Ticker'], (row['Volatilidade_EGARCH'], row['Taxa_Ajustada_Prazo']),
                     xytext=(5, 5), textcoords='offset points', fontsize=9, color='darkred', fontweight='bold')
                     
    plt.tight_layout()
    plt.savefig(os.path.join(out_dir, "01_cross_section_risco.png"), dpi=300)
    plt.close()

    # ---------------------------------------------------------
    # 2. SILHOUETTE SCORE AO LONGO DO TEMPO (EFICIÊNCIA K-MEANS)
    # ---------------------------------------------------------
    logger.info("Calculando Silhouette Score Histórico para validação...")
    silhouette_scores = []
    datas = sorted(df['Data_Janela'].unique())
    
    for dt in datas:
        df_dt = df[df['Data_Janela'] == dt].dropna(subset=['Taxa_Ajustada_Prazo', 'Volatilidade_EGARCH', 'Score_Liquidez'])
        if len(df_dt['Cluster_Risco'].unique()) > 1:
            X = df_dt[['Taxa_Ajustada_Prazo', 'Volatilidade_EGARCH', 'Score_Liquidez']]
            # O MinMaxScaler/StandardScaler já ocorreu, mas o score é calculado na escala original ou padronizada. 
            # Como a defesa foca na separação visual geométrica:
            labels = df_dt['Cluster_Risco']
            score = silhouette_score(X, labels)
            silhouette_scores.append((dt, score))
            
    if silhouette_scores:
        df_sil = pd.DataFrame(silhouette_scores, columns=['Data', 'Silhouette_Score'])
        plt.figure(figsize=(12, 5))
        sns.lineplot(data=df_sil, x='Data', y='Silhouette_Score', color='midnightblue', linewidth=2)
        plt.axhline(df_sil['Silhouette_Score'].mean(), color='red', linestyle='--', label=f"Média: {df_sil['Silhouette_Score'].mean():.2f}")
        plt.title("Evolução da Qualidade da Clusterização (Silhouette Score)")
        plt.xlabel("Janela de Tempo Móvel")
        plt.ylabel("Silhouette Score (-1 a 1)")
        plt.legend()
        plt.grid(True, alpha=0.3)
        plt.tight_layout()
        plt.savefig(os.path.join(out_dir, "02_silhouette_score_kmeans.png"), dpi=300)
        plt.close()

    # ---------------------------------------------------------
    # 3. CONCENTRAÇÃO E ESTRESSE SISTÊMICO (CONTAGION PROXY)
    # ---------------------------------------------------------
    logger.info("Gerando Análise de Contágio (Percentual de Cisnes Negros)...")
    df_dist = df.groupby(['Data_Janela', 'Cluster_Risco']).size().unstack(fill_value=0)
    df_dist_pct = df_dist.div(df_dist.sum(axis=1), axis=0) * 100
    
    plt.figure(figsize=(12, 6))
    plt.fill_between(df_dist_pct.index, 0, df_dist_pct.get('Verde', 0), color='#2ecc71', alpha=0.6, label='Verde (Normal)')
    plt.fill_between(df_dist_pct.index, df_dist_pct.get('Verde', 0), df_dist_pct.get('Verde', 0) + df_dist_pct.get('Amarelo', 0), color='#f1c40f', alpha=0.6, label='Amarelo (Alerta)')
    plt.fill_between(df_dist_pct.index, df_dist_pct.get('Verde', 0) + df_dist_pct.get('Amarelo', 0), 100, color='#e74c3c', alpha=0.6, label='Vermelho (Estresse)')
    
    plt.title("Evolução Sistêmica dos Regimes de Crédito (Distribuição de Clusters)")
    plt.xlabel("Período (Janela)")
    plt.ylabel("% de Ativos no Mercado")
    plt.legend(loc='lower right')
    plt.margins(x=0, y=0)
    plt.tight_layout()
    plt.savefig(os.path.join(out_dir, "03_distribuicao_sistemica_clusters.png"), dpi=300)
    plt.close()
    
    # ---------------------------------------------------------
    # 4. BOXPLOT: SEPARAÇÃO ESTATÍSTICA DE PRÊMIO DE RISCO
    # ---------------------------------------------------------
    logger.info("Gerando Boxplot de Distribuição de Prêmio de Risco...")
    plt.figure(figsize=(10, 6))
    sns.boxplot(data=df_ult, x='Cluster_Risco', y='Taxa_Ajustada_Prazo', palette=cluster_palette, order=['Verde', 'Amarelo', 'Vermelho'])
    plt.title("Distribuição do Prêmio de Risco Ajustado por Cluster (Última Janela)")
    plt.xlabel("Regime de Crédito")
    plt.ylabel("Taxa Ajustada pelo Prazo")
    plt.yscale('log') # Escala log para lidar com outliers extremos
    plt.grid(True, linestyle='--', alpha=0.4)
    plt.tight_layout()
    plt.savefig(os.path.join(out_dir, "04_boxplot_separacao_clusters.png"), dpi=300)
    plt.close()

    # ---------------------------------------------------------
    # 5. ESTUDO DE CASO EMPÍRICO: LOJAS AMERICANAS (LAMEA1)
    # ---------------------------------------------------------
    logger.info("Gerando Estudo de Caso Empírico (LAMEA1 - Americanas)...")
    lame = df[df['Ticker'] == 'LAMEA1'].copy()
    if not lame.empty:
        lame = lame.sort_values('Data_Janela')
        # Converter clusters em numérico para plotar a trajetória
        cluster_map = {'Verde': 1, 'Amarelo': 2, 'Vermelho': 3}
        lame['Alerta_Numerico'] = lame['Cluster_Risco'].map(cluster_map)
        
        plt.figure(figsize=(12, 5))
        plt.plot(lame['Data_Janela'], lame['Alerta_Numerico'], marker='o', linestyle='-', color='darkred', linewidth=2)
        plt.yticks([1, 2, 3], ['Verde\n(Normal)', 'Amarelo\n(Alerta)', 'Vermelho\n(Cisne Negro)'])
        plt.title("Estudo de Caso Empírico (Lojas Americanas - LAMEA1)\nTrajetória de Rebaixamento de Crédito")
        plt.xlabel("Evolução no Tempo")
        plt.ylabel("Sinal do Motor de Risco")
        plt.grid(True, alpha=0.3)
        plt.tight_layout()
        plt.savefig(os.path.join(out_dir, "05_estudo_caso_americanas.png"), dpi=300)
        plt.close()
    
    # ---------------------------------------------------------
    # 6. ESTUDO DE CASO EMPÍRICO: GPA / PÃO DE AÇÚCAR (CBRDA7)
    # ---------------------------------------------------------
    logger.info("Gerando Estudo de Caso Empírico (CBRDA7 - GPA/Pão de Açúcar)...")
    cbrd = df[df['Ticker'] == 'CBRDA7'].copy()
    if not cbrd.empty:
        cbrd = cbrd.sort_values('Data_Janela')
        cbrd['Alerta_Numerico'] = cbrd['Cluster_Risco'].map(cluster_map)
        
        plt.figure(figsize=(12, 5))
        plt.plot(cbrd['Data_Janela'], cbrd['Alerta_Numerico'], marker='s', linestyle='-', color='darkorange', linewidth=2)
        plt.yticks([1, 2, 3], ['Verde\n(Normal)', 'Amarelo\n(Alerta)', 'Vermelho\n(Cisne Negro)'])
        plt.title("Estudo de Caso Empírico (Pão de Açúcar / GPA - CBRDA7)\nTrajetória de Rebaixamento de Crédito")
        plt.xlabel("Evolução no Tempo")
        plt.ylabel("Sinal do Motor de Risco")
        plt.grid(True, alpha=0.3)
        plt.tight_layout()
        plt.savefig(os.path.join(out_dir, "06_estudo_caso_pao_de_acucar.png"), dpi=300)
        plt.close()

    logger.info(f"Visualizações e Testes de Defesa salvos em: {out_dir}")

if __name__ == "__main__":
    run_defense_visuals()
