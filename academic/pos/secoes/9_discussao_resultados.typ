= Discussão dos Resultados <sec_discussao_resultados>

A análise empírica avaliou a calibração econométrica das medidas de cauda e o retorno econômico obtido pelas regras de desinvestimento na carteira simulada de debêntures.

== Validação Estatística do Modelo de Risco

A acurácia do modelo EGARCH-t na estimação do Valor em Risco (VaR 99%) foi avaliada pelo Teste de Proporção de Falhas de Kupiec (POF) e pelo Teste de Cobertura Condicional de Christoffersen ($alpha = 0,05$) sobre 663 séries temporais no período _Out-of-Sample_ (2023 a 2026), universo que contempla as debêntures ativas do treino e novas emissões da janela. A @tab_validacao_cauda 
apresenta as taxas de aprovação empíricas e a sensibilidade do teste conjunto.

#figure(
  [
    #set text(size: 7.5pt)
    #set table(inset: (x: 3.5pt, y: 2pt))
    #table(
      stroke: 0.5pt,
      columns: (1.4fr, 0.6fr, 1.3fr, 1.3fr, 1.1fr, 1.1fr, 1.1fr),
      align: (left + horizon, center + horizon, center + horizon, center + horizon, center + horizon, center + horizon, center + horizon),
      table.header(
        table.cell(rowspan: 2, align: center + horizon)[*Indexador*],
        table.cell(rowspan: 2, align: center + horizon)[*Total*],
        table.cell(rowspan: 2, align: center + horizon)[*Kupiec POF\ ($alpha = 0,05$)*],
        table.cell(rowspan: 2, align: center + horizon)[*Independência\ ($alpha = 0,05$)*],
        table.cell(colspan: 3, align: center + horizon)[*Cobertura Condicional Conjunta (Christoffersen)*],
        [*$alpha = 0,10$ (90%)*], [*$alpha = 0,05$ (95%)*], [*$alpha = 0,01$ (99%)*],
      ),
      [CDI Percentual], [40], [21 (52,5%)], [39 (97,5%)], [21 (52,5%)], [23 (57,5%)], [25 (62,5%)],
      [CDI Spread], [257], [63 (24,5%)], [215 (83,7%)], [68 (26,5%)], [80 (31,1%)], [105 (40,8%)],
      [IPCA], [365], [133 (36,4%)], [330 (90,4%)], [143 (39,2%)], [157 (43,0%)], [193 (52,8%)],
      [Pré-Fixado], [1], [0 (0,0%)], [0 (0,0%)], [0 (0,0%)], [0 (0,0%)], [0 (0,0%)],
      [*Total Consolidado*], [*663*], [*217 (32,7%)*], [*584 (88,1%)*], [*232 (34,9%)*], [*260 (39,2%)*], [*323 (48,7%)*]
    )
  ],
  caption: [Validação de Cauda: Não-Rejeição de Kupiec e Christoffersen no Out-of-Sample (2023–2026).]
) <tab_validacao_cauda>

As taxas de rejeição da Hipótese Nula refletem a magnitude do estresse no mercado secundário doméstico entre 2023 e 2026, marcado pelas recuperações judiciais das Lojas Americanas e da Light S.A., além da reestruturação do Grupo Pão de Açúcar. No grupo 
CDI Percentual, a taxa de não-rejeição de 57,5% (ao nível de 5%) indica que o filtro autorregressivo acompanhou parte das mudanças de volatilidade do período. A baixa frequência de negociação constitui a principal causa de rejeições no teste POF devido a cotações 
esparsas que geram variações discretas de preço que ultrapassam o quantil de 99%. Todavia, o Teste de Independência de Christoffersen exibe não-rejeição de 88,1% no agregado (atingindo 97,5% no CDI Percentual e 90,4% no IPCA), indicando que as violações não ocorreram 
de forma agrupada no tempo (_volatility clustering_). Sob a distribuição t-Student adotada, o Expected Shortfall condicional é derivado analiticamente do mesmo quantil do VaR, compartilhando essa consistência estatística.

== Agilidade de Detecção e Antecipação de Choques (Lead Time)

A capacidade de antecipação temporal (_Lead Time_) foi avaliada a partir de nove episódios empíricos representativos de estresse corporativo ocorridos no mercado secundário doméstico durante a janela _Out-of-Sample_ (2023 a 2026). Estes eventos contemplam recuperações judiciais, 
recuperações extrajudiciais, reperfilamentos e quebras de _covenants_ (_waiver_), abrangendo emissores de diferentes portes e setores econômicos. A @tab_lead_time_consolidado sumariza as métricas de antecipação avaliadas sobre a premissa de emissão ininterrupta de alerta contínuo e 
execução tática orientada pela diretriz de quarentena de 180 dias úteis.

#figure(
  [
    #set text(size: 7pt)
    #set table(inset: (x: 2pt, y: 1.5pt))
    #table(
      stroke: 0.5pt,
      columns: (1.5fr, 0.5fr, 0.9fr, 0.7fr, 0.7fr, 0.7fr, 0.7fr, 0.7fr, 0.7fr),
      align: (left+horizon, center+horizon, center+horizon, center+horizon, center+horizon, center+horizon, center+horizon, center+horizon, center+horizon),
      table.header(
        table.cell(rowspan: 2, align: center + horizon)[*Empresa*],
        table.cell(rowspan: 2, align: center + horizon)[*Ev.*],
        table.cell(rowspan: 2, align: center + horizon)[*Máx.\ Spread*],
        table.cell(colspan: 3, align: center + horizon)[*Alerta Contínuo (dias)*],
        table.cell(colspan: 3, align: center + horizon)[*Quarentena 180d (dias)*],
        [*KM*], [*HMM*], [*Ens.*],
        [*KM*], [*HMM*], [*Ens.*],
      ),
      [Americanas], [RJ], [560,5%], [8 (AT)], [3 (AT)], [3 (AT)], [8 (AT)], [3 (AT)], [3 (AT)],
      [Oi S.A.], [RJ], [11,8%], [50 (AT)], [1 (AT)], [1 (AT)], [33 (AN)], [57 (AN)], [15 (AN)],
      [Light S.A.], [RJ], [120,9%], [3 (AN)], [5 (AN)], [5 (AN)], [102 (AN)], [118 (AN)], [77 (AN)],
      [CVC Corp], [RP], [21,0%], [669 (AT)], [78 (AN)], [78 (AN)], [669 (AT)], [149 (AN)], [149 (AN)],
      [Multilaser], [WV], [118,4%], [18 (AT)], [5 (AT)], [35 (AT)], [148 (AN)], [148 (AN)], [120 (AN)],
      [Dasa], [RP], [163,8%], [19 (AT)], [1 (AT)], [4 (AT)], [106 (AN)], [139 (AN)], [97 (AN)],
      [Unigel], [RE], [87,5%], [253 (AN)], [357 (AN)], [328 (AN)], [169 (AN)], [169 (AN)], [169 (AN)],
      [Casas Bahia], [RE], [56,1%], [F], [F], [F], [F], [F], [F],
      [Pão de Açúcar], [RE], [190,7%], [129 (AT)], [2 (AN)], [2 (AN)], [164 (AN)], [180 (AN)], [180 (AN)]
    )
  ],
  caption: [Resumo Comparativo de Lead Time em Eventos Corporativos. *Nota*: RJ/RE = Rec. Jud./Extrajud.; RP = Reperf.; WV = Waiver; AN = Antecipado; AT = Atraso; F = Falhou.]
) <tab_lead_time_consolidado>

Os resultados da @tab_lead_time_consolidado evidenciam diferentes comportamentos dos modelos conforme a velocidade de alteração no prêmio de risco do emissor. Em casos de perda progressiva de solvência, 
o HMM apresentou maior antecedência no alerta contínuo, antecipando o evento da Unigel em 357 dias úteis (frente a 253 dias do K-Means) e o da CVC Corp em 78 dias, intervalo no qual o K-Means registrou 
maior latência pela manutenção temporária do spread em patamar intermediário. Por outro lado, em reprecificações imediatas associadas a fatos relevantes não refletidos em cotações prévias, como nas Lojas 
Americanas (spread de 560,5%), ambos os modelos registraram atraso de 3 a 8 dias úteis, pois os preços observados antes do anúncio não embutiam prêmio de risco anormal. 

A inclusão da quarentena de 180 dias úteis alterou a dinâmica prática do desinvestimento. Como um único sinal preventivo basta para liquidar a posição e bloquear novas compras no ativo, o K-Means alcançou antecedências superiores a três meses em papéis como 
Light S.A. (102 dias), Multilaser (148 dias), Dasa (106 dias) e Pão de Açúcar (164 dias), reduzindo o giro de carteira. Por fim, no caso do Grupo Casas Bahia (spread de 56,1%), a falta de negócios no mercado secundário nos meses anteriores ao evento inviabilizou 
a atualização das probabilidades dos modelos, confirmando que a eficácia da abordagem depende de uma frequência mínima de negociação do ativo.

== Relação entre Acurácia Preditiva e Rentabilidade no Backtest Financeiro

Os resultados do backtest financeiro evidenciaram um contraste entre a rapidez na detecção de eventos e o retorno líquido acumulado (Accuracy-Profitability Paradox). A @fig_backtest_pnl exibe a evolução patrimonial e a @tab_metricas_backtest consolida as métricas de desempenho.

#figure(
  image("../imagens/backtest_pnl_portfolio.png", width: 50%),
  caption: [Curva de Retorno Acumulado das Estratégias no Backtest Out-of-Sample.]
) <fig_backtest_pnl>

#figure(
  [
    #set text(size: 7.5pt)
    #set table(inset: 2.2pt)
    #table(
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
    )
  ],
  caption: [Métricas de Risco-Retorno do Backtest Financeiro.]
) <tab_metricas_backtest>

As estratégias ativas superaram o portfólio passivo (_Buy-and-Hold_, 22,42%), com maiores retornos no K-Means Vende Amarelo (36,18%) e no HMM Vende Amarelo (32,62%). A avaliação priorizou o _Calmar Ratio_ e o _Maximum Drawdown_ em detrimento do Índice de Sharpe, por capturarem o impacto dos custos de transação. A estratégia HMM registrou rebaixamento patrimonial (_drawdown_) de -9,74% em 2026 devido a ordens defensivas disparadas por oscilações passageiras de mercado. O K-Means obteve os maiores índices de 
Calmar do período (1,711 no modelo base e 1,603 no Vende Amarelo), uma vez que sua menor sensibilidade a variações diárias evitou vendas em aberturas pontuais de spread e concentrou as saídas em ativos com deterioração 
prolongada. Já o modelo Ensemble apresentou o menor retorno acumulado (16,37%), reduzido pela incidência repetida de custos de transação nas alternâncias de sinal entre o HMM e o K-Means.

== Validação por Block Bootstrap

Para testar a hipótese nula de igualdade de retorno em relação ao _Buy-and-Hold_ ($H_0: Delta R <= 0$), aplicou-se o _Block Bootstrap_ estacionário de #cite(<politis1994stationary>, form: "prose") com 10.000 
reamostragens e comprimento médio de bloco de 20 dias úteis, dimensionado para preservar a dependência serial dos retornos diários. A @fig_bootstrap apresenta as distribuições empíricas de retorno excedente obtidas na simulação.

#figure(
  image("../imagens/bootstrap_significance.png", width: 36%),
  caption: [Distribuição do Retorno Excedente das Estratégias via Block Bootstrap.]
) <fig_bootstrap>

A regra K-Means Vende Amarelo apresentou p-valor de 0,0416, o que rejeita $H_0$ ao nível de 5% e mantém o limite inferior do intervalo de confiança de 95% acima de zero. Nas demais regras (K-Means Vende Vermelho, HMM e Ensemble), os p-valores 
ficaram acima de 0,10, uma vez que o número mais elevado de ordens aumentou a incidência do custo de 50 bps por operação e reduziu o retorno líquido acumulado. Esse resultado indica que o desempenho superior do K-Means Vende Amarelo 
no período analisado decorre do menor giro da carteira em conjunto com a quarentena de 180 dias úteis.
