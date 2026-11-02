#pagebreak(weak: true)
= Análise e Exploração dos Dados <sec_analise_exploratoria>

A análise exploratória avaliou o comportamento empírico dos spreads e testou premissas estatísticas necessárias para fundamentar a modelagem econométrica, orientando o diagnóstico de estacionariedade e 
a seleção do subconjunto ideal de variáveis para os algoritmos de agrupamento.

== Propriedades Estatísticas e Diagnóstico de Cauda

As séries históricas de retornos de spread exibem desvios acentuados em relação à normalidade. No período _In-Sample_, as variações diárias apresentaram excesso de curtose de $2.683,30$, indicando eventos extremos e 
caudas pesadas que afastam a hipótese de distribuição gaussiana. Todavia, a variável padronizada `Taxa_ZScore`, resultante do filtro causal, reduziu o excesso de curtose para $1,18$. A @tab_descritiva apresenta as estatísticas 
descritivas das variáveis selecionadas para o espaço de estados no período _In-Sample_ (2018 a 2022).

#figure(
  [
    #set text(size: 8pt)
    #set table(inset: 2.2pt)
    #show raw: set text(size: 7.5pt)
    #table(
      stroke: 0.5pt,
      columns: (auto, 1fr, 1.2fr, 1.1fr, 1fr, 1fr, 1.3fr, 1.1fr),
      align: (left + horizon, center + horizon, center + horizon, center + horizon, center + horizon, center + horizon, center + horizon, center + horizon),
      [*Variável*], [*Média*], [*Desv.*\ *Padrão*], [*Mediana*], [*Q1 (25%)*], [*Q3 (75%)*], [*Assimetria*], [*Exc.*\ *Curtose*],
      [`Taxa_ZScore`], [0,114], [1,241], [0,000], [−0,743], [0,905], [0,45], [1,18],
      [`Volatilidade_EGARCH`], [14,329], [162,051], [0,299], [0,200], [0,466], [22,87], [750,45],
      [`Expected_Shortfall_99`], [0,406], [11,720], [0,966], [0,583], [1,000], [−52,42], [3.477,60]
    )
  ],
  caption: [Estatísticas Descritivas das Variáveis Selecionadas no Período In-Sample (2018 a 2022).]
) <tab_descritiva>

O afastamento entre médias e medianas nas variáveis de volatilidade e cauda quantifica a assimetria gerada por variações discretas e pouco frequentes nas cotações. A variável `Taxa_ZScore` apresenta excesso de curtose moderado ($1,18$), 
situado no intervalo $[-2, +2]$ indicado por #cite(<hair2010multivariate>, form: "prose") para premissas de normalidade assintótica, o que favorece a convergência na estimação das matrizes de covariância do HMM.

== Teste de Estacionariedade dos Spreads (ADF)

A modelagem de volatilidade condicional pressupõe séries estacionárias em covariância. Aplicou-se o Teste de Dickey-Fuller Aumentado (ADF) com intercepto e número de defasagens selecionado pelo critério AIC sobre as 529 
debêntures para testar a hipótese nula de raiz unitária ($H_0$). A @tab_adf apresenta os resultados por indexador ($alpha = 5\%$).

#figure(
  [
    #set text(size: 8pt)
    #set table(inset: 2.2pt)
    #table(
      stroke: 0.5pt,
      columns: (1.5fr, 1fr, 1.2fr, 1fr, 1.2fr),
      align: center + horizon,
      [*Indexador*], [*Total*], [*Estacionárias (Delta Spread)*], [*Taxa (%)*], [*Spread Bruto*],
      [IPCA], [286], [275], [96,2%], [Não-Estacionário],
      [CDI Spread], [239], [227], [95,0%], [Não-Estacionário],
      [PRÉ], [4], [4], [100,0%], [Não-Estacionário],
      [*Total*], [*529*], [*506*], [*95,7%*], [*Não-Estacionário*]
    )
  ],
  caption: [Resultados do Teste ADF ($alpha = 5\%$) por Indexador.]
) <tab_adf>

O spread bruto (`Taxa_Ativo`) é não-estacionário em 91% dos casos (integrado de ordem 1). Após a primeira diferença (`Delta Spread`), 95,7% das séries rejeitam $H_0$ ao nível de 5%, validando a premissa de estacionariedade 
para o EGARCH. Os 3,4% restantes concentram títulos com histórico reduzido (30 a 60 pregões) e iliquidez acentuada.

== Seleção de Variáveis por Contagem de Borda

A definição do subconjunto ideal de variáveis avaliou sete candidatas (`Taxa_ZScore`, `Volatilidade_EGARCH`, `VaR_99`, `Expected_Shortfall_99`, `Spread_Equivalente`, `Spread_Range_Intraday` e `Spread_Skew_Intraday`) via 
busca combinatória no período _In-Sample_ #cite(<saeys2008robust>). A partição foi avaliada por três métricas:

1. *Índice Silhouette* (_Silhouette Score_) #cite(<rousseeuw1987silhouettes>): mede a coesão intra-_cluster_ frente à separabilidade inter-_cluster_ em $[-1, 1]$, em que valores maiores denotam agrupamentos densos e bem delimitados;
2. *Índice Davies-Bouldin* #cite(<davies1979cluster>): avalia a razão entre a dispersão intra-_cluster_ e a distância euclidiana entre centroides, em que valores menores indicam particionamento ótimo;
3. *Índice Calinski-Harabasz* #cite(<calinski1974dendrite>): expressa a razão entre a variância inter-_cluster_ e intra-_cluster_ ponderada pelos graus de liberdade, em que magnitudes superiores refletem maior separação entre grupos.

Para mitigar divergências de ordenação entre métricas, utilizou-se o Método de Borda (_Borda Count_) #cite(<borda1781>)#cite(<ho1994decision>)#cite(<kittler1998combining>), combinando as posições ordinais de cada métrica sem pesos arbitrários.

#figure(
  image("../imagens/feature_selection_ranking.png", width: 62%),
  caption: [Ranking de Seleção de Variáveis pelo Método de Contagem de Borda.]
) <fig_feature_selection>

O subconjunto selecionado incorporou `Taxa_ZScore`, `Volatilidade_EGARCH` e `Expected_Shortfall_99`, figurando em segundo lugar no ranking geral da @fig_feature_selection. A opção pelo trio justifica-se pela 
maior sensibilidade a perdas extremas, ao agregar uma variável de cauda quando comparado com o primeiro lugar. A preferencia pelo Expected Shortfall em relação ao VaR se deu pela primeira ser uma métrica coerente 
de risco, superior ao VaR, conforme #cite(<artzner1999>, form: "prose") e #cite(<acerbi2002>, form: "prose").

== Implementação em Código-Fonte

A rotina de agregação por Contagem de Borda (`feature_selection.py`) quantifica o poder de separação:

```python
# Agregação determinística de Borda sobre métricas de partição (feature_selection.py)
r_sil, r_dbi = df['Silhouette_Score'].rank(ascending=False), df['Davies_Bouldin'].rank(ascending=True)
r_ch = pd.Series(np.log1p(df['CH_Score'].fillna(0))).rank(ascending=False)
df['Borda_Score'] = (n + 1 - r_sil) + (n + 1 - r_dbi) + (n + 1 - r_ch)
subconjunto_eleito = df.sort_values('Borda_Score', ascending=False).iloc[0]
```
