import os
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.dates as mdates
import seaborn as sns
import logging
from typing import List, Dict, Optional
from scipy.stats import chi2 as chi2_dist

logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')
logger = logging.getLogger('FrequentistDefense')

CLUSTER_PALETTE = {'Verde': '#2ecc71', 'Amarelo': '#f1c40f', 'Vermelho': '#e74c3c'}
CLUSTER_MAP = {'Verde': 1, 'Amarelo': 2, 'Vermelho': 3}

# ---------------------------------------------------------------------------
# Dicionário de eventos de crédito conhecidos (ground truth narrativo)
# Chave: título do caso. Valor: lista de (data_str, label_curto).
# ---------------------------------------------------------------------------
EVENTOS_CREDITO: Dict[str, List] = {
    'Lojas Americanas': [
        ('2023-01-11', 'Fraude Contábil\nR$20bi'),
    ],
    'GPA / Pão de Açúcar': [
        ('2024-06-01', 'Saída do\nGrupo Casino'),
        ('2026-02-01', 'Déficit Capital\nde Giro'),
        ('2026-03-01', 'Recuperação\nExtrajudicial'),
    ],
    'Light S.A.': [
        ('2023-06-26', 'Recuperação\nJudicial'),
    ],
    'Via Varejo (Casas Bahia)': [
        ('2023-06-01', 'Reestruturação\nOperacional'),
    ],
    "GOL Linhas Aéreas": [
        ('2024-01-25', 'Chapter 11\n(EUA)'),
        ('2025-04-01', 'Chapter 11\nEncerrado'),
    ],
}

def plot_cross_section(df: pd.DataFrame, out_dir: str):
    logger.info("Gerando Scatter Plot da Última Janela...")
    ultima_janela = df['Data_Janela'].max()
    df_ult = df[df['Data_Janela'] == ultima_janela].copy()
    
    if df_ult.empty: return
    
    plt.figure(figsize=(10, 6))
    sns.scatterplot(
        data=df_ult, 
        x='ES_99', 
        y='Taxa_Ajustada_Prazo', 
        hue='Cluster_Risco_Mahalanobis',
        palette=CLUSTER_PALETTE,
        alpha=0.7,
        s=80,
        edgecolor='k'
    )
    plt.title(f"Mapeamento Transversal de Risco de Crédito (Cross-Section: {ultima_janela.date()})")
    plt.xlabel("Expected Shortfall (ES 99%)")
    plt.ylabel("Prêmio de Risco Relativo Ajustado (Taxa / ln(DU))")
    plt.grid(True, linestyle='--', alpha=0.5)
    
    df_vermelhos = df_ult[df_ult['Cluster_Risco_Mahalanobis'] == 'Vermelho']
    for idx, row in df_vermelhos.iterrows():
        plt.annotate(row['Ticker'], (row['ES_99'], row['Taxa_Ajustada_Prazo']),
                     xytext=(5, 5), textcoords='offset points', fontsize=9, color='darkred', fontweight='bold')
                     
    plt.tight_layout()
    plt.savefig(os.path.join(out_dir, "01_cross_section_risco.png"), dpi=300)
    plt.close()

def plot_mahalanobis_distribution(df: pd.DataFrame, out_dir: str, split_date: str):
    """
    Substitui o Silhouette Score (incompatível com deteção de anomalias por limiar χ2).
    Plota a distribuição mensal da Distância de Mahalanobis como violin chart,
    sobrepondo os limiares teóricos de 90% e 99% da χ2 (4 graus de liberdade).
    """
    logger.info("Gerando distribuição da Distância de Mahalanobis por período...")
    
    if 'Distancia_Mahalanobis' not in df.columns:
        logger.warning("Coluna 'Distancia_Mahalanobis' não encontrada. Pulando violin chart.")
        return
    
    # Número de features usadas no vetor (4: Taxa, ES, ZScore, Vol_GARCH)
    n_features = 4
    limiar_amarelo = chi2_dist.ppf(0.90, df=n_features)
    limiar_vermelho = chi2_dist.ppf(0.99, df=n_features)
    
    df_plot = df[['Data_Janela', 'Distancia_Mahalanobis']].dropna().copy()
    df_plot['Data_Janela'] = pd.to_datetime(df_plot['Data_Janela'])
    df_plot['Mes'] = df_plot['Data_Janela'].dt.to_period('Q').dt.to_timestamp()  # agrupa por trimestre
    
    fig, ax = plt.subplots(figsize=(16, 6))
    
    # Boxplot trim por trim
    trimestres = sorted(df_plot['Mes'].unique())
    data_bp = [df_plot[df_plot['Mes'] == t]['Distancia_Mahalanobis'].values for t in trimestres]
    bp = ax.boxplot(data_bp, positions=range(len(trimestres)), widths=0.6,
                    patch_artist=True, showfliers=False,
                    boxprops=dict(facecolor='#4a90d9', alpha=0.6),
                    medianprops=dict(color='navy', linewidth=2),
                    whiskerprops=dict(color='gray'),
                    capprops=dict(color='gray'))
    
    ax.set_xticks(range(len(trimestres)))
    ax.set_xticklabels([
        f"{pd.to_datetime(t).year}Q{(pd.to_datetime(t).month - 1) // 3 + 1}"
        for t in trimestres
    ], rotation=45, ha='right', fontsize=8)
    
    # Limiares χ2
    ax.axhline(limiar_amarelo, color='#f1c40f', linestyle='--', linewidth=1.8,
               label=f'Limiar Alerta \u03c7²(90%) = {limiar_amarelo:.1f}')
    ax.axhline(limiar_vermelho, color='#e74c3c', linestyle='--', linewidth=1.8,
               label=f'Limiar Cisne Negro \u03c7²(99%) = {limiar_vermelho:.1f}')
    
    # Linha do split
    split_ts = pd.to_datetime(split_date)
    split_idx_list = [i for i, t in enumerate(trimestres) if pd.to_datetime(t) >= split_ts]
    if split_idx_list:
        ax.axvline(split_idx_list[0] - 0.5, color='black', linestyle=':', linewidth=2,
                   label='Início Out-of-Sample')
    
    ax.set_title("Distribuição Trimestral da Distância de Mahalanobis\n"
                 "(Limiares teóricos baseados em \u03c7² com 4 g.l.)")
    ax.set_xlabel("Trimestre")
    ax.set_ylabel("Distância de Mahalanobis")
    ax.legend(loc='upper left')
    ax.grid(True, linestyle='--', alpha=0.4)
    
    plt.tight_layout()
    plt.savefig(os.path.join(out_dir, "02_distribuicao_mahalanobis.png"), dpi=300)
    plt.close()
    logger.info("Violin chart Mahalanobis salvo.")

def plot_contagion(df: pd.DataFrame, out_dir: str, split_date: str):
    logger.info("Gerando Análise de Contágio (Percentual de Cisnes Negros)...")
    df_dist = df.groupby(['Data_Janela', 'Cluster_Risco_Mahalanobis']).size().unstack(fill_value=0)
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
    
    # Ordena categóricamente para garantir a ordem Verde → Amarelo → Vermelho
    df_ult['Cluster_Risco_Mahalanobis'] = pd.Categorical(
        df_ult['Cluster_Risco_Mahalanobis'],
        categories=['Verde', 'Amarelo', 'Vermelho'],
        ordered=True
    )
    
    plt.figure(figsize=(10, 6))
    sns.boxplot(
        data=df_ult,
        x='Cluster_Risco_Mahalanobis',
        y='Taxa_Ajustada_Prazo',
        hue='Cluster_Risco_Mahalanobis',
        palette=CLUSTER_PALETTE,
        order=['Verde', 'Amarelo', 'Vermelho'],
        legend=False
    )
    plt.title("Distribuição do Prêmio de Risco Ajustado por Cluster (Última Janela)")
    plt.xlabel("Regime de Crédito")
    plt.ylabel("Taxa Ajustada pelo Prazo")
    plt.yscale('log')
    plt.grid(True, linestyle='--', alpha=0.4)
    plt.tight_layout()
    plt.savefig(os.path.join(out_dir, "04_boxplot_separacao_clusters.png"), dpi=300)
    plt.close()

def plot_case_study(
    df: pd.DataFrame,
    tickers: List[str],
    title: str,
    filename: str,
    out_dir: str,
    split_date: str,
    eventos: Optional[List] = None
):
    """Plota o estudo de caso de um grupo de ativos com:
    - Sinal do motor (Verde / Amarelo / Vermelho)
    - Taxa Ajustada pelo Prazo (Yield)
    - Expected Shortfall (ES 99%)
    - Z-Score Longo (Stress Anual)
    
    Além disso, adiciona linhas verticais anotadas para cada evento de crédito
    registrado no dicionário EVENTOS_CREDITO (ex.: default, restruturação).
    """
    logger.info(f"Gerando Estudo de Caso Empírico ({title})...")
    
    case_df = df[df['Ticker'].isin(tickers)].copy()
    if case_df.empty:
        logger.warning(f"Estudo de Caso ({title}): Nenhum dado disponível.")
        return
        
    fig, axes = plt.subplots(5, 1, figsize=(14, 15), sharex=True)
    
    for ticker in tickers:
        df_ticker = case_df[case_df['Ticker'] == ticker].sort_values('Data_Janela')
        if df_ticker.empty: continue
            
        df_ticker['Alerta_Numerico'] = df_ticker['Cluster_Risco_Mahalanobis'].map(CLUSTER_MAP)
        
        axes[0].plot(df_ticker['Data_Janela'], df_ticker['Alerta_Numerico'], marker='o', linestyle='-', linewidth=2, label=ticker)
        axes[1].plot(df_ticker['Data_Janela'], df_ticker['Taxa_Ajustada_Prazo'], marker='.', linestyle='-', linewidth=1.5)
        axes[2].plot(df_ticker['Data_Janela'], df_ticker['ES_99'], marker='.', linestyle='-', linewidth=1.5)
        axes[3].plot(df_ticker['Data_Janela'], df_ticker['Taxa_ZScore'], marker='.', linestyle='-', linewidth=1.5)
        if 'Volatilidade_GARCH' in df_ticker.columns:
            axes[4].plot(df_ticker['Data_Janela'], df_ticker['Volatilidade_GARCH'], marker='.', linestyle='-', linewidth=1.5)
    
    # ----------------------------------------------------------------
    # Linha vertical: Início Out-of-Sample
    # ----------------------------------------------------------------
    split_dt = pd.to_datetime(split_date)
    for ax in axes:
        ax.axvline(split_dt, color='black', linestyle='--', linewidth=1.8, alpha=0.8)
    axes[0].axvline(split_dt, color='black', linestyle='--', linewidth=1.8,
                    label='Início Out-of-Sample')
    
    # ----------------------------------------------------------------
    # Linhas verticais: Eventos de crédito (default, RJ, etc.)
    # ----------------------------------------------------------------
    EVENT_COLORS = ['#8e44ad', '#d35400', '#16a085', '#2980b9', '#c0392b']
    if eventos:
        for i, (data_str, label) in enumerate(eventos):
            ev_dt = pd.to_datetime(data_str)
            ev_color = EVENT_COLORS[i % len(EVENT_COLORS)]
            for ax in axes:
                ax.axvline(ev_dt, color=ev_color, linestyle=':', linewidth=1.5, alpha=0.9)
            # Anota apenas no painel do sinal do motor (eixo 0) para não poluir
            ypos = axes[0].get_ylim()[1] if axes[0].get_ylim()[1] != 0 else 3.0
            axes[0].annotate(
                label,
                xy=(ev_dt, 3),
                xytext=(ev_dt, 3.05),
                fontsize=7,
                color=ev_color,
                ha='center',
                va='bottom',
                rotation=0,
                bbox=dict(boxstyle='round,pad=0.2', facecolor='white', edgecolor=ev_color, alpha=0.8),
            )
            # Coloca legenda com a data
            axes[0].axvline(ev_dt, color=ev_color, linestyle=':', linewidth=1.5,
                            label=f"{label.replace(chr(10), ' ')} ({data_str[:7]})")
    
    # ----------------------------------------------------------------
    # Formatação dos eixos
    # ----------------------------------------------------------------
    axes[0].set_yticks([1, 2, 3])
    axes[0].set_yticklabels(['Verde\n(Normal)', 'Amarelo\n(Alerta)', 'Vermelho\n(Cisne Negro)'])
    axes[0].set_ylabel("Sinal do Motor\nde Risco")
    axes[0].set_title(f"Estudo de Caso Empírico: {title}\nDecomposição dos Componentes (Mahalanobis)")
    axes[0].legend(loc='upper left', bbox_to_anchor=(1, 1), fontsize=8)
    axes[0].grid(True, alpha=0.3)
    
    axes[1].set_ylabel("Taxa Ajustada (Yield)")
    axes[1].grid(True, alpha=0.3)
    
    axes[2].set_ylabel("Expected Shortfall\n(ES 99%)")
    axes[2].grid(True, alpha=0.3)
    
    axes[3].set_ylabel("Z-Score Longo\n(Stress Anual)")
    axes[3].grid(True, alpha=0.3)
    
    axes[4].set_ylabel("Volatilidade\n(GARCH %)")
    axes[4].set_xlabel("Evolução no Tempo")
    axes[4].grid(True, alpha=0.3)
    axes[4].xaxis.set_major_formatter(mdates.DateFormatter('%Y-%m'))
    
    plt.tight_layout()
    plt.savefig(os.path.join(out_dir, filename), dpi=300, bbox_inches='tight')
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
    
    if 'Cluster_Risco_Mahalanobis' not in df.columns and 'Cluster_Risco_KMeans' in df.columns:
        df['Cluster_Risco_Mahalanobis'] = df['Cluster_Risco_KMeans']
        
    # Gráficos de visão geral
    plot_cross_section(df, out_dir)
    plot_mahalanobis_distribution(df, out_dir, split_date)  # Substitui Silhouette Score
    plot_contagion(df, out_dir, split_date)
    plot_boxplot(df, out_dir)
    
    # Estudos de Caso c/ marcadores de eventos
    plot_case_study(df, ['LAME29', 'LAMEA1'],
                    "Lojas Americanas", "05_estudo_caso_americanas.png", out_dir, split_date,
                    eventos=EVENTOS_CREDITO.get('Lojas Americanas'))
    
    plot_case_study(df, ['CBRDA7', 'CBRDA8'],
                    "GPA / Pão de Açúcar", "06_estudo_caso_pao_de_acucar.png", out_dir, split_date,
                    eventos=EVENTOS_CREDITO.get('GPA / Pão de Açúcar'))
    
    plot_case_study(df, ['LIGHA6', 'LIGHA9'],
                    "Light S.A.", "07_estudo_caso_light.png", out_dir, split_date,
                    eventos=EVENTOS_CREDITO.get('Light S.A.'))
    
    plot_case_study(df, ['VVAR11', 'VVAR26', 'VVAR15', 'VVAR25'],
                    "Via Varejo (Casas Bahia)", "08_estudo_caso_via_varejo.png", out_dir, split_date,
                    eventos=EVENTOS_CREDITO.get('Via Varejo (Casas Bahia)'))
    
    plot_case_study(df, ['RDORB7', 'RDORC7', 'RDORA5'],
                    "Rede D'Or", "09_estudo_caso_rede_dor.png", out_dir, split_date)
    
    plot_case_study(df, ['SULA19', 'SULA29'],
                    "Sul América", "10_estudo_caso_sulamerica.png", out_dir, split_date)
    
    # GOL Linhas Aéreas: apenas VRGL17 consta na base e com apenas 1 observação
    # (emissão de out/2021). Sem histórico suficiente para GARCH/Mahalanobis.
    # Mantém a chamada para exibir mensagem de aviso — não gera gráfico.
    plot_case_study(df, ['VRGL17'],
                    "GOL Linhas Aéreas", "11_estudo_caso_gol.png", out_dir, split_date,
                    eventos=EVENTOS_CREDITO.get('GOL Linhas Aéreas'))
    
    plot_case_study(df, ['APOL11', 'POLI11', 'POLI21', 'PLSH11'],
                    "Polishop", "12_estudo_caso_polishop.png", out_dir, split_date)

    logger.info(f"Visualizações e Testes de Defesa salvos em: {out_dir}")

if __name__ == "__main__":
    run_defense_visuals()
