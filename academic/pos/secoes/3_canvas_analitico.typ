#pagebreak(weak: true)
= Canvas Analítico <sec_canvas_analitico>

Apresenta-se o Canvas Analítico do projeto, estruturado em doze blocos estratégicos que sintetizam a formulação do problema, as bases de dados, 
as técnicas estatísticas aplicadas e os resultados esperados.

#v(0.2cm)

#let card(title, content) = block(
  stroke: 0.7pt + rgb(170, 190, 215),
  radius: 4pt,
  inset: (x: 8pt, y: 7pt),
  width: 100%,
  height: 4.2cm,
  fill: rgb(250, 252, 255),
  [
    #text(size: 8.5pt, weight: "bold", fill: rgb(15, 45, 95))[#title] \
    #v(4pt)
    #set text(size: 7.2pt)
    #set par(leading: 0.45em, justify: true, first-line-indent: 0pt)
    #content
  ]
)

#grid(
  columns: (1fr, 1fr, 1fr),
  column-gutter: 6pt,
  row-gutter: 5pt,
  
  card("1. Problema de Negócio", [
    Baixa liquidez e assimetria de retornos no mercado secundário de debêntures. Modelos tradicionais de risco (GARCH contínuo e VaR paramétrico) têm baixa aderência diante de saltos discretos e deságios acentuados em eventos de cauda.
  ]),
  card("2. Objetivo Analítico", [
    Classificar regimes latentes de risco de crédito (Verde, Amarelo e Vermelho) e antecipar choques patrimoniais por meio de aprendizado de máquina não supervisionado com modelagem temporal.
  ]),
  card("3. Justificativa", [
    Atrasos na detecção de deterioração de crédito dificultam a venda de posições em mercados pouco líquidos. Alertas antecipados reduzem perdas antes do agravamento do evento de crédito.
  ]),

  card("4. Stakeholders", [
    Gestores de fundos de crédito privado, analistas de risco corporativo, comitês de alocação de ativos e tesourarias institucionais.
  ]),
  card("5. Variável-alvo (Target)", [
    Regime latente de risco de crédito do ativo, classificado em Verde (Baixo Risco), Amarelo (Alerta) e Vermelho (Crise).
  ]),
  card("6. Variáveis de Entrada", [
    Delta Spread diário, Taxa ajustada ao prazo ($S_t / ln("DU")$), Volatilidade condicional EGARCH-t, Expected Shortfall (99%) e Z-Score móvel de 60 dias.
  ]),

  card("7. Fontes de Dados", [
    Prévias públicas de negociação do sistema REUNE da ANBIMA, dados cadastrais via portal Debentures.com.br e séries macroeconômicas (CDI e IPCA) obtidas do Banco Central do Brasil por meio do pacote `python-bcb`.
  ]),
  card("8. Técnicas Estatísticas / ML", [
    AR(1)-EGARCH(1,1)-t para volatilidade assimétrica; K-Means com agregação Borda Count; Gaussian HMM com regularização de Laplace e algoritmo de Viterbi; Ensemble ponderado.
  ]),
  card("9. Métricas de Avaliação", [
    Validação estatística pelos testes de Kupiec POF e Christoffersen, combinada à avaliação financeira pelo Lead Time de antecipação, retorno acumulado líquido e p-valor via Block Bootstrap.
  ]),

  card("10. Entregáveis", [
    Pacote Python modular (`credit_tail_analytics`), pipeline de dados automatizado, base histórica tratada, relatórios analíticos de backtest e repositório de código aberto.
  ]),
  card("11. Impacto Esperado", [
    Mitigação de perdas acentuadas em eventos de estresse corporativo, contenção de custos de transação pelo filtro de ruído e retorno superior ao portfólio passivo (Buy and Hold) validado por teste estatístico.
  ]),
  card("12. Restrições e Riscos", [
    Escassez de negociações diárias na maioria dos ativos, principalmente em períodos de estresse, custos operacionais de giro (50 bps) e alternância excessiva entre estados (flickering).
  ])
)

#pagebreak(weak: true)
