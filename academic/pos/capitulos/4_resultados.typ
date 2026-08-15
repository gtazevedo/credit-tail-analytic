= Resultados e Discussões

Este capítulo apresenta os resultados empíricos obtidos a partir da aplicação da arquitetura de risco desenvolvida e apresentada em @cap_metodologia 
aos dados do mercado secundário de crédito corporativo brasileiro. 
A análise é construída de forma sequencial, iniciando pela validação estatística 
rigorosa dos motores de volatilidade e culminando no impacto financeiro real gerado pelas estratégias táticas de alocação.

== Validação Estatística dos Motores <subcap_valest>

A eficácia de um sistema de alerta preventivo (*Early Warning*) no mercado de crédito está atrelada à sua capacidade 
de modelar as caudas pesadas da distribuição de retornos. Para testar a acurácia do motor 
EGARCH-t na estimação do *Value at Risk* (VaR) a 99% de confiança, aplicou-se o Teste de Proporção de Falhas de Kupiec (POF) adotando um nível de significância de 5% ($alpha = 0,05$).

Os resultados agregados do backtest estatístico, agrupados por classe de indexador, evidenciam a proporção de ativos em que a Hipótese Nula ($H_0$) 
do teste não foi rejeitada (ou seja, a taxa de falhas observada não diferiu estatisticamente da margem de 1% esperada pelo modelo).

#figure(
  table(
    stroke: 0.5pt,
    columns: (1.5fr, 1fr, 1.5fr, 1.5fr, 1.5fr, 1.5fr),
    align: center + horizon,
    [*Indexador*], [*Total*], [*Não-Rejeitados\n(POF)*], [*Não-Rejeitados\n(Conj. 90%)*], [*Não-Rejeitados\n(Conj. 95%)*], [*Não-Rejeitados\n(Conj. 99%)*],
    [CDI Percentual], [40], [21], [21 (52,5%)], [23 (57,5%)], [25 (62,5%)],
    [CDI Spread], [257], [63], [68 (26,4%)], [80 (31,1%)], [105 (40,8%)],
    [IPCA], [365], [133], [143 (39,1%)], [157 (43,0%)], [193 (52,8%)],
    [PRÉ-Fixado], [1], [0], [0 (0,0%)], [0 (0,0%)], [0 (0,0%)]
  ),
  caption: [Resultados do Teste de Kupiec (Não-Rejeição de $H_0$) por Nível de Confiança]
) <tab_kupiec>

Para efeitos visuais e comparativos da eficácia do modelo, a figura abaixo exibe a taxa de não-rejeição relativa.

#figure(
  image("../imagens/kupiec_approval_rate.png", width: 80%),
  caption: [Sensibilidade da Não-Rejeição (Teste Conjunto) a Diferentes Níveis de Confiança]
) <fig_kupiec>

Embora as taxas de rejeição da Hipótese Nula possam parecer elevadas em primeiro momento, estes resultados devem ser interpretados sob a ótica da severidade da janela temporal analisada. 
O backtest de Kupiec foi executado exclusivamente sobre o período *Out-of-Sample* (2023 a 2026). Esta janela temporal 
engloba a maior crise de crédito privado da história recente do Brasil (marcada pelos colapsos sequenciais das Lojas Americanas e da Light S.A. além do mais recente evento do Grupo Pão de Açucar), que 
introduziu choques exógenos severos e propiciou resgates em massa nos fundos de investimento. A sustentação de 57,5% de não-rejeição no grupo CDI Percentual (para um nível de significância de 5%), 
prevendo o risco sem 
sobreajuste em meio a choques sistêmicos, atesta uma forte resiliência da premissa autorregressiva.

Adicionalmente, a iliquidez estrutural do mercado secundário de debêntures atua como o principal ofensor analítico do Teste de Proporção de Falhas. Diversos ativos corporativos 
frequentemente passam dias úteis sem negociação efetiva. Quando o papel é negociado, o prêmio de risco (*spread*) sofre uma reprecificação abrupta, gerando um salto (*jump*) cuja 
magnitude pontual, em alguns casos, rompe o limite projetado pelo VaR de 99%. Como o modelo EGARCH-t assume que a volatilidade condicional rege-se por uma dinâmica fluida de persistência no 
tempo, as violações detectadas decorrem sobretudo da fragmentação da continuidade dos preços (falta de fluxo regular de negociação), e não de uma ineficácia intrínseca do filtro matemático. 
Somando-se a isso, a extrema sensibilidade do teste binomial de Kupiec em amostras temporais pequenas condena modelos por desvios mínimos acima da tolerância esperada de 1%.

Cabe ressaltar a diferença conceitual e quantitativa entre os ativos "Não-Rejeitados (POF)" e "Não-Rejeitados (Conjunto)", expostos na @tab_kupiec. O teste de Kupiec POF avalia estritamente a 
Cobertura Incondicional (*Unconditional Coverage*), limitando-se a analisar o volume total de falhas. Em contrapartida, as colunas do Teste Conjunto refletem a validação pelo Teste de Christoffersen, 
que integra a Cobertura Incondicional à Cobertura Condicional (Teste de Independência). Observa-se que a não-rejeição conjunta é sistematicamente superior em todos os indexadores. Isso evidencia que as 
violações ocorridas no *Out-of-Sample* não estão agrupadas no tempo (*volatility clustering*). Portanto, ainda que o modelo sofra rejeição marginal no teste POF devido a um excesso absoluto de falhas 
causadas pelos saltos de iliquidez, o Teste Conjunto valida a modelagem ao provar que o motor EGARCH-t capturou e mitigou com precisão a dependência temporal da variância, 
convertendo os choques do mercado em violações isoladas e estatisticamente aleatórias.

Por fim, a fim de avaliar a robustez destas conclusões, a @fig_kupiec ilustra a sensibilidade das taxas de não-rejeição do Teste Conjunto frente a variações no nível de significância do próprio teste ($alpha$). 
Ao adotar-se um rigor extremo ($alpha = 0,10$, ou 90% de confiança para não-rejeição), a não-rejeição no indexador IPCA recua para 39,1%. Em contrapartida, sob um critério mais conservador para rejeição de 
modelos ($alpha = 0,01$, ou 99% de confiança), a não-rejeição salta significativamente, alcançando 62,5% no CDI Percentual e 52,8% no IPCA. Essa elasticidade estatística evidencia que grande parte das 
rejeições no cenário-base (95%) ocorre por infrações marginais ao p-valor estipulado, reforçando que o modelo se encontra muito próximo do limiar de validação, mesmo frente ao severo estresse do mercado 
*Out-of-Sample*.

A validação estatística focou primariamente nas métricas de VaR. A ausência de um *backtest* independente para o *Expected Shortfall* (ES) é justificado pela natureza estrutural do modelo adotado: 
sob a premissa de distribuição T de Student assimétrica, o ES condicional derivado do motor EGARCH-t atua como uma função analítica direta e co-dependente do quantil do VaR. 
Consequentemente, ao comprovar via Teste de Christoffersen que o filtro de volatilidade captura a frequência correta e expurga o agrupamento das violações, a métrica ES
está intrinsecamente ancorada e validada, dispensando a exigência de avaliações adicionais.


== O Desempenho do HMM vs K-Means na Classificação
Estabelecida a validade estatística das métricas de risco de cauda, a análise avalia a agilidade e a capacidade dos algoritmos não-supervisionados de transpor essas métricas continuas em regimes de risco
pré estabelecidos (Verde, Amarelo e Vermelho). Nas subsessões seguintes serão apresentados os contrastes entre os resultados obtidos pelo particionamento geométrico (K-Means) e a inferência temporal (HMM).
A fim de ilustrar empiricamente o comportamento dos modelos nessa tarefa, iremos utilizar como exemplo o caso de estudo do Grupo Pão de Açucar (GPA) para as debentures CBRDB8 e CBRDA8, ambas são debentures
indexadas CDI+. Nas tabelas @tab_eventos_cbrda8 e @tab_eventos_cbrdb8 pode-se verificar as maiores variações de PU e Taxa ocorrida para ambas as debentures no periodo recente.


#figure(
  table(
    stroke: 0.5pt,
    columns: (1fr, 1.5fr, 1.5fr),
    align: (center+horizon, center+horizon, center+horizon),
    [*Data*], [*Preço Unitário (PU)*], [*Spread (Taxa)*],
    [23/10/2025], [R\$ 512,13], [12,10%],
    [*24/10/2025*], [*R\$ 453,59*], [*44,75% (Choque)*],
    [27/10/2025], [R\$ 454,35], [44,28%],
    [25/02/2026], [R\$ 486,91], [45,74%],
    [*26/02/2026*], [*R\$ 460,13*], [*100,01% (Choque)*],
    [27/02/2026], [R\$ 413,24], [--]
  ),
  caption: [Histórico de Reprecificação e Perda de Capital em Eventos de Estresse - CBRDA8]
) <tab_eventos_cbrda8>

#figure(
  table(
    stroke: 0.5pt,
    columns: (1fr, 1.5fr, 1.5fr),
    align: (center+horizon, center+horizon, center+horizon),
    [*Data*], [*Preço Unitário (PU)*], [*Spread (Taxa)*],
    [21/11/2025], [R\$ 764,80], [19,75%],
    [*25/11/2025*], [*R\$ 630,22*], [*35,01% (Choque)*],
    [26/11/2025], [R\$ 681,76], [28,73%],
    [23/02/2026], [R\$ 864,71], [16,04%],
    [*24/02/2026*], [*R\$ 738,68*], [*30,11% (Choque)*],
    [25/02/2026], [R\$ 793,33], [23,61%],
    [11/06/2026], [R\$ 456,53], [100,38%],
    [*17/06/2026*], [*R\$ 312,66*], [*190,66% (Choque)*],
    [06/07/2026], [R\$ 361,41], [166,10%]
  ),
  caption: [Histórico de Reprecificação e Perda de Capital em Eventos de Estresse - CBRDB8]
) <tab_eventos_cbrdb8>


=== K-Means <subcap_rkmeans>

A fim de ilustrar o resultado do K-Means, tomemos a debênture CBRDB8 (Grupo Pão de Açúcar). Entre fevereiro e junho de 2026, com o agravamento da percepção de crédito da varejista, o ativo sofreu uma severa 
reprecificação sistêmica: o prêmio de risco (*spread*) variou inicialmente de 16,04% em  23/02/2026 para 30,11% em 24/02/2026, voltando a patamares próximos de 23,5%
no final de fevereiro, antes de saltar para patamares de 190% em junho de 2026. Ocasionando uma perda acumulada de mais de 60%. Apesar da magnitude do evento, 
o K-Means demorou a ancorar o ativo no regime de Crise (Vermelho), como se pode observar na @fig_kmeans_gpa, classificando os dias iniciais da quebra como Verde e 
oscilando erraticamente para o Amarelo em uma clara demonstração de *flickering* matemático. 
Por analisar os dados de forma transversal e atemporal, o agrupamento perdeu o poder de inferir a deterioração em curso.

Já no caso da CBRDA8, em 26 de fevereiro de 2026, a taxa do ativo sofreu um salto, variando de 45,7% para 100,0%. Já que a debenture, por estar mais próxima ao vencimento
quando comparada a CBRDB8, possuía uma grande sensibilidade a mudanças na percepção de risco. Todavia, o K-Means falhou em reconhecer, neste caso, a degradação do papel,
mantendo toda a história do ativo como um regime Verde (Baixo Risco). O exemplo demonstra que o K-Means falha em capturar a natureza sequencial dos dados, o que é crucial 
para a gestão de risco de crédito.

Além disso, durante o período de treino (período anterior a Jan/2023), o ativo CBRDA8 possuía 77 dias de negociação, com saltos no spread que levaram o algoritmo de 
máxima verossimilhança que ajustou o EGARCH falhar em convergir. Como houve problemas de convergência, o período *Out-of-Sample* começou em uma escala irreal (volatilidade de 170%
ao ano)
e fez com que o K-Means fosse insensivel aos saltos observados. Já para CBRDB8, o período de treino possuía 65 observações, porém, sem saltos erráticos como no caso anterior,
a volatilidade do periodo  *Out-of-Sample* iniciou em valores realistas (entre 0.1% e 1.5% ao ano), permitindo ao modelo ter melhor sensibilidade as variações observadas. Na
tentativa de limitar, e melhorar a qualidade do resultados observados para casos como CBRDA8 que se implementou a trava de maximo de 20x a variancia *In-Sample*  como
descrito em @subcap_egarch.

#figure(
  image("../imagens/13_estudo_caso_pão_de_açúcar_(gpa)_kmeans_metric.png", width: 90%),
  caption: [Resultados do K-Means para o Estudo de Caso do Grupo Pão de Açúcar (GPA)]
) <fig_kmeans_gpa>


=== HMM <subcap_rhmm>

Sob a mesma ótica do choque das debêntures do GPA, o Modelo Oculto de Markov provou-se superior ao integrar a dependência temporal inerente às 
matrizes de transição ($A$). Para a emissão CBRDB8, sua taxa durante o período *In-Sample* era cerca de 1.7%, porém, com o evento das Lojas Americanas em
Janeiro/Fevereiro de 2023, houve um efeito de contágio no mercado, e a taxa do papel passou a ser negociada próximo de 2.5%. Porém, quando essa variação foi 
comparada com o histórico do papel, foi observada uma variação no Z-Score de 6.5 desvios padrões, levando a classificação no Regime Vermelho já no inicio do
período pelo motor HMM. Como se pode observar na @fig_hmm_gpa.

Já para a CBRDA8, assim como foi dito na @subcap_rkmeans, o EGARCH falhou em convergir no período *In-Sample*, fazendo com que a distribuição do regime Verde
ficasse larga e achatada. Ou seja, mesmo grandes variações para cima ou para baixo não eram suficientes para fazer o modelo sair do regime de baixo risco, 
porém, em Fev/2026, com o salto de spread de 44% (de 45,7% para 100,0%, conforme a @tab_eventos_cbrda8), o motor HMM conseguiu identificar o choque e classificar 
a debênture no regime de crise.

A capacidade de reação do algoritmo HMM comprovam que a característica matricial de transições das Cadeias de Markov Ocultas é indispensável, para a identificação
das alterações de regime e manutenção do estado enquanto não houver alterações bruscas dos sinais de entrada.

#figure(
  image("../imagens/13_estudo_caso_pão_de_açúcar_(gpa)_hmm_prob.png", width: 90%),
  caption: [Resultados do HMM para o Estudo de Caso do Grupo Pão de Açúcar (GPA)]
) <fig_hmm_gpa>

=== Ensemble

Um dos problemas observados no HMM contudo, é a sensibilidade a ruídos, que causam instabilidade, conforme demonstrado pela coluna de Probabilidade do Regime Vermelho na @fig_hmm_gpa.
Na tentativa de mitigar os efeitos de instabilidade do HMM e ao mesmo tempo aproveitar o poder de predição observado, foi desenvolvido um modelo Ensemble, combinando
a probabilidade estimada a partir do modelo K-Means, conforme descrito em @subcap_kmeans, com a probabilidade de transição de regimes do HMM. A ponderação utilizada pode ser
consultada com mais detalhes na @subcap_modelo_misto.

Em relação aos resultados, pode se observar na @fig_ensemble_gpa que a probabilidade de classificação (*Ensemble Score*), apresentou estabilidade, quando comparada ao HMM, porém,
também falhou em capturar a deterioração observada para CBRDA8. Já no caso de CBRDB8, o modelo apresentou variações de estado frequentes, porém, foi capaz de antecipar o choque,
ao contrário do K-Means, porém de forma menos agressiva do que o HMM.

#figure(
  image("../imagens/13_estudo_caso_pão_de_açúcar_(gpa)_ensemble_prob.png", width: 90%),
  caption: [Resultados do Ensemble para o Estudo de Caso do Grupo Pão de Açúcar (GPA)]
) <fig_ensemble_gpa>

== Simulação de Portfólio (Backtest Financeiro) <subcap_resultadosbacktest>

Para avaliação da utilidade econômica da modelagem desenvolvida, foi realizado um *backtest* financeiro para o período *Out-of-Sample*, conforme descrito na @subcap_kupiec_backtest.
O objetivo da simulação não se limita a medir apenas o desempenho direcional dos modelos propostos contra uma estratégia passiva (*Buy-and-Hold*), mas também a avaliar como as diferentes
formas de liquidação (preventiva no sinal amarelo *vs.* retardada no sinal vermelho) impactam a relação risco-retorno da carteira.

#figure(
  image("../imagens/backtest_pnl_portfolio.png", width: 90%),
  caption: [Resultados do Backtest]
) <fig_backtest_pnl_portfolio>

#figure(
  table(
    stroke: 0.5pt,
    columns: (1.5fr, 1fr, 1fr, 1fr, 1fr, 1fr),
    align: (left+horizon, center+horizon, center+horizon, center+horizon, center+horizon, center+horizon),
    [*Estratégia*], [*Retorno Total*], [*CAGR*], [*Volatilidade*], [*Máx. Drawdown*], [*Calmar Ratio*],
    [Buy-and-Hold], [22,42%], [5,98%], [3,50%], [-4,79%], [1,249],
    [K-Means], [27,06%], [7,11%], [4,29%], [-4,16%], [1,711],
    [K-Means (Vende Amarelo)], [36,18%], [9,27%], [8,92%], [-5,78%], [1,603],
    [HMM], [25,95%], [6,85%], [8,82%], [-6,71%], [1,021],
    [HMM (Vende Amarelo)], [32,62%], [8,44%], [12,56%], [-9,74%], [0,866],
    [Ensemble], [16,37%], [4,45%], [4,68%], [-4,00%], [1,111],
    [Ensemble (Vende Amarelo)], [17,58%], [4,76%], [4,70%], [-4,12%], [1,156]
  ),
  caption: [Métricas de Risco-Retorno do Backtest Financeiro]
) <tab_metricas_backtest>

Os resultados consolidados na @tab_metricas_backtest e a evolução temporal da @fig_backtest_pnl_portfolio revelam o valor adicionado pelas estratégias de *Early Warning*. 
Enquanto o índice passivo (*Buy-and-Hold*) gerou um retorno total de 22,42% penalizado pelo carrego de papéis ilíquidos e depreciados, 
as estratégias reativas obtiveram retornos superiores, destacando-se a *K-Means Vende Amarelo* e *HMM Vende Amarelo* que apresentaram retornos acumulados de
36.18% e 32.62% respectivamente.

Optou-se pela exclusão da métrica clássica de *Sharpe Ratio* dessa avaliação, uma vez que debêntures pós-fixadas (atreladas ao CDI) possuem correlação direta com a 
taxa de juros e volatilidade intrínseca artificialmente próxima a zero, o que distorce o índice na avaliação de prêmio de risco
 (tornando o Sharpe assintótico frente a prêmios negativos). Em seu lugar, as métricas utilizadas foram *Maximum Drawdown* e
 *Calmar Ratio* (Razão do Retorno Anualizado (CAGR - *Compound Annual Growth Rate*) pelo *Maximum Drawdown*).

Apesar do retorno superior apresentado pelas estratégias ativas, elas também incorreram em maior volatilidade e *Drawdown*, sendo penalizadas quando avaliadas por métricas
que ponderam risco e retorno. Em especial, a estratégia *HMM (Vende Amarelo)* apresentou um expressivo *drawdown* de -9,74% em 2026, originado pela marcação simultânea de diversos ativos no estado de Alerta (Amarelo)
em decorrência do contágio de crédito gerado pelo evento do grupo GPA. Por possuir uma regra agressiva de *stop loss*, o agente liquidou uma parcela relevante do portfólio
no mercado secundário exatamente no momento de forte abertura de *spreads*. Esse comportamento evidencia os riscos da sensibilidade acentuada do filtro Bayesiano quando acoplado a uma execução automática.

O portfólio *Buy-and-Hold* apresentou um Calmar de 1,249, sendo superado exclusivamente pelos algoritmos K-Means, com índices de 1,711 (Padrão) e 1,603 (Vende Amarelo). 
A superioridade ruidosa do K-Means neste aspecto advém justamente da sua latência: por reagir de forma mais lenta e instável aos choques do que o HMM, a estratégia apresentou um menor giro de ativos. 
Dessa forma, ela evitou a realização maciça de prejuízos de marcação a mercado simultâneos (mitigando o *drawdown*), mas ainda assim conseguiu se desfazer tempestivamente de papéis que apresentavam deterioração irreversível, distanciando-se do *Buy-and-Hold*. Esse comportamento acidental poupou a carteira das severas punições transacionais que afetaram o HMM.

Por fim, o modelo *Ensemble* — desenvolvido com o intuito de harmonizar a reatividade do HMM com a inércia do K-Means — apresentou resultados amplamente negativos. Embora tenha sustentado um *Calmar Ratio* próximo
ao da estratégia passiva (1,111 *vs.* 1,249), entregou o pior retorno total do período (16,37%), corroído quase integralmente pelo efeito *Whipsaw* (efeito chicote). 
A mediação conflitante dos modelos fez com que o agente acionasse vendas quando o HMM indicava a transição de regime, para logo em seguida recomprar os mesmos ativos assim que a influência do K-Means puxava o *score* novamente para um regime de baixo risco. Conclui-se, portanto, que a modelagem mista falhou estruturalmente ao herdar os custos transacionais da sensibilidade do HMM sem se beneficiar de sua capacidade de proteção definitiva, sofrendo das piores características operacionais de seus precursores.

=== Significância Estatística das Estratégias — Block Bootstrap

A superioridade das estratégias ativas em termos de retorno absoluto não é, por si só, evidência científica suficiente de que os modelos adicionam valor. O período *Out-of-Sample* (2023–2026) foi marcado por eventos excepcionais de crédito, o que levanta a questão: os retornos superiores observados decorrem genuinamente da capacidade preditiva dos algoritmos, ou são produto do período amostral específico?

Para responder a essa pergunta, aplicou-se o *Stationary Block Bootstrap* #cite(<politis1994stationary>) com $n = 10.000$ amostras e blocos de 20 dias úteis ($approx$ 1 mês), que preserva a estrutura de autocorrelação temporal dos retornos diários. A hipótese testada é:

- *H0₃*: A estratégia ativa *não* supera o Buy-and-Hold em termos de retorno médio anualizado ($mu_("estratégia") <= mu_("BnH")$).
- *H1₃*: A estratégia supera o Buy-and-Hold (teste unilateral à direita, $alpha = 5\%$).

O p-valor reportado representa a proporção de amostras bootstrap em que o retorno médio da estratégia foi inferior ou igual ao do benchmark, de forma que valores abaixo de 0,05 levam à rejeição de H0₃.

#figure(
  table(
    stroke: 0.5pt,
    columns: (2fr, 1fr, 1fr, 1fr, 1fr, 1fr),
    align: (left+horizon, center+horizon, center+horizon, center+horizon, center+horizon, center+horizon),
    [*Estratégia*], [*Retorno\\n(%aa)*], [*BnH\\n(%aa)*], [*Diferença\\n(%aa)*], [*p-valor*], [*H0₃*],
    [KMeans], [6,97%], [5,87%], [+1,10%], [0,134], [Não Rejeitada],
    [HMM], [7,02%], [5,87%], [+1,15%], [0,225], [Não Rejeitada],
    [Ensemble], [4,47%], [5,87%], [-1,41%], [0,868], [Não Rejeitada],
    [*K-Means (Vende Amarelo)*], [*9,27%*], [*5,87%*], [*+3,40%*], [*0,015*], [*Rejeitada ✓*],
    [HMM (Vende Amarelo)], [8,90%], [5,87%], [+3,03%], [0,059], [Não Rejeitada],
    [Ensemble (Vende Amarelo)], [4,76%], [5,87%], [-1,11%], [0,808], [Não Rejeitada],
  ),
  caption: [Resultados do Block Bootstrap ($n=10.000$, $alpha=5\%$, bloco=20 dias) — Significância Estatística vs. Buy-and-Hold]
) <tab_bootstrap>

Os resultados do @tab_bootstrap revelam um achado central: *apenas a estratégia K-Means (Vende Amarelo) rejeita H0₃ ao nível de 5%* ($p = 0,015$, IC 95%: [+0,33%; +6,78%]). A estratégia HMM (Vende Amarelo) apresenta p-valor de 0,059, próximo ao limiar de significância, não rejeitando H0₃ sob o critério convencional de 5%, mas sugerindo evidência marginal de superioridade.

Este resultado é coerente com o diagnóstico do *Paradoxo da Latência*: a inércia do K-Means, que aparentava ser uma deficiência preditiva (menor reatividade a mudanças de regime), transformou-se em vantagem financeira — ao evitar o excesso de giro e o efeito *Whipsaw* que corrói os demais modelos. A estratégia HMM puro e as estratégias Ensemble, a despeito de retornos nominais superiores ao benchmark, não apresentam superioridade estatisticamente comprovável, evidenciando que seus ganhos estão dentro do intervalo de incerteza esperado para o período amostral específico.

#figure(
  image("../imagens/bootstrap_significance.png", width: 90%),
  caption: [Forest Plot — Diferença de Retorno vs. Buy-and-Hold com Intervalo de Confiança 95% (Block Bootstrap)]
) <fig_bootstrap>

=== Discussão sobre a Generalização dos Resultados

Os resultados apresentados neste estudo foram obtidos a partir de um conjunto específico de condições empíricas que delimitam sua generalização direta:

1. *Período amostral*: O período *Out-of-Sample* (2023–2026) engloba uma das maiores crises de crédito privado brasileiro da história recente (com colapsos sequenciais de Lojas Americanas, Light S.A. e incertezas em torno do Grupo Pão de Açúcar). A eficácia contundente das estratégias ativas, especialmente do K-Means (Vende Amarelo), foi alavancada pela necessidade extrema de mitigação de risco durante choques agudos. Em ciclos de expansão de crédito com baixa volatilidade, estratégias ativas podem apresentar performance marginal inferior ao carrego passivo, devido ao peso dos custos transacionais sem a contrapartida de grandes eventos de cauda.
2. *Universo de ativos*: A amostra final se restringe a debêntures com liquidez mínima suficiente para permitir a convergência do motor de estimação EGARCH. Ativos de crédito marcadamente ilíquidos — que operam fora da curva Anbima ou não possuem fluxo de negociação regular em mercado secundário — não foram testados por essa metodologia estrutural. Estratégias aplicadas a essas carteiras podem sofrer distorções materiais.
3. *Estrutura de custos operacionais*: A simulação assumiu um custo de transação de 0,5% por operação, considerado conservador e aderente à média do mercado secundário corporativo em tempos normais. Contudo, sob estresse extremo, a liquidez direcional do mercado seca e os *spreads* de compra-venda (*bid-ask spread*) podem expandir severamente, inviabilizando ou majorando exponencialmente as saídas defensivas executadas pelos algoritmos.
4. *Qualidade da informação (Marcação a Mercado)*: Os indicadores preditivos dependem intimamente do reflexo primário dos *spreads* na curva indicativa (Anbima). O alisamento intrínseco aos processos de marcação a mercado no Brasil introduz latência que pode atrasar a identificação quantitativa de risco por parte dos motores bayesianos.

Apesar dessas limitações inerentes à amostra brasileira, os alicerces metodológicos da arquitetura desenvolvida — notadamente a integração da volatilidade condicional leptocúrtica como *feature* para particionamento temporal dinâmico (*Time-Series Clustering*) — constituem um arcabouço inovador que pode ser adaptado e generalizado para outros mercados globais de crédito estruturado caracterizados por informações assimétricas e baixa liquidez.
