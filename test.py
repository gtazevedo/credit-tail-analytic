import pandas as pd
df = pd.read_csv('dados/resultado_frequentist_engine.csv')
cbrdb = df[df['Ticker'] == 'CBRDB8'].sort_values('Data').reset_index(drop=True)
idx = cbrdb[cbrdb['Data'] == '2026-02-24'].index[0]
sub = cbrdb.iloc[max(0, idx-1):idx+2]
print('\n--- CBRDB8 Choque em 2026-02-24 ---')
for _, row in sub.iterrows():
    print(f"{row['Data']}: Spread={row['Taxa_Ativo']:.2f}%, PU=R$ {row['PU']:.2f}")
