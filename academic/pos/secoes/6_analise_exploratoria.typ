= Análise e Exploração dos Dados <sec_analise_exploratoria>

A análise exploratória avaliou o comportamento empírico dos spreads e testou premissas estatísticas necessárias para fundamentar a modelagem econométrica. Essa investigação revelou a estrutura das séries, orientou o diagnóstico de estacionariedade e 
definiu o subconjunto ideal de variáveis para os algoritmos de agrupamento.

== Propriedades Estatísticas e Diagnóstico de Cauda

As séries históricas de retornos de spread exibem desvios acentuados em relação à normalidade. No período _In-Sample_, calculou-se o excesso de curtose sobre as variações dos spreads diários. Constatou-se que os retornos apresentaram excesso de curtose de $2.683,30$, indicando eventos extremos e caudas pesadas que inviabilizariam o pressuposto de normalidade gaussiana. Todavia, a variável padronizada `Taxa_ZScore`, resultante do filtro estocástico do EGARCH-t, reduziu o excesso de curtose para $1,18$.

A @tab_descritiva consolida as principais estatísticas descritivas das variáveis que compõem o espaço de estados para o agrupamento de regimes durante o período de treinamento (_In-Sample_, 2018 a 2022).

#figure(
  [
    #set text(size: 8.5pt)
    #show raw: set text(size: 8pt)
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

A discrepância entre as médias e medianas nas variáveis brutas de volatilidade e cauda evidencia a acentuada assimetria provocada por choques raros de reprecificação. Em contrapartida, a variável padronizada `Taxa_ZScore` apresenta excesso de curtose moderado ($1,18$), situado no intervalo $[-2, +2]$ preconizado por #cite(<hair2010multivariate>, form: "prose") para premissas de normalidade assintótica. Consequentemente, o espaço latente do HMM passa a operar em um domínio no qual o impacto de eventos extremos é atenuado, assegurando estabilidade numérica na convergência das matrizes gaussianas.

== Teste de Estacionariedade dos Spreads (ADF)

A modelagem de volatilidade condicional pressupõe que as séries temporais analisadas sejam estacionárias em covariância. Para verificar essa hipótese nos 529 ativos selecionados, aplicou-se o Teste de Dickey-Fuller Aumentado (ADF). O teste avalia 
formalmente as seguintes hipóteses:

- Hipótese Nula ($H_0$): A série temporal possui raiz unitária (não-estacionária);
- Hipótese Alternativa ($H_1$): A série temporal é estacionária em covariância.

A especificação adotou modelo com termo constante e defasagens selecionadas automaticamente pelo Critério de Informação de Akaike (AIC). A @tab_adf apresenta os resultados agregados por indexador ao nível de significância de 5%.

#figure(
  table(
    stroke: 0.5pt,
    columns: (1.5fr, 1fr, 1.2fr, 1fr, 1.2fr),
    align: center + horizon,
    [*Indexador*], [*Total*], [*Estacionárias (Delta Spread)*], [*Taxa (%)*], [*Spread Bruto*],
    [IPCA], [286], [275], [96,2%], [Não-Estacionário],
    [CDI Spread], [239], [227], [95,0%], [Não-Estacionário],
    [PRÉ], [4], [4], [100,0%], [Não-Estacionário],
    [*Total*], [*529*], [*506*], [*95,7%*], [*Não-Estacionário*]
  ),
  caption: [Resultados do Teste ADF ($alpha = 5\%$) por Indexador.]
) <tab_adf>

Os resultados, reportados na @tab_adf, demonstram que a série de _spread_ bruto (`Taxa_Ativo`) é não-estacionária em 91% dos casos, como esperado (em nível de _spread_, as séries são integradas de ordem 1) e após a primeira 
diferença (`Delta Spread`), 95,7% das séries rejeitam $H_0$ ao nível de 5%, validando o pressuposto de estacionariedade necessário para o EGARCH. Os ativos que compõem os 3,4% restantes que não rejeitam $H_0$ são, em sua maioria, 
títulos com histórico reduzido (entre 30 e 60 observações) e perfil de iliquidez estrutural, nos quais longas sequências de retornos nulos prejudicam a convergência assintótica do teste e reduzem a precisão do motor EGARCH. 

== Seleção de Variáveis por Contagem de Borda

A etapa seguinte definiu quais variáveis agregam maior poder de separação para os modelos de agrupamento. Foram avaliadas sete variáveis candidatas: `Taxa_ZScore`, `Volatilidade_EGARCH`, `VaR_99`, `Expected_Shortfall_99`, 
`Spread_Equivalente`, `Spread_Range_Intraday` e `Spread_Skew_Intraday`.

A seleção executou um _Grid Search_ combinatório sobre subconjuntos de variáveis no período _In-Sample_, seguindo os preceitos de robustez em seleção de atributos descritos por #cite(<saeys2008robust>, form: "prose"). A qualidade 
do particionamento foi avaliada por três métricas consolidadas de validação de agrupamentos: 

1. *Índice Silhouette* (_Silhouette Score_) #cite(<rousseeuw1987silhouettes>): Mede a coesão intra-_cluster_ frente à separabilidade inter-_cluster_, variando no intervalo $[-1, 1]$. Nesta métrica, valores maiores indicam melhor adequação, ou seja, valores próximos a 1 sugerem _clusters_ perfeitamente densos e bem separados, enquanto valores próximos a 0 ou negativos indicam expressiva sobreposição;
2. *Índice Davies-Bouldin* #cite(<davies1979cluster>): Avalia a razão média da dispersão interna do _cluster_ pela distância euclidiana entre os centroides, penalizando sobreposições. Diferentemente do _Silhouette_, nesta métrica valores menores indicam melhor adequação, pois um índice menor (com limite inferior tendendo a zero) significa que os _clusters_ são compactos internamente e distantes uns dos outros;
3. *Índice Calinski-Harabasz* #cite(<calinski1974dendrite>): Mensura a razão entre a variância inter-_cluster_ e a variância intra-_cluster_, ponderada pelos graus de liberdade do sistema. Para este índice, valores maiores indicam melhor adequação, denotando que a distância entre os centros dos _clusters_ é expressivamente maior que a dispersão dos pontos dentro de cada regime.

Diante de divergências de ordenação entre métricas de partição utilizadas, a definição do subconjunto ideal recorreu à heurística do consenso multivariado. Optou-se pela utilização do Método de Borda (_Borda Count_), tradicionalmente 
um sistema de votação, introduzido por #cite(<borda1781>, form: "prose"), e amplamente utilizado na literatura moderna de Aprendizado de Máquina para construção de classificadores de consenso após sua adaptação computacional
(#cite(<ho1994decision>, form: "prose"); #cite(<kittler1998combining>, form: "prose")). Neste trabalho, as variáveis são pontuadas pela posição ordinal que alcançaram em cada métrica isolada. Os resultados são então combinados pelo Método 
de Borda, permitindo mitigar o viés individual de cada métrica e convergir para o subconjunto dimensionalmente mais robusto.

A @fig_feature_selection exibe os dez subconjuntos mais bem classificados na seleção combinatória. Como resultado da otimização matemática (_Borda Score_), o subconjunto `Taxa_ZScore` e `Volatilidade_EGARCH` obteve a pontuação máxima no particionamento empírico. No entanto, 
o subconjunto eleito para a modelagem final incorporou também a estimativa de risco de cauda (`Expected_Shortfall_99`), formando o trio `Taxa_ZScore`, `Volatilidade_EGARCH` e `Expected_Shortfall_99`, que figurou em segundo lugar no ranking geral. A 
opção metodológica por esse trio de variáveis justifica-se pela necessidade de o modelo possuir sensibilidade a perdas financeiras extremas, agregando significado econômico aos _clusters_ formados.

#figure(
  image("../imagens/feature_selection_ranking.png", width: 90%),
  caption: [Top 10 Subconjuntos de Variáveis classificados pelo método de Borda Count.]
) <fig_feature_selection>


Para complementar a análise sob uma perspectiva geométrica multivariada, a @fig_feature_radar ilustra o desempenho das quatro principais combinações normalizado nos três eixos de avaliação (Coesão, Dispersão e Separação). O gráfico demonstra como a combinação escolhida consegue maximizar satisfatoriamente o _Silhouette Score_ e o _Calinski-Harabasz_, mantendo a competitividade no índice de _Davies-Bouldin_.


#figure(
  image("../imagens/feature_selection_radar.png", width: 90%),
  caption: [Comparação Multidimensional das métricas de particionamento (Min-Max Scaled).]
) <fig_feature_radar>


Na @fig_feature_radar, o conjunto dado pelas variáveis `Taxa_ZScore`, `Volatilidade_EGARCH` e `Expected_Shortfall_99` (segundo lugar) e o conjunto formado por `Taxa_ZScore`, `Volatilidade_EGARCH` e `VaR_99` (terceiro lugar)
apresentam geometria visualmente próxima. Contudo, a consulta à @fig_feature_selection evidencia a superioridade quantitativa do primeiro grupo. A única diferença reside na substituição do VaR pelo Expected Shortfall, 
que supera o VaR em todas as métricas de validação. Conforme demonstrado por #cite(<artzner1999>, form: "prose") e #cite(<acerbi2002>, form: "prose"), o Expected Shortfall atende aos axiomas de medida coerente de risco, sanando a violação da 
subaditividade do VaR tradicional. Enquanto o VaR delimita apenas a perda máxima tolerada a 99% de confiança (ignorando o tamanho do prejuízo além desse piso), o Expected Shortfall mensura a perda média condicionada 
à violação desse limite, reforçando sua eleição para o modelo final.

== Implementação em Código-Fonte

A rotina de seleção combinatória e agregação por Contagem de Borda, extraída de `src/credit_tail_analytics/models/credit_risk/feature_selection.py`, quantifica o poder de separação das variáveis sem recorrer a pesos heurísticos arbitrários:

```python
import numpy as np
import pandas as pd
from sklearn.preprocessing import RobustScaler
from sklearn.cluster import KMeans
from sklearn.metrics import silhouette_score, davies_bouldin_score, calinski_harabasz_score

class FeatureSelector:
    """Seleção combinatória de atributos via Contagem de Borda multi-métrica."""

    @staticmethod
    def avaliar_combinacao(subset: list, df_is: pd.DataFrame, grupo_col: str = 'Indexador_Grupo') -> dict:
        """Calcula Silhouette, Davies-Bouldin e Calinski-Harabasz intra-indexador."""
        df_sub = df_is.dropna(subset=subset)
        if df_sub.empty:
            return None

        sil_list, db_list, ch_list = [], [], []
        for grupo in df_sub[grupo_col].unique():
            grp = df_sub[df_sub[grupo_col] == grupo]
            X = grp[subset].values
            if len(X) < 6:
                continue

            X_sc = RobustScaler().fit_transform(X)
            km = KMeans(n_clusters=3, random_state=42, n_init=10)
            labels = km.fit_predict(X_sc)

            if len(np.unique(labels)) < 2:
                continue

            samp = min(len(X_sc), 5000) if len(X_sc) > 5000 else None
            sil_list.append(silhouette_score(X_sc, labels, sample_size=samp, random_state=42))
            db_list.append(davies_bouldin_score(X_sc, labels))
            ch_list.append(calinski_harabasz_score(X_sc, labels))

        if not sil_list:
            return None

        return {
            'Features': ', '.join(subset),
            'Silhouette_Score': float(np.mean(sil_list)),
            'Davies_Bouldin': float(np.mean(db_list)),
            'CH_Score': float(np.mean(ch_list)),
        }

    @staticmethod
    def agregar_borda_count(results_df: pd.DataFrame) -> pd.DataFrame:
        """Aplica log1p no Calinski-Harabasz e computa a pontuação determinística de Borda."""
        n = len(results_df)
        sil_rank = results_df['Silhouette_Score'].rank(ascending=False, method='average')
        dbi_rank = results_df['Davies_Bouldin'].rank(ascending=True, method='average')
        
        # log1p comprime a cauda pesada do índice CH, preservando a ordenação ordinal
        ch_log = np.log1p(results_df['CH_Score'].fillna(0))
        ch_rank = pd.Series(ch_log).rank(ascending=False, method='average')

        # Agregação de Borda (Borda, 1781)
        results_df['CH_Score_Log'] = ch_log.values
        results_df['Borda_Score'] = (n + 1 - sil_rank) + (n + 1 - dbi_rank) + (n + 1 - ch_rank)
        return results_df.sort_values('Borda_Score', ascending=False).reset_index(drop=True)
```
