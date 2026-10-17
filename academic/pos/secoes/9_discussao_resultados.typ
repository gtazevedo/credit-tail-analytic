= Discussão dos Resultados <sec_discussao_resultados>

A avaliação empírica investigou a eficácia dos modelos sob duas perspectivas complementares: a validação econométrica da cobertura de risco e a viabilidade financeira das decisões de investimento em ambiente simulado de mercado.

== Validação Estatística dos Motores de Risco

A acurácia do motor EGARCH-t na estimação do Valor em Risco (VaR 99%) foi testada por meio do Teste de Proporção de Falhas de Kupiec (POF) e do Teste de Cobertura Condicional de Christoffersen, adotando significância de 5% ($alpha = 0,05$).

A @tab_kupiec consolida os resultados do teste no período *Out-of-Sample* (2023 a 2026).

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

Os resultados refletem a gravidade da janela *Out-of-Sample*. Esse período concentrou eventos críticos de crédito corporativo, como as quebras das Lojas Americanas e da Light, seguidas 
pela forte reprecificação do Grupo Pão de Açúcar. A @fig_kupiec exibe a sensibilidade das taxas de aprovação do teste conjunto frente a diferentes níveis de significância estatística.

#figure(
  image("../imagens/kupiec_approval_rate.png", width: 80%),
  caption: [Sensibilidade da Não-Rejeição no Teste Conjunto a Diferentes Níveis de Confiança.]
) <fig_kupiec>

A taxa de não-rejeição conjunta supera a cobertura incondicional isolada em todos os indexadores. O modelo EGARCH-t absorveu satisfatoriamente a dependência temporal da variância, impedindo 
o agrupamento de violações (*volatility clustering*). As exceções observadas decorrem de dias esparsos sem negócios seguidos de reprecificações discretas de cotação.

== Agilidade de Detecção e Antecipação de Choques (Lead Time)

Para avaliar a capacidade dos algoritmos de antecipar choques de crédito, analisaram-se casos reais de estresse corporativo ocorridos na janela de teste. Destaca-se o caso das debêntures CBRDA8 e 
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

== O Paradoxo da Acurácia-Rentabilidade no Backtest Financeiro

Apesar da superioridade analítica demonstrada pelo HMM na antecipação de alertas (*Lead Time*), os resultados do *backtest* financeiro revelaram uma dicotomia entre acurácia 
preditiva teórica e ganho financeiro líquido. Trata-se do conhecido "Paradoxo da Acurácia-Rentabilidade" (*Accuracy-Profitability Paradox*).

A @fig_backtest_pnl exibe a curva de patrimônio líquido acumulado das estratégias táticas contra a carteira passiva (*Buy and Hold*).

#figure(
  image("../imagens/backtest_pnl_portfolio.png", width: 90%),
  caption: [Curva de Retorno Acumulado das Estratégias no Backtest Out-of-Sample.]
) <fig_backtest_pnl>

A estratégia orientada pelo K-Means com liquidação preventiva (*Vende Amarelo*) entregou o maior retorno financeiro absoluto do período, alcançando 36,18% de rentabilidade acumulada 
contra 32,84% do benchmark passivo (*Buy and Hold*). Foi a única abordagem capaz de superar o mercado passivo.

A causa econômica dessa assimetria reside no impacto dos custos operacionais de negociação. Em mercados com liquidez restrita e spread bid-ask dilatado (modelado em 0,5% por transação), 
a alta sensibilidade do HMM gerou excesso de rotatividade (*turnover*). O modelo acionou vendas preventivas seguidas de recompras precipitadas diante de falsos alarmes transitórios, corroendo o carrego acumulado da carteira.

Em contrapartida, a inércia do K-Means funcionou como um filtro natural contra o ruído secundário. O modelo manteve as debêntures em carteira durante oscilações passageiras de volatilidade, 
liquidando posições apenas quando as distâncias geométricas indicaram distorções consistentes. Essa ineficiência preditiva converteu-se, paradoxalmente, em proteção patrimonial.

O modelo Ensemble apresentou o pior desempenho do período. A mescla de sinais provocou o efeito chicote (*whipsaw*): o portfólio realizava vendas impulsionadas pela reatividade do HMM e 
executava recompras tardias sob a inércia do K-Means, maximizando o pagamento de custos operacionais.

== Validação por Block Bootstrap

Para verificar se a rentabilidade superior do K-Means (*Vende Amarelo*) reflete habilidade tática genuína ou mero acaso amostral, aplicou-se a técnica de *Block Bootstrap* estacionário com 
10.000 repetições e blocos temporais de 20 dias úteis, seguindo a formulação para séries financeiras dependentes desenvolvida por #cite(<politis1994stationary>). O procedimento preserva a 
dependência temporal e a autocorrelação residual da carteira dentro de cada bloco reamostrado.

A @fig_bootstrap apresenta a distribuição empírica dos retornos excedentes gerados pela reamostragem.

#figure(
  image("../imagens/bootstrap_significance.png", width: 85%),
  caption: [Distribuição do Retorno Excedente das Estratégias via Block Bootstrap.]
) <fig_bootstrap>

A estratégia K-Means Vende Amarelo registrou p-valor de $0,0416$ ($p < 0,05$), com intervalo de confiança a 95% estritamente positivo em relação ao *Buy and Hold*. Todas as demais estratégias 
registraram p-valores superiores a 0,10, não rejeitando a hipótese de igualdade de desempenho frente ao mercado passivo. O resultado atesta que a disciplina de venda preventiva com filtro de inércia 
agrega valor financeiro verificável sob atritos operacionais realistas.
