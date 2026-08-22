import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
from math import pi
from pathlib import Path

def plot_radar_chart():
    df = pd.read_csv('dados/feature_selection_metrics.csv')
    
    # Pegar os top 3, 4 ou 5 para não poluir o gráfico
    top_n = 4
    df_top = df.head(top_n).copy()
    
    # Criar rótulos amigáveis
    labels = []
    for feats in df_top['Features']:
        f_list = [f.replace('_', ' ') for f in feats.split(', ')]
        text = " + ".join(f_list)
        if len(text) > 40:
            text = text.replace(' + Expected Shortfall 99', '\n+ ES 99')
            text = text.replace(' + Spread Skew Intraday', '\n+ Spread Skew')
            text = text.replace(' + Spread Range Intraday', '\n+ Spread Range')
        labels.append(text)
    df_top['Label'] = labels
    
    # Para plotar no radar, precisamos que as métricas estejam na mesma escala [0, 1].
    # O Silhouette e CH_Score_Log são "quanto maior, melhor".
    # O Davies-Bouldin é "quanto menor, melhor".
    
    # Min-Max global da tabela inteira (não só dos top N)
    sil_min, sil_max = df['Silhouette_Score'].min(), df['Silhouette_Score'].max()
    db_min,  db_max  = df['Davies_Bouldin'].min(), df['Davies_Bouldin'].max()
    ch_min,  ch_max  = df['CH_Score_Log'].min(), df['CH_Score_Log'].max()
    
    # Função de normalização [0.1, 1.0] (0.1 para não sumir no centro do gráfico)
    def norm_high(x, xmin, xmax): return 0.1 + 0.9 * (x - xmin) / (xmax - xmin + 1e-9)
    def norm_low(x, xmin, xmax):  return 0.1 + 0.9 * (xmax - x) / (xmax - xmin + 1e-9)
    
    df_top['Sil_Norm'] = df_top['Silhouette_Score'].apply(lambda x: norm_high(x, sil_min, sil_max))
    df_top['DB_Norm']  = df_top['Davies_Bouldin'].apply(lambda x: norm_low(x, db_min, db_max))
    df_top['CH_Norm']  = df_top['CH_Score_Log'].apply(lambda x: norm_high(x, ch_min, ch_max))
    
    categories = ['Silhouette Score\n(Coesão - Maior é Melhor)', 
                  'Davies-Bouldin Index\n(Dispersão - Menor é Melhor)', 
                  'Calinski-Harabasz\n(Separação - Maior é Melhor)']
    N = len(categories)
    
    # Ângulos para o radar
    angles = [n / float(N) * 2 * pi for n in range(N)]
    angles += angles[:1]
    
    fig, ax = plt.subplots(figsize=(8, 8), subplot_kw=dict(polar=True))
    
    # Configurar o grid (primeira categoria no topo)
    ax.set_theta_offset(pi / 2)
    ax.set_theta_direction(-1)
    
    # Eixo X
    plt.xticks(angles[:-1], categories, color='black', size=11, fontweight='bold')
    
    # Eixo Y (ocultar os números internos para ficar mais limpo)
    ax.set_rlabel_position(0)
    plt.yticks([0.25, 0.5, 0.75, 1.0], [], color="grey", size=7)
    plt.ylim(0, 1.1)
    
    # Cores de destaque
    colors = ['#174A7E', '#FF7F0E', '#2CA02C', '#D62728']
    
    for i, row in list(df_top.iterrows())[::-1]:
        values = [row['Sil_Norm'], row['DB_Norm'], row['CH_Norm']]
        values += values[:1]
        
        # Padrões de tracejado: quanto mais pro topo (i=0), maiores os espaços
        # (tamanho_do_traço, tamanho_do_espaço)
        dash_patterns = {
            3: (2, 1),   # Fundo (Vermelho): quase sólido
            2: (4, 2),   # Verde: tracejado curto
            1: (6, 4),   # Laranja: tracejado médio
            0: (8, 6)    # Topo (Azul): tracejado longo com muito espaço
        }
        
        # Desenhar linha (mesma espessura para todas)
        ax.plot(angles, values, linewidth=2.5, dashes=dash_patterns[i], label=row['Label'], color=colors[i], zorder=10-i)
        
        # Preencher área
        if i == 0:
            ax.fill(angles, values, color=colors[i], alpha=0.35, zorder=10-i)
        else:
            ax.fill(angles, values, color=colors[i], alpha=0.05, zorder=10-i)
            
    # Inverter a ordem das legendas para o vencedor (azul) aparecer primeiro
    handles, labels_leg = ax.get_legend_handles_labels()
    ax.legend(handles[::-1], labels_leg[::-1], loc='upper center', bbox_to_anchor=(0.5, -0.15), 
               title="Subconjuntos (Top 4)", title_fontproperties={'weight':'bold'}, fontsize=9, ncol=2)
               
    plt.title("Comparação Multidimensional - Feature Selection", size=15, fontweight='bold', y=1.15)
    
    plt.tight_layout()
    out_path = Path('graficos/feature_selection_radar.png')
    out_path.parent.mkdir(exist_ok=True)
    plt.savefig(out_path, dpi=300, bbox_inches='tight')
    print(f"Gráfico radar salvo em {out_path}")

if __name__ == '__main__':
    plot_radar_chart()
