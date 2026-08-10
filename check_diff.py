import pandas as pd
pd.set_option('display.max_columns', None)
df = pd.read_csv('dados/kupiec_test_results.csv')
diff = df[(df['POF_Valido'] == 'NÃO') & (df['Modelo_Valido'] == 'SIM')]
print(diff.head())
