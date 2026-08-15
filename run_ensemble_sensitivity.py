import sys, warnings
warnings.filterwarnings('ignore')
sys.path.insert(0, r'd:\projects\credit-tail-analytic\src')

import pandas as pd
from credit_tail_analytics.analysis.ensemble_sensitivity import EnsembleSensitivity

print('Carregando resultado_frequentist_engine.csv...')
df = pd.read_csv(r'd:\projects\credit-tail-analytic\dados\resultado_frequentist_engine.csv')
df['Data'] = pd.to_datetime(df['Data'])
# Modificação Option 2: Ensemble otimizado APENAS no In-Sample
df = df[df['Data'] < '2023-01-01']
print(f'Shape In-Sample: {df.shape}')

print('Iniciando EnsembleSensitivity...')
es = EnsembleSensitivity(df, step=0.10)
# 'Amarelo' is equivalent to 'Vende Amarelo' in BacktestFinanceiro
df_grade = es.run(stop_mode='Amarelo')
