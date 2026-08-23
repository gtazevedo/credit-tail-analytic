= Resultados e Discussões <cap_resultados>

Este capítulo apresenta os resultados empíricos obtidos a partir da aplicação da arquitetura de risco desenvolvida e apresentada na @cap_metodologia 
aos dados do mercado secundário de crédito corporativo brasileiro. 
A análise é construída de forma sequencial, iniciando pela validação estatística 
dos motores de volatilidade e culminando no impacto financeiro gerado pelas estratégias táticas de alocação.

== Validação Estatística dos Motores <subcap_valest>

A eficácia de um sistema de alerta preventivo (_Early Warning_) no mercado de crédito está atrelada à sua capacidade 
de modelar as caudas pesadas da distribuição de retornos. Para testar a acurácia do motor 
EGARCH-t na estimação do _Value at Risk_ (VaR) a 99% de confiança, aplicou-se o Teste de Proporção de Falhas de Kupiec (POF)#footnote[Devido à volumetria da amostra, os resultados analíticos granulares do Teste de Kupiec, bem como os dados dos demais testes detalhados individualmente por debênture, foram consolidados e encontram-se disponíveis na pasta `anexos_digitais/` no repositório público desta pesquisa no GitHub.] adotando um nível de significância de 5% ($alpha = 0,05$).

Os resultados agregados do _backtest_ estatístico, agrupados por classe de indexador, evidenciam a proporção de ativos em que a Hipótese Nula ($H_0$) 
do teste não foi rejeitada (ou seja, a taxa de falhas observada não diferiu estatisticamente da margem de 1% esperada pelo modelo).

#figure(
  table(
    stroke: 0.5pt,
    columns: (1.5fr, 1fr, 1.5fr, 1.5fr, 1.5fr, 1.5fr),
    align: center + horizon,
    [*Indexador*], [*Total*], [*Não-Rejeitados \ (POF)*], [*Não-Rejeitados \ (Conj. 90%)*], [*Não-Rejeitados \ (Conj. 95%)*], [*Não-Rejeitados \ (Conj. 99%)*],
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
O _backtest_ de Kupiec foi executado exclusivamente sobre o período _Out-of-Sample_ (2023 a 2026). Esta janela temporal 
engloba a maior crise de crédito privado da história recente do Brasil (marcada pelos colapsos sequenciais das Lojas Americanas e da Light S.A. além do mais recente evento do Grupo Pão de Açucar), que 
introduziu choques exógenos severos e propiciou resgates em massa nos fundos de investimento. A sustentação de 57,5% de não-rejeição no grupo CDI Percentual (para um nível de significância de 5%), 
prevendo o risco sem 
sobreajuste em meio a choques sistêmicos, atesta uma forte resiliência da premissa autorregressiva.

Adicionalmente, a iliquidez estrutural do mercado secundário de debêntures atua como o principal ofensor analítico do Teste de Proporção de Falhas. Diversos ativos corporativos 
frequentemente passam dias úteis sem negociação efetiva. Quando o papel é negociado, o prêmio de risco (_spread_) sofre uma reprecificação abrupta, gerando um salto (_jump_) cuja 
magnitude pontual, em alguns casos, rompe o limite projetado pelo VaR de 99%. Como o modelo EGARCH-t assume que a volatilidade condicional rege-se por uma dinâmica fluida de persistência no 
tempo, as violações detectadas decorrem sobretudo da fragmentação da continuidade dos preços (falta de fluxo regular de negociação), e não de uma ineficácia intrínseca do filtro matemático. 
Somando-se a isso, a extrema sensibilidade do teste binomial de Kupiec em amostras temporais pequenas condena modelos por desvios mínimos acima da tolerância esperada de 1%.

Cabe ressaltar a diferença conceitual e quantitativa entre os ativos "Não-Rejeitados (POF)" e "Não-Rejeitados (Conjunto)", expostos na @tab_kupiec. O teste de Kupiec POF avalia estritamente a 
Cobertura Incondicional (_Unconditional Coverage_), limitando-se a analisar o volume total de falhas. Em contrapartida, as colunas do Teste Conjunto refletem a validação pelo Teste de Christoffersen, 
que integra a Cobertura Incondicional à Cobertura Condicional (Teste de Independência). Observa-se que a não-rejeição conjunta é sistematicamente superior em todos os indexadores. Isso evidencia que as 
violações ocorridas no _Out-of-Sample_ não estão agrupadas no tempo (_volatility clustering_). Portanto, ainda que o modelo sofra rejeição marginal no teste POF devido a um excesso absoluto de falhas 
causadas pelos saltos de iliquidez, o Teste Conjunto valida a modelagem ao provar que o motor EGARCH-t capturou e mitigou com precisão a dependência temporal da variância, 
convertendo os choques do mercado em violações isoladas e estatisticamente aleatórias.

Por fim, a fim de avaliar a robustez destas conclusões, a @fig_kupiec ilustra a sensibilidade das taxas de não-rejeição do Teste Conjunto frente a variações no nível de significância do próprio teste ($alpha$). 
Ao adotar-se um rigor extremo ($alpha = 0,10$, ou 90% de confiança para não-rejeição), a não-rejeição no indexador IPCA recua para 39,1%. Em contrapartida, sob um critério mais conservador para rejeição de 
modelos ($alpha = 0,01$, ou 99% de confiança), a não-rejeição salta significativamente, alcançando 62,5% no CDI Percentual e 52,8% no IPCA. Essa elasticidade estatística evidencia que grande parte das 
rejeições no cenário-base (95%) ocorre por infrações marginais ao p-valor estipulado, reforçando que o modelo se encontra muito próximo do limiar de validação, mesmo frente ao severo estresse do mercado 
_Out-of-Sample_.

A validação estatística focou primariamente nas métricas de VaR. A ausência de um _backtest_ independente para o _Expected Shortfall_ (ES) é justificado pela natureza estrutural do modelo adotado: 
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
    [*24/10/2025*], [*R\$ 453,59*], [*44,75%*],
    [27/10/2025], [R\$ 454,35], [44,28%],
    [25/02/2026], [R\$ 486,91], [45,74%],
    [*26/02/2026*], [*R\$ 460,13*], [*100,01%*],
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
    [*25/11/2025*], [*R\$ 630,22*], [*35,01%*],
    [26/11/2025], [R\$ 681,76], [28,73%],
    [23/02/2026], [R\$ 864,71], [16,04%],
    [*24/02/2026*], [*R\$ 738,68*], [*30,11%*],
    [25/02/2026], [R\$ 793,33], [23,61%],
    [11/06/2026], [R\$ 456,53], [100,38%],
    [*17/06/2026*], [*R\$ 312,66*], [*190,66%*],
    [06/07/2026], [R\$ 361,41], [166,10%]
  ),
  caption: [Histórico de Reprecificação e Perda de Capital em Eventos de Estresse - CBRDB8]
) <tab_eventos_cbrdb8>


=== K-Means <subcap_rkmeans>

A fim de ilustrar o resultado do K-Means, tomemos a debênture CBRDB8 (Grupo Pão de Açúcar). Entre fevereiro e junho de 2026, com o agravamento da percepção de crédito da varejista, o ativo sofreu uma severa 
reprecificação sistêmica: o prêmio de risco (_spread_) variou inicialmente de 16,04% em  23/02/2026 para 30,11% em 24/02/2026, voltando a patamares próximos de 23,5%
no final de fevereiro, antes de saltar para patamares de 190% em junho de 2026. Ocasionando uma perda acumulada de mais de 60%. Apesar da magnitude do evento, 
o K-Means demorou a ancorar o ativo no regime de Crise (Vermelho), como se pode observar na @fig_kmeans_gpa, classificando os dias iniciais da quebra como Verde e 
oscilando erraticamente para o Amarelo em uma clara demonstração de _flickering_ matemático. 
Por analisar os dados de forma transversal e atemporal, o agrupamento perdeu o poder de inferir a deterioração em curso.

Já no caso da CBRDA8, em 26 de fevereiro de 2026, a taxa do ativo sofreu um salto, variando de 45,7% para 100,0%. Já que a debenture, por estar mais próxima ao vencimento
quando comparada a CBRDB8, possuía uma grande sensibilidade a mudanças na percepção de risco. Todavia, o K-Means falhou em reconhecer, neste caso, a degradação do papel,
mantendo toda a história do ativo como um regime Verde (Baixo Risco). O exemplo demonstra que o K-Means falha em capturar a natureza sequencial dos dados, o que é crucial 
para a gestão de risco de crédito.

Além disso, durante o período de treino (período anterior a Jan/2023), o ativo CBRDA8 possuía 77 dias de negociação, com saltos no _spread_ que levaram o algoritmo de 
máxima verossimilhança que ajustou o EGARCH falhar em convergir. Como houve problemas de convergência, o período _Out-of-Sample_ começou em uma escala irreal (volatilidade de 170%
ao ano)
e fez com que o K-Means fosse insensivel aos saltos observados. Já para CBRDB8, o período de treino possuía 65 observações, porém, sem saltos erráticos como no caso anterior,
a volatilidade do periodo  _Out-of-Sample_ iniciou em valores realistas (entre 0.1% e 1.5% ao ano), permitindo ao modelo ter melhor sensibilidade as variações observadas. Na
tentativa de limitar, e melhorar a qualidade do resultados observados para casos como CBRDA8 que se implementou a trava de maximo de 20x a variancia _In-Sample_  como
descrito em @subcap_egarch.

#figure(
  image("../imagens/13_estudo_caso_pão_de_açúcar_(gpa)_kmeans_metric.png", width: 90%),
  caption: [Resultados do K-Means para o Estudo de Caso do Grupo Pão de Açúcar (GPA)]
) <fig_kmeans_gpa>


=== HMM <subcap_rhmm>

Sob a mesma ótica do choque das debêntures do GPA, o Modelo Oculto de Markov provou-se superior ao integrar a dependência temporal inerente às 
matrizes de transição ($A$). Para a emissão CBRDB8, sua taxa durante o período _In-Sample_ era cerca de 1.7%, porém, com o evento das Lojas Americanas em
Janeiro/Fevereiro de 2023, houve um efeito de contágio no mercado, e a taxa do papel passou a ser negociada próximo de 2.5%. Porém, quando essa variação foi 
comparada com o histórico do papel, foi observada uma variação no Z-Score de 6.5 desvios padrões, levando a classificação no Regime Vermelho já no inicio do
período pelo motor HMM. Como se pode observar na @fig_hmm_gpa.

Já para a CBRDA8, assim como foi dito na @subcap_rkmeans, o EGARCH falhou em convergir no período _In-Sample_, fazendo com que a distribuição do regime Verde
ficasse larga e achatada. Ou seja, mesmo grandes variações para cima ou para baixo não eram suficientes para fazer o modelo sair do regime de baixo risco, 
porém, em Fev/2026, com o salto de _spread_ de 44% (de 45,7% para 100,0%, conforme a @tab_eventos_cbrda8), o motor HMM conseguiu identificar o choque e classificar 
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

Em relação aos resultados, pode se observar na @fig_ensemble_gpa que a probabilidade de classificação (_Ensemble Score_), apresentou estabilidade, quando comparada ao HMM, porém,
também falhou em capturar a deterioração observada para CBRDA8. Já no caso de CBRDB8, o modelo apresentou variações de estado frequentes, porém, foi capaz de antecipar o choque,
ao contrário do K-Means, porém de forma menos agressiva do que o HMM.

#figure(
  image("../imagens/13_estudo_caso_pão_de_açúcar_(gpa)_ensemble_prob.png", width: 90%),
  caption: [Resultados do Ensemble para o Estudo de Caso do Grupo Pão de Açúcar (GPA)]
) <fig_ensemble_gpa>

=== Antecipação de Eventos Sistêmicos (Lead Time)

A fim de fornecer o rigor quantitativo, evitando a dependência excessiva em um único estudo de caso, expandiu-se a avaliação direcional dos modelos para um rol mais abrangente de eventos de crédito observados no mercado 
corporativo brasileiro entre 2023 e 2026, porém, para evitar-se um detalhamento de todos os casos, que extenderiam em demasia este trabalho, optou-se pela seleção de alguns eventos específicos e análise menos detalhada 
do que a observada no estudo de caso especifico (Grupo Pão de Açúcar). A premissa central de um modelo de alerta precoce (_Early Warning_) é a capacidade de emitir sinalizações quando se inicia um regime de risco elevado (Regime Vermelho) 
com antecedência suficiente para permitir a liquidação defensiva do portfólio, métrica denominada _Lead Time_.

Através de uma comparação entre eventos recentes de deterioração de créditos e os resultados resultados dessa pesquisa, foram analisados 9 grandes eventos corporativos cujos ativos mantiveram liquidez 
secundária suficiente para a calibração *Out-of-Sample* dos modelos. A @tab_lead_time consolida a capacidade antecipatória de cada algoritmo ao registrar quantos dias antes do choque principal 
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

A análise da @tab_lead_time, calculada sob a premissa de estado de alerta contínuo, ou seja, o modelo entrou no estado vermelho e permaneceu até a data do evento sem sair do estado vermelho no período, demonstra empiricamente o valor preditivo que a
dependência temporal (matriz de Markov) adiciona à classificação. Ao desconsiderar períodos de instabilidade de regimes (uma vez que só consideramos períodos sem saídas do estado vermelho), o K-Means revelou-se ruidoso, demonstrando 
atrasos efetivos (como observado nos casos da Oi, Dasa e Multilaser). Com exceção da fraude da Lojas Americanas e da Recuperação Extrajudicial da Casas Bahia (onde todos os algoritmos falharam em manter o alerta ininterrupto), o HMM apresentou 
robustez preditiva superior. Para o caso da CVC Corp, o HMM foi capaz de sustentar o alerta de crise 78 dias antes do evento, enquanto o mapeamento geométrico (K-Means) sofreu de forte inércia, resultando em um atraso de 669 dias 
alcançar o estado vermelho de forma ininterrupta.

Adicionalmente, os resultados do _Ensemble_ demonstram que o K-Means frequentemente contamina a convicção do modelo. Conclui-se, portanto, que o HMM constitui veículo superior de proteção informacional para a liquidação defensiva de 
carteiras, quando consideramos apenas a capacidade de antecipação de alertas de forma ininterrupta até a deflagração do choque financeiro. Contudo, se considerarmos as regras operacionais definidas na metodologia do _Backtest_ (@subcap_kupiec_backtest), 
em que o portfólio adota um filtro de Quarentena Temporal: caso o modelo acuse Regime Vermelho, o ativo é sumariamente vendido e fica expressamente bloqueado para recompra por um período de 180 dias (6 meses), um sinal isolado (ainda que configure 
instabilidade matemática e não se mantenha ininterrupto até o choque) é suficiente para identificar a necessidade de saída do ativo, desde que ocorra dentro da janela de 180 dias que antecede o evento. A @tab_lead_time_operacional avalia o _Lead Time_ sob 
essa ótica puramente operacional: contabiliza-se a distância temporal entre o evento de crédito e o primeiro disparo vermelho registrado no semestre anterior.

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
na borda máxima do semestre. Independentemente da flexibilização operacional demonstrar a viabilidade dos alertas do K-Means e do Ensemble, o HMM manteve superioridade consistente — como evidenciado pela antecedência 
superior na Oi S.A. (57 dias) e Dasa (139 dias), demonstrando a superioridade da memória temporal na antecipação de alterações de regime.

== Simulação de Portfólio (Backtest Financeiro) <subcap_resultadosbacktest>

Para avaliação da utilidade econômica da modelagem desenvolvida, foi realizado um _backtest_ financeiro para o período _Out-of-Sample_, conforme descrito na @subcap_kupiec_backtest.
O objetivo da simulação não se limita a medir apenas o desempenho dos modelos propostos contra uma estratégia passiva (_Buy-and-Hold_), mas também a avaliar como as diferentes
formas de liquidação (preventiva no sinal amarelo _vs._ retardada no sinal vermelho) impactam a relação risco-retorno.

#figure(
  image("../imagens/backtest_pnl_portfolio.png", width: 90%),
  caption: [Resultados do Backtest]
) <fig_backtest_pnl_portfolio>

#figure(
  table(
    stroke: 0.5pt,
    columns: (1.5fr, 1fr, 1fr, 1fr, 1fr, 1fr),
    align: (left+horizon, center+horizon, center+horizon, center+horizon, center+horizon, center+horizon),
    [*Estratégia*], [*Retorno Total*], [_CAGR_], [*Volatilidade*], [_Máx. Drawdown_], [*Calmar Ratio*],
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

Os resultados consolidados na @tab_metricas_backtest e a evolução temporal da @fig_backtest_pnl_portfolio revelam o valor adicionado pelas estratégias de _Early Warning_. 
Enquanto o índice passivo (_Buy-and-Hold_) gerou um retorno total de 22,42% penalizado pelo carrego de papéis ilíquidos e depreciados, 
as estratégias reativas obtiveram retornos superiores, destacando-se a *K-Means Vende Amarelo* e *HMM Vende Amarelo* que apresentaram retornos acumulados de
36.18% e 32.62% respectivamente.

Optou-se pela exclusão da métrica clássica de _Sharpe Ratio_ dessa avaliação, uma vez que debêntures pós-fixadas (atreladas ao CDI) possuem correlação direta com a 
taxa de juros e volatilidade intrínseca artificialmente próxima a zero, o que distorce o índice na avaliação de prêmio de risco
 (tornando o Sharpe assintótico frente a prêmios negativos). Em seu lugar, as métricas utilizadas foram _Maximum Drawdown_ e
 *Calmar Ratio* (Razão do Retorno Anualizado (CAGR - _Compound Annual Growth Rate_) pelo _Maximum Drawdown_).

Apesar do retorno superior apresentado pelas estratégias ativas, elas também incorreram em maior volatilidade e _Drawdown_, sendo penalizadas quando avaliadas por métricas
que ponderam risco e retorno. Em especial, a estratégia *HMM (Vende Amarelo)* apresentou um expressivo _drawdown_ de -9,74% em 2026, originado pela marcação simultânea de diversos ativos no estado de Alerta (Amarelo)
em decorrência do contágio de crédito gerado pelo evento do grupo GPA. Por possuir uma regra agressiva de _stop loss_, o agente liquidou uma parcela relevante do portfólio
no mercado secundário exatamente no momento de forte abertura de _spreads_. Esse comportamento evidencia os riscos da sensibilidade acentuada do filtro Bayesiano quando combinado a uma execução automática.

O portfólio _Buy-and-Hold_ apresentou um Calmar de 1,249, sendo superado exclusivamente pelos algoritmos K-Means, com índices de 1,711 (Padrão) e 1,603 (Vende Amarelo). 
A superioridade do K-Means neste aspecto advém justamente da sua latência: por reagir de forma mais lenta e instável aos choques do que o HMM, a estratégia apresentou um menor giro de ativos. 
Dessa forma, ela evitou a realização maciça de prejuízos de marcação a mercado simultâneos (mitigando o _drawdown_), mas ainda assim conseguiu se desfazer tempestivamente de ativos que apresentavam deterioração irreversível, 
distanciando-se do _Buy-and-Hold_. Esse comportamento poupou a carteira das punições transacionais que afetaram o HMM.

Por fim, o modelo _Ensemble_ — desenvolvido com o intuito de harmonizar a reatividade do HMM com a inércia do K-Means — apresentou resultados negativos. Embora tenha sustentado um *Calmar Ratio* próximo
ao da estratégia passiva (1,111 _vs._ 1,249), entregou o menor retorno total do período (16,37%), corroído em grande parte pelo efeito _Whipsaw_ (efeito chicote). 
A mediação conflitante dos modelos fez com que o agente acionasse vendas quando o HMM indicava a transição de regime, para logo em seguida recomprar os mesmos ativos assim que a influência do K-Means puxava 
o _score_ novamente para um regime de baixo risco. Conclui-se, portanto, que a modelagem mista falhou estruturalmente ao herdar os custos transacionais da sensibilidade do HMM sem se beneficiar de sua capacidade 
de proteção definitiva, sofrendo das piores características operacionais de seus precursores.

=== Significância Estatística das Estratégias — Block Bootstrap

A superioridade das estratégias ativas em termos de retorno absoluto não é, por si só, evidência científica suficiente de que os modelos agregam valor. O período _Out-of-Sample_ (2023–2026) foi marcado por eventos excepcionais de crédito, 
o que levanta a questão: os retornos superiores observados decorrem da capacidade preditiva dos algoritmos, ou são produto de um período amostral específico?

Para responder a essa pergunta, aplicou-se o _Stationary Block Bootstrap_ #cite(<politis1994stationary>) com $n = 10.000$ amostras e blocos de 20 dias úteis (aproximadamente 1 mês), que preserva a estrutura de autocorrelação temporal 
dos retornos diários. A hipótese testada é:

- *H0₃*: A estratégia ativa *não* supera o Buy-and-Hold em termos de retorno médio anualizado ($mu_("estratégia") <= mu_("BnH")$).
- *H1₃*: A estratégia supera o Buy-and-Hold (teste unilateral à direita, $alpha = 5\%$).

O p-valor reportado representa a proporção de amostras bootstrap em que o retorno médio da estratégia foi inferior ou igual ao do benchmark, de forma que valores abaixo de 0,05 levam à rejeição de H0₃.

#figure(
  table(
    stroke: 0.5pt,
    columns: (2fr, 1fr, 1fr, 1fr, 1fr, 1fr),
    align: (left+horizon, center+horizon, center+horizon, center+horizon, center+horizon, center+horizon),
    [*Estratégia*], [*Retorno\ (%aa)*], [*BnH\ (%aa)*], [*Diferença\ (%aa)*], [*p-valor*], [*H0₃*],
    [KMeans], [6,97%], [5,87%], [+1,10%], [0,134], [NR],
    [HMM], [7,02%], [5,87%], [+1,15%], [0,225], [NR],
    [Ensemble], [4,47%], [5,87%], [-1,41%], [0,868], [NR],
    [*K-Means (Vende Amarelo)*], [*9,27%*], [*5,87%*], [*+3,40%*], [*0,015*], [*R*],
    [HMM (Vende Amarelo)], [8,90%], [5,87%], [+3,03%], [0,059], [NR],
    [Ensemble (Vende Amarelo)], [4,76%], [5,87%], [-1,11%], [0,808], [NR],
  ),
  caption: [Resultados do Block Bootstrap ($n=10.000$, $alpha=5\%$, bloco=20 dias) — Significância Estatística vs. Buy-and-Hold. \ *Nota*: R = Rejeitada; NR = Não Rejeitada.]
) <tab_bootstrap>

Os resultados do @tab_bootstrap revelam um achado central: *apenas a estratégia K-Means (Vende Amarelo) rejeita H0₃ ao nível de 5%* ($p = 0,015$, IC 95%: [+0,33%; +6,78%]). A estratégia HMM (Vende Amarelo) 
apresenta p-valor de 0,059, próximo ao limiar de significância, não rejeitando H0₃ sob o critério convencional de 5%, mas sugerindo evidência marginal de superioridade.

Este resultado é coerente com o diagnóstico do conhecido *Paradoxo da Acurácia-Rentabilidade* (_Accuracy-Profitability Paradox_)#footnote[Fenômeno documentado na literatura financeira quantitativa onde o aumento da acurácia preditiva de um modelo não se traduz, necessariamente, em retornos financeiros superiores, frequentemente devido ao impacto desproporcional dos custos transacionais decorrentes de falsos alarmes (_whipsaws_). No mercado de crédito corporativo, devido aos altos custos transacionais e restrições de liquidez, a menor sensibilidade reativa do K-Means (sua inércia na mudança de estado) atuou como um filtro natural de ruídos, resultando paradoxalmente em uma proteção de capital superior à entregue pelo modelo probabilístico de alta reatividade.]:
a inércia do K-Means, que aparentava ser uma deficiência preditiva (menor reatividade a mudanças de regime), transformou-se em vantagem financeira — ao evitar o excesso de giro e o efeito _Whipsaw_ que corrói os demais modelos. A estratégia HMM e as estratégias Ensemble, apesar dos retornos nominais 
superiores ao benchmark, não apresentam superioridade estatisticamente comprovável, evidenciando que seus ganhos estão dentro do intervalo de incerteza esperado para o período amostral específico, podendo a superioridade dos retornos no período ser apenas fruto do acaso.

#figure(
  image("../imagens/bootstrap_significance.png", width: 90%),
  caption: [Forest Plot — Diferença de Retorno vs. Buy-and-Hold com Intervalo de Confiança 95% (Block Bootstrap)]
) <fig_bootstrap>

=== Discussão sobre a Generalização dos Resultados

Os resultados apresentados neste estudo foram obtidos a partir de um conjunto específico de condições empíricas que delimitam sua generalização direta:

1. *Período amostral*: O período _Out-of-Sample_ (2023–2026) engloba uma das maiores crises de crédito privado brasileiro da história recente (com colapsos sequenciais de Lojas Americanas, Light S.A. e incertezas em torno do Grupo Pão de Açúcar). A eficácia das estratégias ativas, 
especialmente do K-Means (Vende Amarelo), foi alavancada pela necessidade de mitigação de risco no período. Em ciclos de expansão de crédito com baixa volatilidade, estratégias ativas, como as implementadas, podem apresentar performance inferior ao carrego passivo, devido ao peso dos 
custos transacionais.
2. *Universo de ativos*: A amostra final se restringe a debêntures com liquidez mínima suficiente para permitir a convergência do motor de estimação EGARCH. Ativos de crédito marcadamente ilíquidos — que operam fora da curva Anbima ou não possuem fluxo de negociação regular em mercado 
secundário — não foram testados. Estratégias aplicadas a essas carteiras podem sofrer distorções materiais.
3. *Estrutura de custos operacionais*: A simulação assumiu um custo de transação de 0,5% por operação, considerado aderente à média do mercado secundário corporativo. Contudo, em períodos de estresse extremo, o _bid-ask spread_ pode ser significativamente maior, inviabilizando as saídas 
defensivas simuladas nesta pesquisa.
4. *Frequência de Negociação*: Ao se utilizar dados de negócios realizados no mercado secundário (mitigando o viés de alisamento da marcação a mercado teórica), os indicadores preditivos tornam-se altamente dependentes do fluxo de liquidez.  Em momentos de estresse, a negociação de determinados ativos pode cessar, gerando indisponibilidade de dados do modelo no momento de maior necessidade.

Apesar das limitações inerentes à amostra brasileira e as características intrisecas do mercado de crédito, os alicerces metodológicos da arquitetura desenvolvida — como a integração da volatilidade condicional leptocúrtica como _feature_ para particionamento
 temporal dinâmico (_Time-Series Clustering_) — constituem um arcabouço que pode ser adaptado e generalizado para outros mercados globais de crédito privado caracterizados por informações assimétricas e baixa liquidez.
