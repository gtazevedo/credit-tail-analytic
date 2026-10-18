# -*- coding: utf-8 -*-
import os
import matplotlib.pyplot as plt
import pandas as pd
import seaborn as sns

df = pd.read_csv('dados/kupiec_test_results.csv')

def count_approved(p_values, alpha):
    return ((p_values >= alpha) | p_values.isna()).sum()

summary = df.groupby('Indexador_Grupo').agg(
    Total_Ativos=('Ticker', 'count'),
    Aprovados_POF_90=('P_Valor_POF', lambda x: count_approved(x, 0.10)),
    Aprovados_Joint_90=('P_Valor_Joint', lambda x: count_approved(x, 0.10)),
    Aprovados_POF_95=('P_Valor_POF', lambda x: count_approved(x, 0.05)),
    Aprovados_Joint_95=('P_Valor_Joint', lambda x: count_approved(x, 0.05)),
    Aprovados_POF_99=('P_Valor_POF', lambda x: count_approved(x, 0.01)),
    Aprovados_Joint_99=('P_Valor_Joint', lambda x: count_approved(x, 0.01)),
).reset_index()

for col in ['POF_90', 'Joint_90', 'POF_95', 'Joint_95', 'POF_99', 'Joint_99']:
    summary[f'Taxa_{col}'] = (summary[f'Aprovados_{col}'] / summary['Total_Ativos'] * 100).round(2)

plot_data = pd.melt(summary, id_vars=['Indexador_Grupo'], 
                    value_vars=['Taxa_Joint_90', 'Taxa_Joint_95', 'Taxa_Joint_99'],
                    var_name='Nivel_Confianca', value_name='Taxa_Nao_Rejeicao')

plot_data['Nivel_Confianca'] = plot_data['Nivel_Confianca'].map({
    'Taxa_Joint_90': '90% Confiança (α = 0,10)',
    'Taxa_Joint_95': '95% Confiança (α = 0,05)',
    'Taxa_Joint_99': '99% Confiança (α = 0,01)'
})

plot_data['Indexador_Grupo'] = plot_data['Indexador_Grupo'].replace({
    'CDI_Percentual': 'CDI Percentual',
    'CDI_Spread': 'CDI Spread',
    'IPCA': 'IPCA',
    'PRE': 'Pré-Fixado'
})

sns.set_theme(style="whitegrid")
fig, ax = plt.subplots(figsize=(10, 6))

barplot = sns.barplot(
    data=plot_data, 
    x='Indexador_Grupo', 
    y='Taxa_Nao_Rejeicao', 
    hue='Nivel_Confianca', 
    palette='viridis',
    ax=ax,
    edgecolor='black',
    linewidth=0.5
)

for container in ax.containers:
    labels = [f"{v:.1f}%".replace('.', ',') if v > 0 else '0,0%' for v in container.datavalues]
    ax.bar_label(container, labels=labels, padding=4, fontsize=9.5, fontweight='bold', color='#1e293b')

ax.set_title('Sensibilidade da Taxa de Não-Rejeição (Teste Conjunto de Christoffersen)', fontsize=13, fontweight='bold', pad=15)
ax.set_ylabel('Taxa de Não-Rejeição (%)', fontsize=11, labelpad=10)
ax.set_xlabel('Indexador da Debênture', fontsize=11, labelpad=10)
ax.set_ylim(0, 75)
ax.tick_params(labelsize=10)
ax.legend(title='Nível de Confiança do Teste', title_fontsize='10', fontsize=9.5, loc='upper right', frameon=True)

plt.tight_layout()
os.makedirs('academic/pos/imagens', exist_ok=True)
plt.savefig('academic/pos/imagens/kupiec_approval_rate.png', dpi=300)
plt.close()
