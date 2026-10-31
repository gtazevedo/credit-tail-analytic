= Coleta de Dados <sec_coleta_dados>

A modelagem de risco necessita de dados observados de negociação, em especial em crédito privado, para evitar preços teóricos marcados na curva, uma vez que as cotações de negócios
efetivos refletem o prêmio de risco praticado no mercado, reduzem a dependência de premissas de continuidade de preços em ativos pouco líquidos e registram os pregões em que 
ocorrem descontos relevantes nas cotações. A base empírica unifica três fontes públicas nacionais, compreendendo as transações do mercado secundário de debêntures extraídas do sistema REUNE da ANBIMA 
(2.112 pregões entre 02/01/2018 e 10/07/2026), características cadastrais obtidas via portal Debentures.com.br e ANBIMA Data (pacote `debentures_dot_com`), e séries macroeconômicas diárias 
(taxa DI, Selic e inflação IPCA) coletadas via API do Banco Central do Brasil (`python-bcb`) #cite(<freitaspythonbcb>).

As séries utilizadas possuem preços unitários, taxas de spread negociadas, prazos até o vencimento e volumes negociados de debêntures corporativas, confrontados com as taxas livres 
de risco da economia em um intervalo contínuo entre janeiro de 2018 e julho de 2026, que foi dividido em duas etapas metodológicas, sendo a primeira o período de treinamento (_In-Sample_, 2018 a 2022) 
e a segunda o período de validação e teste (_Out-of-Sample_, 2023 a 2026).

== Dicionário de Dados

A base consolidada unifica registros de negociação, cadastro e macroeconômicos. A @tab_dicionario_dados descreve os atributos utilizados nas etapas de tratamento e modelagem.

#block(
  fill: rgb(248, 250, 252),
  stroke: 0.5pt + rgb(210, 220, 230),
  inset: 4pt,
  radius: 3pt,
  width: 100%,
  [
    #set text(size: 8pt)
    #set par(leading: 0.32em, first-line-indent: 0pt)
    *Nome do dataset:* Base Consolidada de Negociação de Debêntures e Séries Macroeconômicas \
    *Descrição:* Registros de negócios secundários (ANBIMA REUNE), dados cadastrais (Debentures.com.br) e indicadores do BACEN (SGS). \
    *Link:* #link("https://github.com/gtazevedo/credit-tail-analytic")[https://github.com/gtazevedo/credit-tail-analytic]
  ]
)

#figure(
  [
    #set text(size: 7.5pt)
    #set table(inset: 2.2pt)
    #table(
      stroke: 0.5pt,
      columns: (1.5fr, 3fr, 1fr),
      align: (left + horizon, left + horizon, center + horizon),
      [*Nome do Atributo*], [*Descrição*], [*Tipo*],
      [`data`], [Data de referência do pregão de negociação], [Date],
      [`ticker`], [Código de negociação do ativo na CETIP/B3 (ex.: CBRDA8)], [String],
      [`taxa_min/med/max`], [Taxas anualizadas de spread mínima, média e máxima praticadas no dia], [Float],
      [`pu_min/med/max`], [Preços unitários mínimo, médio e máximo observados no pregão], [Float],
      [`faixa_volume`], [Classificação de liquidez ANBIMA (Faixas 1, 2 e 3)], [String],
      [`indexador`], [Indexador contratual da emissão (DI+, IPCA+, Pré)], [String],
      [`du_vencimento`], [Dias úteis restantes até a data de vencimento do título], [Integer],
      [`cdi_anual`], [Taxa média diária anualizada do CDI divulgada pelo BACEN], [Float],
      [`delta_spread`], [Primeira diferença do spread de crédito diário], [Float],
      [`taxa_prazo`], [Spread anualizado ajustado pelo logaritmo do prazo útil], [Float]
    )
  ],
  caption: [Dicionário de Atributos da Base Consolidada de Negociação de Debêntures.]
) <tab_dicionario_dados>
