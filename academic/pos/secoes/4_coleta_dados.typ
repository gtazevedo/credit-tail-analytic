= Coleta de Dados <sec_coleta_dados>

A modelagem de risco em ativos de crédito privado exige dados de negociação transparentes e livres de estimativas puramente teóricas. Para construir a base empírica 
desta pesquisa, foram integradas três fontes primárias de informação pública: os registros diários de transações do mercado secundário, as características cadastrais 
de cada instrumento emitido e as séries históricas macroeconômicas de taxas de juros e inflação.

Os dados transacionais de negociação foram extraídos da plataforma da Associação Brasileira das Entidades dos Mercados Financeiro e de Capitais (ANBIMA), a partir do 
sistema REUNE (Prévias Públicas de Negociação de Instrumentos Financeiros). A série histórica compreende o intervalo entre 2 de janeiro de 2018 e 10 de julho de 2026. O 
histórico abrange 2.112 dias úteis. As rotinas automatizadas de raspagem (_web scraping_) e os módulos de unificação dos arquivos diários encontram-se disponíveis 
no #link("https://github.com/gtazevedo/credit-tail-analytic")[repositório público do projeto].

As características cadastrais das debêntures foram obtidas por meio de consultas programáticas ao portal Debentures.com.br e ao ANBIMA Data, utilizando o pacote `debentures_dot_com` 
(de autoria própria). Essa base contém atributos estruturais de cada papel, como código do emissor, data de emissão, data de repactuação, data de vencimento final, 
indexador contratual, tipo de garantia e volume total emitido.

As séries macroeconômicas de referência (taxa DI diária, taxa Selic e índices de inflação IPCA e IGP-M) foram coletadas diretamente do Sistema Gerenciador de Séries Temporais 
(SGS) do Banco Central do Brasil, utilizando o pacote `python-bcb` #cite(<freitaspythonbcb>). O cruzamento entre os registros de negociação e os dados macroeconômicos 
viabilizou computar uma aproximação dos prêmios de risco e das variações de spread.

== Dicionário de Dados

A base consolidada resultante unifica os registros de negociação, cadastrais e macroeconômicos. A @tab_dicionario_dados descreve os principais atributos utilizados nas etapas 
de saneamento e modelagem.

#figure(
  table(
    stroke: 0.5pt,
    columns: (1.5fr, 3fr, 1fr),
    align: (left + horizon, left + horizon, center + horizon),
    [*Nome do Atributo*], [*Descrição*], [*Tipo*],
    [`data`], [Data de referência do pregão de negociação], [Date],
    [`ticker`], [Código de negociação do ativo na CETIP/B3 (ex.: CBRDA8)], [String],
    [`taxa_min`], [Menor taxa anual de spread negociada no dia para o ativo], [Float],
    [`taxa_med`], [Taxa média ponderada anual negociada no pregão], [Float],
    [`taxa_max`], [Maior taxa anual de spread negociada no dia para o ativo], [Float],
    [`pu_min`], [Menor preço unitário praticado na sessão de negócios], [Float],
    [`pu_med`], [Preço unitário médio observado no dia], [Float],
    [`pu_max`], [Maior preço unitário praticado na sessão de negócios], [Float],
    [`faixa_volume`], [Classificação de liquidez ANBIMA (Faixas 1, 2 e 3)], [String],
    [`indexador`], [Indexador contratual da emissão (DI+, IPCA+, Pré)], [String],
    [`du_vencimento`], [Dias úteis restantes até a data de vencimento do papel], [Integer],
    [`cdi_anual`], [Taxa média diária anualizada do CDI divulgada pelo BACEN], [Float],
    [`delta_spread`], [Primeira diferença do spread de crédito diário], [Float],
    [`taxa_prazo`], [Spread anualizado ajustado pelo logaritmo do prazo útil], [Float]
  ),
  caption: [Dicionário de Atributos da Base Consolidada de Negociação de Debêntures.]
) <tab_dicionario_dados>

== Análise pela Técnica dos 5-Ws

Para sintetizar as informações apresentadas sobre os dados, elaborou-se um resumo considerando a metodologia dos 5-Ws:

- *(_Why?_) Por que os dados são importantes:* As cotações de negócios efetivos refletem o prêmio de risco real exigido pelo mercado. Elas eliminam a ficção de modelos que assumem continuidade de preços em ativos ilíquidos, expondo os momentos exatos em que ocorrem deságios severos.
- *(_Who?_) Qual a origem dos dados:* Informações públicas auditadas e divulgadas pela ANBIMA (sistema REUNE), portal Debentures.com.br e Banco Central do Brasil.
- *(_What?_) O que é analisado:* Preços unitários, taxas de spread negociadas, prazos até o vencimento e volumes negociados de debêntures corporativas, confrontados com as taxas livres de risco da economia.
- *(_Where?_) Qual a cobertura geográfica:* Mercado financeiro doméstico brasileiro, contemplando emissores de dívida corporativa atuantes no território nacional.
- *(_When?_) Qual o período analisado:* Intervalo contínuo entre janeiro de 2018 e julho de 2026. Essa janela foi dividida em duas etapas metodológicas: período de treinamento (_In-Sample_, 2018 a 2022) e período de validação e teste (_Out-of-Sample_, 2023 a 2026).
