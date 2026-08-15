"""
run_cluster_validation.py — Item 5
Gera Elbow Method + Silhouette para justificar k=3
"""
import sys, warnings
warnings.filterwarnings('ignore')
sys.path.insert(0, r'd:\projects\credit-tail-analytic\src')

import pandas as pd
from sklearn.preprocessing import RobustScaler
from credit_tail_analytics.analysis.clustering_validation import plot_elbow_silhouette

df = pd.read_csv(r'd:\projects\credit-tail-analytic\dados\resultado_frequentist_engine.csv')
df['Data'] = pd.to_datetime(df['Data'])
features = ['Taxa_ZScore', 'Volatilidade_EGARCH', 'Expected_Shortfall_99']

all_results = {}
for idx in ['IPCA', 'CDI_Spread', 'CDI_Percentual']:
    df_idx = df[df['Indexador_Grupo'] == idx][features].dropna()
    print(f'[{idx}] amostras: {len(df_idx)}')
    if len(df_idx) < 100:
        continue
    scaler = RobustScaler()
    X = scaler.fit_transform(df_idx.values)
    df_val = plot_elbow_silhouette(
        X,
        k_range=range(2, 8),
        k_chosen=3,
        random_state=42,
        output_dir=r'd:\projects\credit-tail-analytic\graficos',
        filename_prefix=f'cluster_val_{idx.lower().replace(" ", "_")}',
        title_suffix=idx,
    )
    all_results[idx] = df_val
    print(df_val.to_string())
    print()

print('Clustering validation concluido.')
print()
print('=== RESUMO PARA O TCC ===')
for idx, df_v in all_results.items():
    best_sil_k = df_v.loc[df_v['Silhouette_Score'].idxmax(), 'k']
    sil_k3 = df_v.loc[df_v['k'] == 3, 'Silhouette_Score'].values[0]
    sil_best = df_v['Silhouette_Score'].max()
    print(f'{idx}: k=3 -> Silhouette={sil_k3:.4f} | melhor k={best_sil_k} (Score={sil_best:.4f})')
