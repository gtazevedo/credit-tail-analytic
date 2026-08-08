# -*- coding: utf-8 -*-
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import os

df = pd.read_csv('dados/kupiec_test_results.csv')

summary = df.groupby('Indexador_Grupo').agg(
    Total_Ativos=('Ticker', 'count'),
    Aprovados_POF=('POF_Valido', lambda x: (x == 'SIM').sum()),
    Aprovados_Modelo=('Modelo_Valido', lambda x: (x == 'SIM').sum())
).reset_index()

summary['Taxa_Aprovacao_POF'] = (summary['Aprovados_POF'] / summary['Total_Ativos'] * 100).round(2)
summary['Taxa_Aprovacao_Total'] = (summary['Aprovados_Modelo'] / summary['Total_Ativos'] * 100).round(2)

print(summary.to_markdown(index=False))

os.makedirs('academic/pos/imagens', exist_ok=True)
plt.figure(figsize=(8, 5))
sns.barplot(data=summary, x='Indexador_Grupo', y='Taxa_Aprovacao_POF', palette='viridis')
plt.title('Taxa de Aprovacao no Teste de Kupiec (POF)')
plt.ylabel('Aprovacao (%)')
plt.xlabel('Indexador')
plt.ylim(0, 100)
for index, row in summary.iterrows():
    plt.text(index, row.Taxa_Aprovacao_POF + 1, f'{row.Taxa_Aprovacao_POF}%', color='black', ha='center')
plt.tight_layout()
plt.savefig('academic/pos/imagens/kupiec_approval_rate.png', dpi=300)
plt.close()
