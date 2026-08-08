= Resultados e Discussões

Este capítulo apresenta os resultados empíricos obtidos a partir da aplicação da arquitetura de risco desenvolvida e apresentada em @cap_metodologia 
aos dados do mercado secundário de crédito corporativo brasileiro. 
A análise é construída de forma sequencial, iniciando pela validação estatística 
rigorosa dos motores de volatilidade e culminando no impacto financeiro real gerado pelas estratégias táticas de alocação.

== Rejeição da Hipótese Nula (Validação de Kupiec)
A eficácia de qualquer sistema de alerta preventivo (*Early Warning*) no mercado de crédito está fundamentalmente atrelada à sua capacidade 
matemática de modelar as caudas pesadas da distribuição de retornos. Para atestar a acurácia do motor 
EGARCH-t na estimação do *Value at Risk* (VaR), aplicou-se o Teste de Proporção de Falhas de Kupiec (POF).

Os resultados agregados do backtest estatístico, agrupados por classe de indexador, evidenciam a proporção de ativos em que a Hipótese Nula ($H_0$) do teste não foi rejeitada (ou seja, a taxa de falhas observada não diferiu estatisticamente da margem de 1% esperada pelo modelo).

#figure(
  table(
    columns: (auto, auto, auto, auto, auto),
    align: center,
    [*Indexador*], [*Total de Ativos*], [*Aprovados (POF)*], [*Aprovados (Conjunto)*], [*Taxa de Aprovação POF*],
    [CDI Percentual], [40], [21], [23], [52,50%],
    [CDI Spread], [257], [63], [80], [24,51%],
    [IPCA], [365], [133], [157], [36,44%],
    [PRÉ-Fixado], [1], [0], [0], [0,00%]
  ),
  caption: [Resumo dos Resultados do Teste de Kupiec POF por Indexador]
) <tab_kupiec>

Para efeitos visuais e comparativos da eficácia do modelo, a figura abaixo exibe a taxa de aprovação relativa.

#figure(
  image("../imagens/kupiec_approval_rate.png", width: 80%),
  caption: [Taxa de Aprovação no Teste de Proporção de Falhas (POF)]
) <fig_kupiec>

== O Desempenho do HMM vs K-Means na Classificação
Estabelecida a validade estatística das métricas de risco de cauda, a análise avalia a agilidade e a coerência dos algoritmos não-supervisionados na tarefa de transpor essas métricas contínuas para Regimes Latentes de risco (Verde, Amarelo e Vermelho). O contraste entre o particionamento geométrico (K-Means) e a inferência temporal (HMM) revela nuances cruciais sobre a capacidade preditiva de cada modelo diante de choques sistêmicos.

== Simulação de Portfólio (Backtest Financeiro)
O teste definitivo da utilidade econômica da modelagem preditiva materializa-se na simulação financeira *Out-of-Sample*. O objetivo deste *backtest* não se limita a aferir o alfa direcional do modelo contra uma estratégia passiva (*Buy-and-Hold*), mas avaliar como as liquidações preventivas (Sinal Amarelo) e retardadas (Sinal Vermelho) impactam a relação de risco-retorno (medida pelo *Sharpe Ratio*) do portfólio.

== O Impacto Prático dos Custos e a Sobrevivência no Mundo Real
A mais acurada predição de crise perde seu valor econômico caso os custos de atrito (*frictions*) para executá-la superem a perda evitada no evento de cauda. Devido às restrições de liquidez estruturais do mercado secundário de debêntures brasileiro, provou-se indispensável analisar o comportamento da estratégia frente à penalidade financeira do excesso de giro (*whipsaw*).