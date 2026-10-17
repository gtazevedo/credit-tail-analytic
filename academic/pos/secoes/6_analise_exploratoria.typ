= Análise e Exploração dos Dados <sec_analise_exploratoria>

A análise exploratória avaliou o comportamento empírico dos spreads e testou premissas estatísticas necessárias para fundamentar a modelagem econométrica. Essa investigação revelou a estrutura das séries, orientou o diagnóstico de estacionariedade e 
definiu o subconjunto ideal de variáveis para os algoritmos de agrupamento.

== Propriedades Estatísticas e Diagnóstico de Cauda

As séries históricas de retornos de spread exibem desvios severos em relação à normalidade. No período *In-Sample*, calculou-se o excesso de curtose sobre as variações dos spreads diários. O valor médio apurado alcançou $2.683,30$. Esse número 
atesta a presença de caudas ultra-pesadas e confirma a ocorrência de choques discretos de reprecificação. A curtose encontrada inviabiliza suposições distributivas gaussianas para as taxas brutas.

A aplicação do filtro econométrico de volatilidade normalizou esse comportamento. A variável padronizada `Taxa_ZScore`, derivada da variância condicional do modelo EGARCH com inovações t-Student, registrou excesso de curtose de apenas $1,17$. Em estatística 
multivariada, excessos de curtose contidos no intervalo entre $-2$ e $+2$ situam-se em níveis adequados para a calibração de modelos estocásticos sem introduzir vieses estruturais nas estimativas #cite(<hair2010multivariate>).

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

Os resultados confirmam que as séries de spread em nível são não-estacionárias em 91% dos casos. Trata-se de processos integrados de ordem um, $I(1)$. Após a primeira diferenciação (`Delta Spread`), 95,7% dos ativos rejeitam 
a hipótese nula de raiz unitária ao nível de 5%. Apenas 3,4% das séries não rejeitaram $H_0$, contingente formado por ativos que acumularam histórico curto e negociações esparsas. A diferenciação viabilizou a aplicação segura do motor de volatilidade.

== Seleção de Variáveis por Contagem de Borda

A etapa seguinte definiu quais variáveis agregam maior poder de separação para os modelos de agrupamento. Foram avaliadas sete variáveis candidatas: `Taxa_ZScore`, `Volatilidade_EGARCH`, `VaR_99`, `Expected_Shortfall_99`, 
`Spread_Equivalente`, `Spread_Range_Intraday` e `Spread_Skew_Intraday`.

A seleção executou um *Grid Search* combinatório sobre subconjuntos de variáveis no período *In-Sample*, seguindo os preceitos de robustez em seleção de atributos descritos por #cite(<saeys2008robust>). A qualidade 
do particionamento foi avaliada por três métricas consolidadas de validação de agrupamentos: o *Silhouette Score* de #cite(<rousseeuw1987silhouettes>), o *Índice Davies-Bouldin* de #cite(<davies1979cluster>) e o 
*Índice Calinski-Harabasz* de #cite(<calinski1974dendrite>). Como essas métricas atuam em escalas matemáticas heterogêneas, a classificação final agregou os rankings individuais pelo método determinístico de Contagem de 
Borda (*Borda Count*), estabelecido originalmente por #cite(<borda1781>).

A @fig_feature_selection exibe os dez subconjuntos mais bem classificados no torneio.

#figure(
  image("../imagens/feature_selection_ranking.png", width: 90%),
  caption: [Top 10 Subconjuntos de Variáveis classificados pelo método de Borda Count.]
) <fig_feature_selection>

O subconjunto formado por `Taxa_ZScore` e `Volatilidade_EGARCH` obteve a pontuação máxima de Borda. Mas a modelagem final adotou o trio composto por `Taxa_ZScore`, `Volatilidade_EGARCH` e `Expected_Shortfall_99`, segundo 
colocado no ranking geral. Essa decisão incorporou sensibilidade direta a perdas extremas de cauda. 

A inclusão do Expected Shortfall apoia-se nos fundamentos teóricos de medidas coerentes de risco postulados por #cite(<artzner1999>). Enquanto o VaR convencional responde apenas qual é o piso de perda tolerado 
para um quantil fixado (violando o axioma da subaditividade e ignorando o comportamento além do limiar), o Expected Shortfall, conforme demonstrado por #cite(<acerbi2002>), atende aos axiomas de coerência e quantifica a 
perda média esperada condicionada à violação do VaR.

A @fig_feature_radar compara o desempenho das quatro principais combinações de atributos em três eixos normalizados (Coesão, Dispersão e Separação).

#figure(
  image("../imagens/feature_selection_radar.png", width: 90%),
  caption: [Comparação Multidimensional das métricas de particionamento (Min-Max Scaled).]
) <fig_feature_radar>

O trio eleito equilibra coesão interna e separabilidade entre os grupos. O Expected Shortfall supera o VaR em todas as métricas avaliadas, fornecendo a expectativa de perda condicional no pior 1% dos casos.

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
