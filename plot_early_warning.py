# -*- coding: utf-8 -*-
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import os
import matplotlib.patches as mpatches

df = pd.read_csv('dados/resultado_frequentist_engine.csv')
df['Data'] = pd.to_datetime(df['Data'])
lame = df[df['Ticker'] == 'LAMEA4'].sort_values('Data')

if lame.empty:
    print("Ativo LAMEA4 não encontrado.")
    exit()

# Criar a figura
fig, ax = plt.subplots(figsize=(12, 6))

# Plotar o Spread
ax.plot(lame['Data'], lame['Taxa_Ativo'], color='black', linewidth=1.5, label='Taxa LAMEA4')

# Colorir o fundo de acordo com o cluster HMM
# Supondo que Cluster_HMM: 0 (Verde), 1 (Amarelo), 2 (Vermelho)
# Precisamos mapear as cores baseado no score. Normalmente: maior cluster -> maior risco.
# Vamos verificar a probabilidade de crise para mapear:
colors = {0: 'lightgreen', 1: 'khaki', 2: 'salmon'}

# Função para preencher o fundo
start_idx = 0
current_cluster = lame['Cluster_HMM'].iloc[0]

for i in range(1, len(lame)):
    if lame['Cluster_HMM'].iloc[i] != current_cluster or i == len(lame) - 1:
        ax.axvspan(lame['Data'].iloc[start_idx], lame['Data'].iloc[i], 
                   color=colors.get(current_cluster, 'white'), alpha=0.4, lw=0)
        start_idx = i
        current_cluster = lame['Cluster_HMM'].iloc[i]

# Customizações
ax.set_title('Early Warning System (HMM) - LAMEA4 (Lojas Americanas)', fontsize=14, pad=15)
ax.set_ylabel('Taxa do Ativo (%)')
ax.set_xlabel('Data')
ax.grid(True, alpha=0.3)

# Legendas
verde_patch = mpatches.Patch(color='lightgreen', alpha=0.4, label='Regime 0: Normalidade')
amarelo_patch = mpatches.Patch(color='khaki', alpha=0.4, label='Regime 1: Alerta (Amarelo)')
vermelho_patch = mpatches.Patch(color='salmon', alpha=0.4, label='Regime 2: Crise (Vermelho)')
ax.legend(handles=[ax.lines[0], verde_patch, amarelo_patch, vermelho_patch], loc='upper left')

plt.tight_layout()
os.makedirs('academic/pos/imagens', exist_ok=True)
plt.savefig('academic/pos/imagens/early_warning_lamea4.png', dpi=300)
plt.close()
print("Gráfico Early Warning gerado.")
