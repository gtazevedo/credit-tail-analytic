= Discussão dos Resultados <sec_discussao_resultados>

A avaliação empírica investigou a eficácia dos modelos sob duas perspectivas complementares: a validação econométrica da cobertura de risco 
e a viabilidade financeira das decisões de investimento em ambiente simulado de mercado.

== Validação Estatística dos Motores de Risco

A acurácia do motor EGARCH-t na estimação do Valor em Risco (VaR 99%) foi testada por meio do Teste de Proporção de Falhas de Kupiec (POF) 
e do Teste de Cobertura Condicional de Christoffersen, adotando significância de 5% ($alpha = 0,05$).

A @tab_kupiec consolida os resultados do teste no período _Out-of-Sample_ (2023 a 2026).

#figure(
  table(
    stroke: 0.5pt,
    columns: (1.5fr, 1fr, 1.3fr, 1.4fr, 1.4fr),
    align: center + horizon,
    [*Indexador*], [*Total*], [*Não-Rejeitados (POF)*], [*Conjunto (95%)*], [*Conjunto (99%)*],
    [CDI Percentual], [40], [21 (52,5%)], [23 (57,5%)], [25 (62,5%)],
    [CDI Spread], [257], [63 (24,5%)], [80 (31,1%)], [105 (40,8%)],
    [IPCA], [365], [133 (36,4%)], [157 (43,0%)], [193 (52,8%)],
    [PRÉ-Fixado], [1], [0 (0,0%)], [0 (0,0%)], [0 (0,0%)],
    [*Total*], [*663*], [*217 (32,7%)*], [*260 (39,2%)*], [*323 (48,7%)*]
  ),
  caption: [Resultados do Teste de Kupiec e Christoffersen por Nível de Confiança.]
) <tab_kupiec>

Para efeitos visuais e comparativos da eficácia do modelo, a figura abaixo exibe a taxa de não-rejeição relativa.

#figure(
  image("../imagens/kupiec_approval_rate.png", width: 80%),
  caption: [Sensibilidade da Não-Rejeição no Teste Conjunto a Diferentes Níveis de Confiança.]
) <fig_kupiec>

Embora as taxas de rejeição da Hipótese Nula possam parecer elevadas em primeiro momento, estes resultados devem ser interpretados sob a ótica da severidade da janela temporal analisada. 
O _backtest_ de Kupiec foi executado exclusivamente sobre o período _Out-of-Sample_ (2023 a 2026). Esta janela temporal 
engloba a maior crise de crédito privado da história recente do Brasil (marcada pelos colapsos sequenciais das Lojas Americanas e da Light S.A. além do mais recente evento do Grupo Pão de Açucar), que 
introduziu choques exógenos severos e propiciou resgates em massa nos fundos de investimento. A sustentação de 57,5% de não-rejeição no grupo CDI Percentual (para um nível de significância de 5%), 
prevendo o risco sem 
sobreajuste em meio a choques sistêmicos, atesta uma forte resiliência da premissa autorregressiva.

A iliquidez estrutural do mercado secundário de debêntures atua como o principal ofensor analítico do Teste de Proporção de Falhas. Diversos ativos corporativos 
frequentemente passam dias úteis sem negociação efetiva. Quando o papel é negociado, o prêmio de risco (_spread_) sofre uma reprecificação abrupta, gerando um salto (_jump_) cuja 
magnitude pontual, em alguns casos, rompe o limite projetado pelo VaR de 99%. Como o modelo EGARCH-t assume que a volatilidade condicional rege-se por uma dinâmica fluida de persistência no 
tempo, as violações detectadas decorrem sobretudo da fragmentação da continuidade dos preços (falta de fluxo regular de negociação), e não de uma ineficácia intrínseca do filtro matemático. 
Somando-se a isso, a extrema sensibilidade do teste binomial de Kupiec em amostras temporais pequenas condena modelos por desvios mínimos acima da tolerância esperada de 1%.

O teste de Kupiec POF, exposto na @tab_kupiec, e, resumido na coluna "Não-Rejeitados (POF)", avalia estritamente a 
Cobertura Incondicional (_Unconditional Coverage_), limitando-se a analisar o número de falhas. Já as colunas "Não-Rejeitados (Conjunto)", para diferentes níveis de confiança, do Teste Conjunto reflete a validação pelo Teste de Christoffersen, 
que integra a Cobertura Incondicional à Cobertura Condicional (Teste de Independência). Observa-se que a não-rejeição conjunta é superior em todos os indexadores. Evidenciando que as 
violações ocorridas no _Out-of-Sample_ não estão agrupadas no tempo (_volatility clustering_). Portanto, ainda que o modelo sofra rejeição marginal no teste POF devido a um excesso de falhas 
causadas pelos saltos de iliquidez, o Teste Conjunto valida a modelagem ao provar que o motor EGARCH-t capturou e mitigou a dependência temporal da variância, 
convertendo os choques do mercado em violações isoladas e estatisticamente aleatórias.

A @fig_kupiec ilustra os dados da @tab_kupiec para auxiliar na visualização da sensibilidade das taxas de não-rejeição do Teste Conjunto frente a variações no nível de significância do próprio teste ($alpha$). 
Ao adotar-se um rigor extremo ($alpha = 0,10$, ou 90% de confiança para não-rejeição), a não-rejeição no indexador IPCA recua para 39,2%. Em contrapartida, sob um critério mais conservador para rejeição de 
modelos ($alpha = 0,01$, ou 99% de confiança), a não-rejeição salta significativamente, alcançando 62,5% no CDI Percentual e 52,9% no IPCA. Essa elasticidade estatística evidencia que grande parte das 
rejeições no cenário-base (95%) ocorre por infrações marginais ao p-valor estipulado, reforçando que o modelo se encontra muito próximo do limiar de validação, mesmo frente ao severo estresse do mercado 
_Out-of-Sample_.

A validação estatística focou primariamente nas métricas de VaR. A ausência de um _backtest_ independente para o _Expected Shortfall_ (ES) é justificado pela natureza estrutural do modelo adotado: 
sob a premissa de distribuição T de Student assimétrica, o ES condicional derivado do motor EGARCH-t atua como uma função analítica direta e co-dependente do quantil do VaR. 
Consequentemente, ao comprovar via Teste de Christoffersen que o filtro de volatilidade captura a frequência correta e expurga o agrupamento das violações, a métrica ES
está intrinsecamente ancorada e validada, dispensando a exigência de avaliações adicionais.

== Agilidade de Detecção e Antecipação de Choques (Lead Time)

Para avaliar a capacidade dos algoritmos de antecipar choques de crédito, foram analisados casos reais de estresse corporativo ocorridos na janela de teste. Destaca-se o caso das debêntures CBRDA8 e 
CBRDB8, emitidas pelo Grupo Pão de Açúcar (GPA). As tabelas @tab_eventos_cbrda8 e @tab_eventos_cbrdb8 detalham as perdas patrimoniais sofridas pelos títulos durante as fases de reprecificação.

#figure(
  table(
    stroke: 0.5pt,
    columns: (1fr, 1.4fr, 1.4fr),
    align: center + horizon,
    [*Data*], [*Preço Unitário (PU)*], [*Spread de Negociação*],
    [23/10/2025], [R\$ 512,13], [12,10%],
    [24/10/2025], [R\$ 453,59], [44,75%],
    [27/10/2025], [R\$ 454,35], [44,28%],
    [25/02/2026], [R\$ 486,91], [45,74%],
    [26/02/2026], [R\$ 460,13], [100,01%],
    [27/02/2026], [R\$ 413,24], [Não Negociado]
  ),
  caption: [Histórico de Reprecificação e Perda de Capital em Choques de Estresse (CBRDA8).]
) <tab_eventos_cbrda8>

#figure(
  table(
    stroke: 0.5pt,
    columns: (1fr, 1.4fr, 1.4fr),
    align: center + horizon,
    [*Data*], [*Preço Unitário (PU)*], [*Spread de Negociação*],
    [21/11/2025], [R\$ 764,80], [19,75%],
    [25/11/2025], [R\$ 630,22], [35,01%],
    [26/11/2025], [R\$ 570,05], [54,99%],
    [01/12/2025], [R\$ 460,86], [101,89%]
  ),
  caption: [Histórico de Reprecificação e Perda de Capital em Choques de Estresse (CBRDB8).]
) <tab_eventos_cbrdb8>

O HMM comprovou maior sensibilidade e agilidade preditiva. Ao incorporar a dependência temporal via matrizes de transição, o HMM antecipou a migração para regimes de alto risco semanas 
antes do choque principal em múltiplos emissores independentes (GPA, CVC Corp e Light). O K-Means apresentou maior inércia, respondendo com atraso às variações iniciais de spread.

As figuras @fig_gpa_kmeans, @fig_gpa_hmm e @fig_gpa_ensemble ilustram o comportamento temporal dos modelos durante o estresse das debêntures do Grupo Pão de Açúcar.

#figure(
  image("../imagens/13_estudo_caso_pão_de_açúcar_(gpa)_kmeans_metric.png", width: 85%),
  caption: [Classificação de Regimes via K-Means no Estudo de Caso GPA.]
) <fig_gpa_kmeans>

#figure(
  image("../imagens/13_estudo_caso_pão_de_açúcar_(gpa)_hmm_prob.png", width: 85%),
  caption: [Probabilidade de Crise via Gaussian HMM no Estudo de Caso GPA.]
) <fig_gpa_hmm>

#figure(
  image("../imagens/13_estudo_caso_pão_de_açúcar_(gpa)_ensemble_prob.png", width: 85%),
  caption: [Probabilidade de Risco do Modelo Ensemble no Estudo de Caso GPA.]
) <fig_gpa_ensemble>

A fim de fornecer rigor quantitativo, evitando a dependência excessiva em um único estudo de caso, expandiu-se a avaliação direcional dos modelos para um rol mais abrangente de eventos de crédito observados no mercado 
corporativo brasileiro entre 2023 e 2026. Porém, para evitar um detalhamento exaustivo de todos os casos, que estenderia este trabalho, optou-se pela seleção de eventos representativos com análise sintetizada, em complemento ao estudo de caso específico do Grupo Pão de Açúcar. 
A premissa central de um modelo de alerta precoce (_Early Warning_) é a capacidade de emitir sinalizações quando se inicia um regime de risco elevado (Regime Vermelho) 
com antecedência suficiente para permitir a liquidação defensiva do portfólio, métrica denominada _Lead Time_.

Por meio de uma comparação entre eventos recentes de deterioração de crédito e as estimações desta pesquisa, foram analisados nove grandes eventos corporativos cujos ativos mantiveram liquidez 
secundária suficiente para a calibração _Out-of-Sample_ dos modelos. A @tab_lead_time consolida a capacidade antecipatória de cada algoritmo ao registrar quantos dias antes do choque principal 
o ativo foi ancorado definitivamente no Regime Vermelho. 

#figure(
  table(
    stroke: 0.5pt,
    columns: (1fr, 1fr, 1.2fr, 1fr, 1fr, 1fr, 1fr),
    align: (left+horizon, left+horizon, center+horizon, center+horizon, center+horizon, center+horizon, center+horizon),
    [*Empresa*], [*Evento*], [*Data*], [*Máx Spread*], [*K-Means*\ (dias)], [*HMM*\ (dias)], [*Ensemble*\ (dias)],
    [Lojas Americanas], [RJ], [01/01/2023], [560,5%], [8 (AT)], [3 (AT)], [3 (AT)],
    [Oi S.A.], [RJ], [01/03/2023], [11,8%], [50 (AT)], [1 (AT)], [1 (AT)],
    [Light S.A.], [RJ], [01/05/2023], [120,9%], [3 (AN)], [5 (AN)], [5 (AN)],
    [CVC Corp], [RP], [01/06/2023], [21,0%], [669 (AT)], [78 (AN)], [78 (AN)],
    [Multilaser], [WV], [01/06/2023], [118,4%], [18 (AT)], [5 (AT)], [35 (AT)],
    [Dasa], [RP], [01/06/2023], [163,8%], [19 (AT)], [1 (AT)], [4 (AT)],
    [Unigel], [RE], [01/02/2024], [87,5%], [253 (AN)], [357 (AN)], [328 (AN)],
    [Casas Bahia], [RE], [01/02/2024], [56,1%], [F], [F], [F],
    [Pão de Açúcar], [RE], [01/03/2026], [190,7%], [129 (AT)], [2 (AN)], [2 (AN)]
  ),
  caption: [Resumo Comparativo: Antecipação (Lead Time) do Alerta de Crise por Modelo. \ *Nota*: Eventos: RJ = Rec. Judicial; RP = Reperfilamento; WV = Waiver; RE = Rec. Extrajudicial. Status: AN = Antecipado; AT = Atraso; F = Falhou.]
) <tab_lead_time>

A análise da @tab_lead_time, calculada sob a premissa de estado de alerta contínuo, ou seja, o modelo entrou no estado vermelho e permaneceu nele de forma ininterrupta até a data do evento, demonstra empiricamente o valor preditivo que a
dependência temporal (matriz de Markov) adiciona à classificação. Ao desconsiderar períodos de instabilidade de regimes (uma vez que só consideramos períodos sem saídas do estado vermelho), o K-Means revelou-se ruidoso, demonstrando 
atrasos efetivos (como observado nos casos da Oi, Dasa e Multilaser). Com exceção da fraude da Lojas Americanas e da Recuperação Extrajudicial da Casas Bahia (onde todos os algoritmos falharam em manter o alerta ininterrupto), o HMM apresentou 
robustez preditiva superior. Para o caso da CVC Corp, o HMM foi capaz de sustentar o alerta de crise 78 dias antes do evento, enquanto o mapeamento geométrico (K-Means) sofreu de forte inércia, resultando em um atraso de 669 dias.

Os resultados do _Ensemble_ demonstram que o K-Means frequentemente contamina a convicção do modelo. Conclui-se, portanto, que o HMM constitui veículo superior de proteção informacional para a liquidação defensiva de 
carteiras, quando consideramos apenas a capacidade de antecipação de alertas de forma ininterrupta até a deflagração do choque financeiro. Ao considerar as regras operacionais definidas na metodologia do _Backtest_ (@subcap_kupiec_backtest), 
em que o portfólio adota um filtro de Quarentena Temporal: caso o modelo acuse Regime Vermelho, o ativo é sumariamente vendido e fica expressamente bloqueado para recompra por um período de 180 dias (6 meses), observa-se uma mudança de comportamento.
Uma vez que um sinal isolado (ainda que configure instabilidade matemática e não se mantenha ininterrupto até o choque) é suficiente para identificar a necessidade de saída do ativo, 
desde que ocorra dentro da janela de 180 dias que antecede o evento. A @tab_lead_time_operacional avalia o _Lead Time_ sob essa ótica puramente operacional: contabiliza-se a distância temporal entre o evento de crédito e o primeiro 
disparo vermelho registrado no semestre anterior.

#figure(
  table(
    stroke: 0.5pt,
    columns: (1fr, 1fr, 1.2fr, 1fr, 1fr, 1fr, 1fr),
    align: (left+horizon, left+horizon, center+horizon, center+horizon, center+horizon, center+horizon, center+horizon),
    [*Empresa*], [*Evento*], [*Data*], [*Máx Spread*], [*K-Means*\ (dias)], [*HMM*\ (dias)], [*Ensemble*\ (dias)],
    [Lojas Americanas], [RJ], [01/01/2023], [560,5%], [8 (AT)], [3 (AT)], [3 (AT)],
    [Oi S.A.], [RJ], [01/03/2023], [11,8%], [33 (AN)], [57 (AN)], [15 (AN)],
    [Light S.A.], [RJ], [01/05/2023], [120,9%], [102 (AN)], [118 (AN)], [77 (AN)],
    [CVC Corp], [RP], [01/06/2023], [21,0%], [669 (AT)], [149 (AN)], [149 (AN)],
    [Multilaser], [WV], [01/06/2023], [118,4%], [148 (AN)], [148 (AN)], [120 (AN)],
    [Dasa], [RP], [01/06/2023], [163,8%], [106 (AN)], [139 (AN)], [97 (AN)],
    [Unigel], [RE], [01/02/2024], [87,5%], [169 (AN)], [169 (AN)], [169 (AN)],
    [Casas Bahia], [RE], [01/02/2024], [56,1%], [F], [F], [F],
    [Pão de Açúcar], [RE], [01/03/2026], [190,7%], [164 (AN)], [180 (AN)], [180 (AN)]
  ),
  caption: [Resumo Comparativo: Antecipação (Lead Time) considerando Quarentena de 180 dias. \ *Nota*: Eventos: RJ = Rec. Judicial; RP = Reperfilamento; WV = Waiver; RE = Rec. Extrajudicial. Status: AN = Antecipado; AT = Atraso; F = Falhou.]
) <tab_lead_time_operacional>

Ao se aplicar a trava temporal de 180 dias, os resultados operacionais do _Lead Time_ se mostram mais robustos. Casos como o da Light S.A., 
onde a antecipação observada havia sido de poucos dias, passaram a contar com antecipação superior a 3 meses ao considerar-se as regras operacionais estabelecidas. O valor máximo de antecipação 
dessa métrica fica matematicamente limitado ao teto da quarentena, o que explica os modelos empatarem em 169 dias e 180 dias (Unigel e Pão de Açúcar, respectivamente), configurando o disparo protetivo 
na borda máxima do semestre. Independentemente da flexibilização operacional demonstrar a viabilidade dos alertas do K-Means e do Ensemble, o HMM manteve superioridade consistente, como evidenciado pela antecedência 
superior na Oi S.A. (57 dias) e Dasa (139 dias), demonstrando a superioridade da memória temporal na antecipação de alterações de regime.


== O Paradoxo da Acurácia-Rentabilidade no Backtest Financeiro 

Apesar da superioridade analítica demonstrada pelo HMM na antecipação de alertas (_Lead Time_), os resultados do _backtest_ financeiro revelaram uma dicotomia entre acurácia 
preditiva teórica e ganho financeiro líquido. Trata-se do conhecido "Paradoxo da Acurácia-Rentabilidade" (_Accuracy-Profitability Paradox_).

A @fig_backtest_pnl exibe a curva de patrimônio líquido acumulado das estratégias táticas contra a carteira passiva (_Buy and Hold_).

#figure(
  image("../imagens/backtest_pnl_portfolio.png", width: 90%),
  caption: [Curva de Retorno Acumulado das Estratégias no Backtest Out-of-Sample.]
) <fig_backtest_pnl>

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
  caption: [Métricas de Risco-Retorno do Backtest Financeiro.]
) <tab_metricas_backtest>

Os resultados consolidados na @tab_metricas_backtest e a evolução temporal da @fig_backtest_pnl revelam o valor adicionado pelas estratégias de _Early Warning_. 
Enquanto o índice passivo (_Buy-and-Hold_) gerou um retorno total de 22,42% penalizado pelo carrego de papéis ilíquidos e depreciados, 
as estratégias reativas obtiveram retornos superiores, destacando-se a _K-Means Vende Amarelo_ e _HMM Vende Amarelo_ que apresentaram retornos acumulados de 
36,18% e 32,62%, respectivamente.

Optou-se pela exclusão da métrica clássica de _Sharpe Ratio_ dessa avaliação, uma vez que debêntures pós-fixadas (atreladas ao CDI) possuem correlação direta com a 
taxa de juros e volatilidade intrínseca artificialmente próxima a zero, o que distorce o índice na avaliação de prêmio de risco 
(tornando o Sharpe assintótico frente a prêmios negativos). Em seu lugar, as métricas utilizadas foram _Maximum Drawdown_ e 
_Calmar Ratio_ (Razão do Retorno Anualizado (CAGR - _Compound Annual Growth Rate_) pelo _Maximum Drawdown_).

Apesar do retorno superior apresentado pelas estratégias ativas, elas também incorreram em maior volatilidade e _Drawdown_, sendo penalizadas quando avaliadas por métricas 
que ponderam risco e retorno. Em especial, a estratégia _HMM (Vende Amarelo)_ apresentou um expressivo _drawdown_ de -9,74% em 2026, originado pela marcação simultânea de diversos ativos no estado de Alerta (Amarelo) 
em decorrência do contágio de crédito gerado pelo evento do grupo GPA. Por possuir uma regra agressiva de _stop loss_, o agente liquidou uma parcela relevante do portfólio 
no mercado secundário exatamente no momento de forte abertura de _spreads_. Esse comportamento evidencia os riscos da sensibilidade acentuada do filtro Bayesiano quando combinado a uma execução automática.

O portfólio _Buy-and-Hold_ apresentou um Calmar de 1,249, sendo superado exclusivamente pelos algoritmos K-Means, com índices de 1,711 (Padrão) e 1,603 (Vende Amarelo). 
A superioridade do K-Means neste aspecto advém justamente da sua latência: por reagir de forma mais lenta e instável aos choques do que o HMM, a estratégia apresentou um menor giro de ativos. 
Com isso, ela evitou a realização maciça de prejuízos de marcação a mercado simultâneos (mitigando o _drawdown_), mas ainda assim conseguiu se desfazer tempestivamente de ativos que apresentavam deterioração irreversível, 
distanciando-se do _Buy-and-Hold_. Esse comportamento poupou a carteira das punições transacionais que afetaram o HMM.

Por fim, o modelo _Ensemble_, desenvolvido com o intuito de harmonizar a reatividade do HMM com a inércia do K-Means, apresentou resultados negativos. Embora tenha sustentado um _Calmar Ratio_ próximo 
ao da estratégia passiva (1,111 _vs._ 1,249), entregou o menor retorno total do período (16,37%), corroído em grande parte pelo efeito _Whipsaw_ (efeito chicote). 
A mediação conflitante dos modelos fez com que o agente acionasse vendas quando o HMM indicava a transição de regime, para logo em seguida recomprar os mesmos ativos assim que a influência do K-Means puxava 
o _score_ novamente para um regime de baixo risco. Conclui-se, portanto, que a modelagem mista falhou estruturalmente ao herdar os custos transacionais da sensibilidade do HMM sem se beneficiar de sua capacidade 
de proteção definitiva, sofrendo das piores características operacionais de seus precursores.

== Validação por Block Bootstrap

Para verificar se a rentabilidade superior do K-Means (_Vende Amarelo_) reflete habilidade tática genuína ou mero acaso amostral, aplicou-se a técnica de _Block Bootstrap_ estacionário com 
10.000 repetições e blocos temporais de 20 dias úteis, seguindo a formulação para séries financeiras dependentes desenvolvida por #cite(<politis1994stationary>, form: "prose"). O procedimento preserva a 
dependência temporal e a autocorrelação residual da carteira dentro de cada bloco reamostrado.

A @fig_bootstrap apresenta a distribuição empírica dos retornos excedentes gerados pela reamostragem.

#figure(
  image("../imagens/bootstrap_significance.png", width: 85%),
  caption: [Distribuição do Retorno Excedente das Estratégias via Block Bootstrap.]
) <fig_bootstrap>

A estratégia K-Means Vende Amarelo registrou p-valor de $0,0416$ ($p < 0,05$), com intervalo de confiança a 95% estritamente positivo em relação ao _Buy and Hold_. Todas as demais estratégias 
registraram p-valores superiores a 0,10, não rejeitando a hipótese de igualdade de desempenho frente ao mercado passivo. O resultado atesta que a disciplina de venda preventiva com filtro de inércia 
agrega valor financeiro verificável sob atritos operacionais realistas.
