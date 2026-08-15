"""
run_bootstrap.py — Item 7
Roda o backtest completo (incluindo bootstrap de significancia automatico)
"""
import sys, warnings
warnings.filterwarnings('ignore')
sys.path.insert(0, r'd:\projects\credit-tail-analytic\src')

import pandas as pd
from credit_tail_analytics.analysis.backtest_financeiro import BacktestFinanceiro

print('Carregando resultado_frequentist_engine.csv...')
df = pd.read_csv(r'd:\projects\credit-tail-analytic\dados\resultado_frequentist_engine.csv')
df['Data'] = pd.to_datetime(df['Data'])
print(f'Shape: {df.shape}')

print('Iniciando BacktestFinanceiro...')
bt = BacktestFinanceiro(df)
df_pnl = bt.simulate_portfolio(
    initial_capital=1_000_000.0,
    cure_days=180,
    transaction_cost=0.005,
    meses_payback=3,
)
print()
print('=== CURVAS PNL (ultimo dia) ===')
print(df_pnl.tail(1).to_string())

print()
print('Metricas salvas em dados/metricas_backtest.csv')
print('Bootstrap salvo em dados/bootstrap_significance.csv')
print('Grafico bootstrap em graficos/bootstrap_significance.png')
