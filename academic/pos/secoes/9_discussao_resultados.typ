= Discussão dos Resultados <sec_discussao_resultados>

A avaliação empírica investigou a eficácia dos modelos sob duas perspectivas complementares: a validação econométrica da cobertura de risco 
e a viabilidade financeira das decisões de investimento em ambiente simulado de mercado.

== Validação Estatística dos Motores de Risco

A acurácia do motor EGARCH-t na estimação do Valor em Risco (VaR 99%) foi testada por meio do Teste de Proporção de Falhas de Kupiec (POF) 
e do Teste de Cobertura Condicional de Christoffersen, adotando significância de 5% ($alpha = 0,05$).

A @tab_kupiec consolida os resultados do teste no período _Out-of-Sample_ (2023 a 2026), abrangendo 663 séries temporais com negócios registrados nessa janela (incluindo emissões posteriores a 2022).

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

A @fig_kupiec sintetiza a sensibilidade da taxa de não-rejeição relativa do Teste Conjunto frente aos níveis de significância estipulados.

#figure(
  image("../imagens/kupiec_approval_rate.png", width: 80%),
  caption: [Sensibilidade da Não-Rejeição no Teste Conjunto a Diferentes Níveis de Confiança.]
) <fig_kupiec>

Embora as taxas de rejeição da Hipótese Nula possam parecer elevadas em um primeiro momento, esses resultados devem ser interpretados sob a ótica da magnitude do estresse observado na janela temporal analisada. 
O _backtest_ de Kupiec foi executado exclusivamente sobre o período _Out-of-Sample_ (2023 a 2026). Essa janela temporal 
engloba um período de elevado estresse no mercado de crédito privado brasileiro (marcado pelos pedidos sequenciais de recuperação judicial das Lojas Americanas e da Light S.A., além da reestruturação do Grupo Pão de Açúcar), o qual 
introduziu choques exógenos atípicos e propiciou expressivo volume de resgates na indústria de fundos de investimento. A sustentação de 57,5% de não-rejeição no grupo CDI Percentual (para um nível de significância de 5%), 
prevendo o risco sem 
sobreajuste em meio a choques sistêmicos, atesta uma elevada resiliência da premissa autorregressiva.

A iliquidez estrutural do mercado secundário de debêntures constitui a principal causa de distorções estatísticas no Teste de Proporção de Falhas. Diversos ativos corporativos 
frequentemente passam dias úteis sem negociação efetiva. Quando o ativo é negociado, o prêmio de risco (_spread_) sofre uma reprecificação abrupta, gerando um salto (_jump_) cuja 
magnitude pontual, em alguns casos, rompe o limite projetado pelo VaR de 99%. Como o modelo EGARCH-t assume que a volatilidade condicional rege-se por uma dinâmica fluida de persistência no 
tempo, as violações detectadas decorrem sobretudo da fragmentação da continuidade dos preços (falta de fluxo regular de negociação), e não de uma ineficácia intrínseca do filtro matemático. 
Adicionalmente, a sensibilidade do teste binomial de Kupiec em amostras temporais reduzidas induz à rejeição de modelos por desvios marginais acima da tolerância esperada de 1%.

O teste de Kupiec POF, exposto na @tab_kupiec e resumido na coluna "Não-Rejeitados (POF)", avalia estritamente a 
Cobertura Incondicional (_Unconditional Coverage_), limitando-se a analisar o número de falhas. Já as colunas "Não-Rejeitados (Conjunto)", para diferentes níveis de confiança, do Teste Conjunto refletem a validação pelo Teste de Christoffersen, 
que integra a Cobertura Incondicional à Cobertura Condicional (Teste de Independência). Observa-se que a não-rejeição conjunta é superior em todos os indexadores, evidenciando que as 
violações ocorridas no _Out-of-Sample_ não estão agrupadas no tempo (_volatility clustering_). Portanto, ainda que o modelo sofra rejeição marginal no teste POF devido a um excesso de falhas 
causadas pelos saltos de iliquidez, o Teste Conjunto valida a modelagem ao evidenciar que o motor EGARCH-t capturou e mitigou a dependência temporal da variância, 
convertendo os choques do mercado em violações isoladas e estatisticamente aleatórias.

A @fig_kupiec ilustra os dados da @tab_kupiec para auxiliar na visualização da sensibilidade das taxas de não-rejeição do Teste Conjunto frente a variações no nível de significância do próprio teste ($alpha$). 
Ao adotar-se um rigor extremo ($alpha = 0,10$, ou 90% de confiança para não-rejeição), a não-rejeição no indexador IPCA recua para 39,2%. Em contrapartida, sob um critério mais conservador para rejeição de 
modelos ($alpha = 0,01$, ou 99% de confiança), a taxa de não-rejeição eleva-se, alcançando 62,5% no CDI Percentual e 52,9% no IPCA. Essa elasticidade estatística evidencia que grande parte das 
rejeições no cenário-base (95%) ocorre por infrações marginais ao p-valor estipulado, reforçando que o modelo se encontra muito próximo do limiar de validação, mesmo frente ao elevado estresse do mercado 
_Out-of-Sample_.

A validação estatística focou primariamente nas métricas de VaR. A ausência de um _backtest_ independente para o _Expected Shortfall_ (ES) é justificada pela natureza estrutural do modelo adotado: 
sob a premissa de distribuição T de Student assimétrica, o ES condicional derivado do motor EGARCH-t atua como uma função analítica direta e co-dependente do quantil do VaR. 
Consequentemente, ao evidenciar, por meio do Teste de Christoffersen, que o filtro de volatilidade captura a frequência correta e elimina o agrupamento temporal das violações, a métrica ES
torna-se intrinsecamente ancorada e consistente, dispensando avaliações adicionais.

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

O HMM evidenciou maior sensibilidade e agilidade preditiva. Ao incorporar a dependência temporal via matrizes de transição, o HMM antecipou a migração para regimes de alto risco semanas 
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

Para assegurar solidez analítica e afastar o viés amostral de um caso isolado, expandiu-se a avaliação direcional para nove eventos relevantes de deterioração de crédito observados no mercado secundário entre 2023 e 2026. A 
@tab_lead_time consolida a capacidade antecipatória de cada algoritmo ao registrar quantos dias antes do choque principal o ativo foi ancorado definitivamente no Regime Vermelho, métrica denominada _Lead Time_.

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

A análise da @tab_lead_time, calculada sob a premissa de estado de alerta contínuo — na qual o modelo atinge o estado vermelho e nele permanece de maneira ininterrupta até a data do evento —, evidencia empiricamente o valor preditivo que a
dependência temporal (matriz de Markov) agrega à classificação. Ao desconsiderar períodos de instabilidade de regimes (delimitando-se a análise a regimes de alerta permanente sem transições de saída), o K-Means apresentou oscilações de classificação, demonstrando 
atrasos efetivos (como observado nos casos da Oi, Dasa e Multilaser). Com exceção da recuperação judicial das Lojas Americanas e da Recuperação Extrajudicial das Casas Bahia (nas quais todos os algoritmos falharam em manter o alerta ininterrupto), o HMM apresentou 
robustez preditiva superior. Para o caso da CVC Corp, o HMM foi capaz de sustentar o alerta de crise 78 dias antes do evento, enquanto o particionamento geométrico (K-Means) apresentou maior inércia, resultando em defasagem temporal de 669 dias.

Os resultados do _Ensemble_ demonstram que a inclusão do K-Means dilui a probabilidade condicional de alerta gerada pelo HMM. 
Constata-se que a modelagem markoviana isolada apresenta maior eficácia na sinalização ininterrupta para a liquidação defensiva de 
carteiras, caso se avalie estritamente a sustentação do alerta de crise até a deflagração do choque financeiro. Ao considerar as regras operacionais definidas na metodologia do _Backtest_ (@subcap_kupiec_backtest), 
em que o portfólio adota um filtro de Quarentena Temporal: caso o modelo acuse Regime Vermelho, o ativo é alienado e permanece bloqueado para recompra por um período de 180 dias (6 meses), observa-se uma alteração
na eficácia prática. Sob essa diretriz operacional, um sinal isolado (ainda que configure instabilidade matemática e não se mantenha ininterrupto até o choque) determina a liquidação imediata da posição e impede a recompra imediata durante
o período de quarentena semestral, bastando que ocorra dentro da janela de 180 dias antecedentes ao choque. A @tab_lead_time_operacional consolida o _Lead Time_ sob este critério de execução.

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

Ao se aplicar a trava temporal de 180 dias, os resultados operacionais do _Lead Time_ apresentam maior consistência prática. Casos como o da Light S.A., 
nos quais a antecipação observada restringia-se a poucos dias, passaram a registrar antecipação superior a três meses sob as diretrizes operacionais adotadas. O valor máximo de antecipação 
dessa métrica fica delimitado ao teto da quarentena, o que justifica a convergência dos modelos em 169 dias e 180 dias (Unigel e Pão de Açúcar, respectivamente), configurando o acionamento protetivo 
na borda do semestre. Ainda que a flexibilização operacional evidencie a viabilidade dos alertas do K-Means e do Ensemble, o HMM manteve maior capacidade antecipatória, como observado na Oi S.A. (57 dias) e na Dasa (139 dias), o que corrobora a relevância da dependência temporal na sinalização precoce de alterações de regime.


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
Enquanto o índice passivo (_Buy-and-Hold_) gerou um retorno total de 22,42% penalizado pelo carrego de títulos ilíquidos e depreciados, 
as estratégias ativas obtiveram retornos superiores, destacando-se a _K-Means Vende Amarelo_ e a _HMM Vende Amarelo_, que apresentaram retornos acumulados de 
36,18% e 32,62%, respectivamente.

A avaliação de risco do portfólio privilegiou o _Calmar Ratio_ (razão entre a taxa composta anualizada de crescimento e o recuo máximo de pico a vale) e o _Maximum Drawdown_ em detrimento do Índice de Sharpe, 
pois essas métricas refletem com fidelidade a penalização imposta pelos custos de liquidação forçada e não sofrem a distorção teórica descrita na @subcap_modelo_ensemble.

Apesar do retorno superior apresentado pelas estratégias ativas, elas também incorreram em maior volatilidade e _Drawdown_, sendo penalizadas quando avaliadas por métricas 
que ponderam risco e retorno. Em especial, a estratégia _HMM (Vende Amarelo)_ apresentou um expressivo _drawdown_ de -9,74% em 2026, originado pela marcação simultânea de diversos ativos no estado de Alerta (Amarelo) 
em decorrência do contágio de crédito gerado pelo evento do grupo GPA. Por possuir uma regra estrita de _stop loss_, a estratégia liquidou uma parcela relevante do portfólio 
no mercado secundário no momento exato de expressiva abertura de _spreads_. Esse comportamento evidencia os riscos da sensibilidade acentuada do filtro Bayesiano quando combinado a uma execução automática.

O portfólio _Buy-and-Hold_ apresentou um Calmar de 1,249, sendo superado exclusivamente pelos algoritmos K-Means, com índices de 1,711 (Padrão) e 1,603 (Vende Amarelo). 
A superioridade do K-Means neste aspecto advém justamente da sua latência: por reagir de forma mais lenta e instável aos choques do que o HMM, a estratégia apresentou um menor giro de ativos. 
Com isso, ela evitou a liquidação precipitada de posições sob deságio temporário (mitigando o _drawdown_), assegurando a liquidação tempestiva de posições que apresentavam deterioração irreversível, 
distanciando-se do _Buy-and-Hold_. Esse comportamento atenuou o impacto dos custos de transação recorrentes que incidiram sobre a estratégia HMM.

Por fim, o modelo _Ensemble_, desenvolvido com o intuito de harmonizar a reatividade do HMM com a inércia do K-Means, apresentou resultados negativos. Embora tenha sustentado um _Calmar Ratio_ próximo 
ao da estratégia passiva (1,111 _vs._ 1,249), entregou o menor retorno total do período (16,37%), penalizado em grande parte pelo efeito _Whipsaw_ (efeito chicote). 
A mediação conflitante dos modelos fez com que a estratégia acionasse vendas quando o HMM indicava a transição de regime, para logo em seguida recomprar os mesmos ativos assim que a influência do K-Means 
deslocava a pontuação novamente para o regime de baixo risco. Essa dinâmica evidenciou que a arquitetura híbrida revelou-se ineficaz sob o ponto de vista financeiro: a sobreposição entre a reatividade do HMM e 
a inércia do K-Means apenas inflacionou a fricção transacional, sem proporcionar cobertura protetiva correspondente.

== Validação por Block Bootstrap

Com o intuito de discernir se o retorno excedente auferido pelo K-Means (_Vende Amarelo_) decorre de efetiva consistência tática ou de mero viés de amostragem, submeteu-se a série temporal a um teste 
de _Block Bootstrap_ estacionário (#cite(<politis1994stationary>, form: "prose")). Adotaram-se 10.000 iterações em blocos de 20 dias úteis, dimensão calibrada para preservar a dependência estocástica 
e a estrutura de autocorrelação serial típica do mercado de crédito.

A @fig_bootstrap sintetiza a dispersão das distribuições simuladas frente ao retorno passivo.

#figure(
  image("../imagens/bootstrap_significance.png", width: 85%),
  caption: [Distribuição do Retorno Excedente das Estratégias via Block Bootstrap.]
) <fig_bootstrap>

Entre todas as abordagens testadas, unicamente a estratégia K-Means Vende Amarelo atingiu relevância estatística, com $p = 0,0416$ ($p < 0,05$) e intervalo com 95% de confiança inteiramente deslocado 
para o campo positivo em relação ao _Buy-and-Hold_. As configurações remanescentes exibiram $p > 0,10$, impedindo a rejeição da hipótese nula de igualdade. O teste comprova, sob o rigor da reamostragem 
em blocos, que o atraso prudencial imposto pelo filtro de inércia gerou alfa genuíno mesmo após a absorção de custos operacionais expressivos.
