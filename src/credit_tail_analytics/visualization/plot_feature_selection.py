import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
from pathlib import Path

def plot_borda_ranking():
    # Estilo
    plt.style.use('seaborn-v0_8-whitegrid')
    
    df = pd.read_csv('dados/feature_selection_metrics.csv')
    
    # Pegar as Top 10
    top_df = df.head(10).copy()
    
    # Rótulos amigáveis
    labels = []
    for feats in top_df['Features']:
        f_list = [f.replace('_', ' ') for f in feats.split(', ')]
        # Se for muito longo, quebra a linha na metade
        text = " + ".join(f_list)
        if len(text) > 55:
            # Encontra o '+' mais próximo do meio
            mid = len(text) // 2
            idx = text.find('+', mid - 10)
            if idx != -1:
                text = text[:idx] + '\n+' + text[idx+1:]
        labels.append(text)
    
    top_df['Label'] = labels
    
    # Inverter para o gráfico de barras horizontais
    top_df = top_df.iloc[::-1]
    
    fig, ax = plt.subplots(figsize=(12, 7))
    
    colors = ['#A8C6FA'] * (len(top_df) - 1) + ['#174A7E']
    
    bars = ax.barh(top_df['Label'], top_df['Borda_Score'], color=colors, edgecolor='black', linewidth=0.8)
    
    # Textos dentro das barras
    for bar, (_, row) in zip(bars, top_df.iterrows()):
        width = bar.get_width()
        # Texto principal (Borda Score)
        ax.text(width - 2, bar.get_y() + bar.get_height()/2, 
                f"Borda: {row['Borda_Score']:.0f}", 
                ha='right', va='center', color='white', fontweight='bold', fontsize=11)
        
        # Texto secundário fora da barra (Métricas)
        metrics_text = f"Silh: {row['Silhouette_Score']:.3f} | DBI: {row['Davies_Bouldin']:.3f}"
        ax.text(width + 2, bar.get_y() + bar.get_height()/2, 
                metrics_text, 
                ha='left', va='center', color='black', fontsize=10)

    ax.set_xlabel('Borda Score', fontweight='bold', fontsize=12)
    ax.set_title('Top 10 Subconjuntos de Variáveis (Feature Selection)', fontweight='bold', fontsize=14, pad=15)
    
    # Ajustes de eixo
    ax.set_xlim(0, top_df['Borda_Score'].max() * 1.3) # Dar espaço para o texto das métricas
    ax.tick_params(axis='y', labelsize=10)
    
    ax.spines['top'].set_visible(False)
    ax.spines['right'].set_visible(False)
    
    plt.tight_layout()
    out_path = Path('graficos/feature_selection_ranking.png')
    plt.savefig(out_path, dpi=300, bbox_inches='tight')
    print(f"Gráfico salvo com sucesso em {out_path}")

if __name__ == '__main__':
    plot_borda_ranking()
