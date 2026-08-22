# -*- coding: utf-8 -*-
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import os

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
    'Taxa_Joint_90': '90% Conf (α=0.10)',
    'Taxa_Joint_95': '95% Conf (α=0.05)',
    'Taxa_Joint_99': '99% Conf (α=0.01)'
})

os.makedirs('academic/pos/imagens', exist_ok=True)
plt.figure(figsize=(10, 6))
sns.barplot(data=plot_data, x='Indexador_Grupo', y='Taxa_Nao_Rejeicao', hue='Nivel_Confianca', palette='viridis')
plt.title('Sensibilidade da Não-Rejeição da $ (Teste Conjunto)')
plt.ylabel('Taxa de Não-Rejeição (%)')
plt.xlabel('Indexador')
plt.ylim(0, 100)
plt.legend(title='Confiança do Teste')
plt.tight_layout()
plt.savefig('academic/pos/imagens/kupiec_approval_rate.png', dpi=300)
plt.close()
