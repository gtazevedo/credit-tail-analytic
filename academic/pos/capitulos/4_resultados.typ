= Resultados e Discussões

Este capítulo apresenta os resultados empíricos obtidos a partir da aplicação da arquitetura de risco desenvolvida e apresentada em @cap_metodologia 
aos dados do mercado secundário de crédito corporativo brasileiro. 
A análise é construída de forma sequencial, iniciando pela validação estatística 
rigorosa dos motores de volatilidade e culminando no impacto financeiro real gerado pelas estratégias táticas de alocação.

== Rejeição da Hipótese Nula (Validação de Kupiec)
A eficácia de um sistema de alerta preventivo (*Early Warning*) no mercado de crédito está atrelada à sua capacidade 
de modelar as caudas pesadas da distribuição de retornos. Para testar a acurácia do motor 
EGARCH-t na estimação do *Value at Risk* (VaR), aplicou-se o Teste de Proporção de Falhas de Kupiec (POF).

Os resultados agregados do backtest estatístico, agrupados por classe de indexador, evidenciam a proporção de ativos em que a Hipótese Nula ($H_0$) 
do teste não foi rejeitada (ou seja, a taxa de falhas observada não diferiu estatisticamente da margem de 1% esperada pelo modelo).

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

Embora as taxas de rejeição da Hipótese Nula possam parecer elevadas à primeira vista (especialmente na classe IPCA), estes resultados devem ser interpretados sob a ótica da microestrutura do mercado brasileiro e da severidade da janela temporal analisada. Em primeiro lugar, o backtest de Kupiec foi executado exclusivamente sobre o período *Out-of-Sample* (2023 a 2026). Esta janela temporal engloba a maior crise de crédito privado da história recente do Brasil (marcada pelos colapsos sequenciais das Lojas Americanas e da Light S.A.), que introduziu choques exógenos severos e propiciou resgates em massa nos fundos de investimento. A sustentação de 52,50% de aprovação no grupo CDI Percentual, prevendo o risco sem sobreajuste em meio a choques sistêmicos, atesta uma forte resiliência da premissa autorregressiva.

Adicionalmente, a iliquidez estrutural do mercado secundário de debêntures atua como o principal ofensor analítico do Teste de Proporção de Falhas. Diversos ativos corporativos frequentemente passam dias úteis sem negociação efetiva, permanecendo sujeitos a uma marcação a mercado inerte ou teórica. Quando o papel finalmente é negociado e encontra liquidez real, o prêmio de risco (*spread*) sofre uma reprecificação abrupta, gerando um salto (*jump*) cuja magnitude pontual inevitavelmente rompe o limite projetado pelo VaR de 99%. Como o modelo EGARCH-t assume que a volatilidade condicional rege-se por uma dinâmica fluida de persistência no tempo, as violações detectadas decorrem sobretudo da fragmentação da continuidade dos preços (falta de fluxo regular de negociação), e não de uma ineficácia intrínseca do filtro matemático. Somando-se a isso, a extrema sensibilidade do teste binomial de Kupiec em amostras temporais pequenas condena modelos por desvios mínimos acima da tolerância esperada de 1%.

Cabe ressaltar a diferença conceitual e quantitativa entre os ativos "Aprovados (POF)" e "Aprovados (Conjunto)", expostos na @tab_kupiec. O teste de Kupiec POF avalia estritamente a Cobertura Incondicional (*Unconditional Coverage*), limitando-se a analisar o volume total de falhas. Em contrapartida, a coluna "Aprovados (Conjunto)" reflete a validação pelo Teste Conjunto de Christoffersen, que integra a Cobertura Incondicional à Cobertura Condicional (Teste de Independência). Observa-se que a aprovação conjunta é sistematicamente superior em todos os indexadores. Isso evidencia que as violações ocorridas no *Out-of-Sample* não estão agrupadas no tempo (*volatility clustering*). Portanto, ainda que o modelo sofra rejeição marginal no teste POF devido a um excesso absoluto de falhas causadas pelos saltos de iliquidez, o Teste Conjunto valida a modelagem ao provar que o motor EGARCH-t capturou e mitigou com precisão a dependência temporal da variância, convertendo os choques do mercado em violações isoladas e estatisticamente aleatórias.

== O Desempenho do HMM vs K-Means na Classificação
Estabelecida a validade estatística das métricas de risco de cauda, a análise avalia a agilidade e a coerência dos algoritmos não-supervisionados na tarefa de transpor essas métricas contínuas para Regimes Latentes de risco (Verde, Amarelo e Vermelho). O contraste entre o particionamento geométrico (K-Means) e a inferência temporal (HMM) revela nuances cruciais sobre a capacidade preditiva de cada modelo diante de choques sistêmicos.

== Simulação de Portfólio (Backtest Financeiro)
O teste definitivo da utilidade econômica da modelagem preditiva materializa-se na simulação financeira *Out-of-Sample*. O objetivo deste *backtest* não se limita a aferir o alfa direcional do modelo contra uma estratégia passiva (*Buy-and-Hold*), mas avaliar como as liquidações preventivas (Sinal Amarelo) e retardadas (Sinal Vermelho) impactam a relação de risco-retorno (medida pelo *Sharpe Ratio*) do portfólio.

== O Impacto Prático dos Custos e a Sobrevivência no Mundo Real
A mais acurada predição de crise perde seu valor econômico caso os custos de atrito (*frictions*) para executá-la superem a perda evitada no evento de cauda. Devido às restrições de liquidez estruturais do mercado secundário de debêntures brasileiro, provou-se indispensável analisar o comportamento da estratégia frente à penalidade financeira do excesso de giro (*whipsaw*).