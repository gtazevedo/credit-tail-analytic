= Processamento/Tratamento de Dados <sec_processamento>

O tratamento dos dados de negociação mitiga distorções de baixa liquidez e multiplicidade de indexadores contratuais. A base foi dividida em dois intervalos 
complementares, o primeiro, _In-Sample_ (02/01/2018 a 30/12/2022), utilizado para calibração econométrica e inferência de regimes, e o segundo _Out-of-Sample_ (02/01/2023 a 10/07/2026), para validação preditiva e simulação tática.

== Divisão Temporal e Filtro de Iliquidez

No sistema REUNE/ANBIMA, o volume diário é estratificado em faixas ordinais (Faixa 3 para volumes até R\$ 1 milhão). Para excluir ativos com negociação esparsa no treino, foram removidos títulos 
sem negócios em 95% ou mais dos pregões _In-Sample_, prevenindo distorções na persistência da variância do EGARCH. O filtro incidiu apenas no treino, exceto pela debênture RDVT11, excluída integralmente por variações extremas decorrentes de recuperação judicial.

== Harmonização de Taxas e Engenharia de Atributos <subcap_processamento>

A base abrange debêntures atreladas a percentual do CDI, DI+ e IPCA+. Em títulos a percentual do CDI, a taxa foi convertida em spread equivalente anual sobre a taxa livre de risco ($S_t$). Em contratos IPCA+ e DI+, a taxa contratual corresponde diretamente ao prêmio bruto ($S_t = "Taxa"_t$). A partir do spread harmonizado, calcularam-se a primeira diferença ($Delta S_t = S_t - S_(t-1)$), a taxa ajustada ao prazo ($S_t / ln(max("DU", 2))$), a amplitude diária ($S_"range" = "Taxa"_"max" - "Taxa"_"min"$), a assimetria intraday ($S_"skew"$) e o Z-Score causal móvel de 60 dias, detalhados na Subseção @subcap_implementacao_preprocessor.

== Tratamento de Discrepâncias e Normalização

Aplicou-se winsorização bilateral nos percentis 1% e 99%, calibrada no _In-Sample_ e replicada no _Out-of-Sample_ para evitar viés prospectivo (_look-ahead bias_). O escalonamento 
adotou o `RobustScaler` #cite(<rousseeuw2011robust>), que subtrai a mediana e divide os valores pelo intervalo interquartil (IQR), com piso de 10% do IQR mediano para prevenir indeterminações numéricas.

== Implementação em Código-Fonte <subcap_implementacao_preprocessor>

As rotinas de tratamento e transformação concentram-se em `preprocessor.py`:

```python
# Harmonização de spread equivalente, prazo e dispersão (preprocessor.py)
spread_pct = ((((1 + cdi / 100.0) ** (1 / 252) - 1) * (taxa / 100.0) + 1) ** 252 - 1) * 100.0 - cdi
df['Spread_Equivalente'] = np.where(is_pct, spread_pct, np.where(is_puro, taxa, taxa - cdi))
df['Taxa_Ajustada_Prazo'] = df['Spread_Equivalente'] / np.log(np.maximum(df['DU_Vencimento'], 2))
df['Taxa_ZScore'] = ((df['Spread_Equivalente'] - roll.mean().values) / roll.std().replace(0, np.nan).values).fillna(0.0)
```
