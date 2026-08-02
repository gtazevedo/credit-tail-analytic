= Metodologia e Dados <cap_metodologia>

A análise do risco de crédito das debentures requer uma coleta extensa de dados e analise rigorosa de sua qualidade para que o modelo implementado seja acurado e capaz
de capturar as nuances desejadas. Este capítulo detalha os procedimentos que foram adotados para a coleta, tratamento e análise dos dados. Além dos modelos e validações
aplicados neste estudo.

Uma vez que o estudo será disponibilizado juntamente dos códigos-fonte utilizados para sua implementação, todos os procedimentos detalhados abaixo podem ser replicados pelo leitor
de forma independente. Para facilitar a reprodução, as funções utilizadas em cada etapa serão citadas, a fim de auxiliar a coomprensão do leitor. Os detalhes sobre a utilização de
cada função e da ferramenta como um todo poderão ser encontrados na documentação do projeto disponível no #link("https://github.com/gtazevedo/credit-tail-analytic")[repositório do GitHub].

== Coleta e Tratamento de Dados (ANBIMA) <subcap_coleta_dados>

Os dados base de spread por debenture e dia, que alimentam essa pesquisa foram extraidos do site da ANBIMA, mais especificamente na seção de Prévias Públicas de Negociação de Instrumentos Financeiros,
que pertence ao sistema REUNE. O período da amostra foi do segundo dia de janeiro de 2018 a 10 de julho de 2026. Os dados extraidos diários possuem as seguintes colunas:
Codigo Cetip, Tipo, Agrupamento, Taxa Mínima, Taxa Média, Taxa Máxima, Preço Mínimo, Preço Médio, Preço Máximo e Faixa de Volume.
O leitor pode replicar esse download por meio da classe `data.anbima_scraper.AnbimaScraper`; para maior comodide tambem se pode utilizar `data.run_scraper_full.rodar_extracao` e 
posteriormente `data.unify_csvs.unify_csvs`, uma vez que o download gera um arquivo csv por dia de consulta.

Já as informações cadastrais foram obtidas na página #link("https://www.debentures.com.br")[Debentures.com.br] (que será substituida pelo #link("https://data.anbima.com.br/")[ANBIMA Data]) por meio de consulta utilizando o pacote `debentures_dot_com`. As informações 
obtidas são referentes a emissão das debentures e incluem informações como: Ticker, Indexador, Data de Emissão, Data Vencimento, Empresa, CNPJ, Emissão, Situação, Classe, Garantia, Quantidade Emitida,
Quantidade Mercado, Taxa Emissão, Motivo de Saida, entre outras; para mais informações sobre os campos citados ou campos disponíveis consultar a página do #link("https://data.anbima.com.br/")[ANBIMA Data] e/ou o
pacote `debentures_dot_com`. O leitor pode replicar esse download por meio da função `data.build_cadastro.build_cadastro_mestre`.

As informações macroeconomicas (CDI, Selic, IPCA Mensal e 12M e IGPM Mensal) foram extraidas utilizando o pacote `python-bcb`. O leitor pode replicar esse download por meio
da função `data.download_macro.download_macro_data`, que é uma aplicação direta do pacote de #cite(<freitaspythonbcb>, form: "prose") para as variaveis de interesse para a pesquisa.

Na etapa de pré-processamento, mais detalhada em @subcap_processamento, foi realizada a normalização e tratamento das variáveis. Como a base de dados extraída da ANBIMA abrange múltiplos indexadores (como IPCA+, DI+ e % do CDI), 
foi necessário separar esse grupos treinar e aplicar o modelo de forma independente,
criando uma instância de modelagem por indexador, 
conforme será detalhado nas sessões seguintes,
uma vez que os papéis de diferentes indexadores possuem comportamento de risco distintos, assim como distinta sensibilidade a variação da taxa. 

Como citado em @cap_introducao, um desafio inerente ao mercado secundário de crédito privado brasileiro é a baixa liquidez dos ativos, inclusive com alguns chegando a possuir
dias sem negociação. A ANBIMA classifica o volume de negociação em faixas, sendo a faixa mais baixa dada por "Até 1MM", e portanto, dado as informações possuídas na realização dessa pesquisa,
esses são os ativos definidos como ilíquidos. No código implementado, desenvolveu-se uma rotina de tratamento governada pela flag `filter_low_liquidity`. Quando habilitada, 
essa rotina remove da base de dados para treinamento (que será detalhada posteriormente), os ativos que permaneceram como iliquidos durante um período igual ou superior a 95% da amostra.
O propósito dessa funcionalidade é impedir que, caso sejam observados
eventos de variação de spread expurios, devido a baixa liquidez, eles não sejam propagados para o modelo EGARCH, o que poderia corromper a estimação da persistência e dos choques 
(parâmetros $alpha$ e $beta$) da variância condicional. É importante notar que esses ativos foram removidos apenas da amostra de teste, com a exceção de RDVT11, que foi removido manualmente da amostra
devido aos seguintes fatores:
- O ativo não tinha dados de negociação durante a etapa de treinamento, então seria considerado posteriormente, mesmo iliquido.
- A série de preços do ativo apresenta grandes variações, com um espaçamento elevado entre os dados, o que pode introduzir vieses na estimação.
    - Em 05/12/2023 o ativo foi negociado com PU de 1001.77, sendo negociado novamente apenas em 20/03/2024 com PU de 1.40 e posterio em 21/03/2024 com PU de 0.000014. Voltando a ser negociado em 26/07/2024 com PU de 38.04 e em 28/02/2025 com PU de 754.31.
- A empresa passou por eventos de reestruturação e recuperação judicial

A principio, a empresa deveria ser um exemplo de evento que o modelo deveria prever, porém, devido ao espaçamento irregular de marcações e a falta de liquidez, ocorrem inconsistencias expurias, que serão mais detalhadas posteriormente. Também serão mostrados os 
resultados obtidos quando o ativo é mantido na amostra, para efeitos de comparação.

== O Pipeline de Risco (EGARCH, K-Means e HMM)

Para a implementação dos modelos, foi criado um *pipeline* de risco, que, através de um fluxo linear estima as variáveis de maior impacto para o modelo, realiza o cálculo do volatilidade,
VaR e *Expected Shortfall* (ES) por papel e, por fim, aplica o algoritmo K-Means e o Modelo Oculto de Markov (HMM). Uma vez obtdos os resultados do K-Means e HMM, se gera um modelo
*Ensemble*, ponderando os resultados de cada modelo. Para mais detalhes sobre o funcionamento do *pipeline*, consultar a documentação do projeto disponível no #link("https://github.com/gtazevedo/credit-tail-analytic")[repositório do GitHub].
Abaixamos será detalhado a metodologia aplicada em cada etapa.

=== Pré-processamento de Dados e Filtros <subcap_processamento>

Os dados coletados em @subcap_coleta_dados foram divididos em dois períodos *In-Sample* e *Out-of-Sample*, sendo o período *In-Sample*, iniciado em janeiro de 2018 até dezembro de 2022
 utilizados para a seleção e estimação dos parametros dos modelos e o período *Out-of-Sample*, iniciado em janeiro de 2023 até julho de 2026, utilizado para a implementação, observação e validação dos modelos,
 incluindo a avaliação do modelo em eventos de crédito realizado como o Grupo Pão de Açúcar, amplamente citado nessa pesquisa, devido a suas proporções e ao fato de ter sido o evento mais recente, dado o momento em que 
 este trabalho foi escrito.

 Além disso, as variáveis obtidas na etapa @subcap_coleta_dados foram utilizadas como base para o cálculo de outras métricas. Para papéis indexados a um percentual do CDI 
(ex: 120% do DI), foi realizada uma conversão explícita baseada na taxa CDI anualizada (extraída via `python-bcb`). 
A transformação anualiza o fator diário do título e extrai o prêmio absoluto sobre a taxa livre de risco, conforme abaixo:
$ F_"cdi" = (1 + "CDI"_t / 100)^(1/252) $
$ F_"titulo" = (F_"cdi" - 1) times ("Taxa do Ativo"_t / 100) + 1 $
$ S_t = ( (F_"titulo")^252 - 1 ) times 100 - "CDI"_t $

Para os títulos atrelados a índices de inflação (como IPCA, IGPM) ou por um prêmio direto sobre o DI (DI Spread), a própria taxa informada no secundário já reflete o prêmio de risco 
puro:
$ S_t = "Taxa do Ativo"_t $. 

A partir dessa informação, foi calculado a variação diária do *spread* (*Delta Spread*), que atua como o principal input para o ajuste temporal do modelo EGARCH.

$ Delta S_t = S_t - S_(t-1) $

Devido a indisponibilidade de dados suficientes para o cálculo de duration se utilizou como base a quantidade de dias úteis para o vencimento do papel (limitado ao minimo de dois dias), para calcular a taxa ajustada ao prazo, conforme abaixo:

$ "Taxa"_"prazo" = S_t / ln(max("DU", 2))$

Foi tambem calculado o z-score do spread, utilizando uma janela móvel de 60 dias, além do *Spread Range Intraday* e *Spread Skew Intraday*, dados respectivamente por:

$S_("range") = "Taxa do Ativo"_"max" - "Taxa do Ativo"_"min"$


$S_("skew") = ("Taxa do Ativo" - "Taxa do Ativo"_"min") / (S_("range") + epsilon)$

Sendo $epsilon = 1e-6$ para evitar divisão por zero. A implementação desses cálculos é realizada de maneira estruturada na classe `DataPreprocessor`.

=== EGARCH <subcap_egarch>

Apesar do viés teórico discutido em @cap_revisao_lit, para se optar pelo modelo EGARCH, foram testados vários modelos da familia GARCH em um modelo de torneio de *grid-search*, para
diferentes tamanhos de amostra. O torneio avaliou os dados a partir de 2018 até o fim de 2022, que foi o período utilizado para treinamento do modelo, sendo o período a partir de 2023
o período de validação dos resultados, conforme detalhado em @subcap_processamento. O código listou todos os ativos e filtrou os 30, 50, 100, 500, 1000, 3000, 5000 mais líquidos do período.

Para cada um dos ativos selecionados, o otimizador testou um grid combinatório de 32 especificações da familia GARCH (utilizando o pacote `arch`). Os hiperparâmetros iterados foram:
- Média Condicional: Fixada em um modelo Autorregressivo de ordem 1 (AR(1)).
- Famílias de Volatilidade: GARCH tradicional, EGARCH (exponencial), GJR-GARCH (assimétrico) e TARCH.
- Defasagens (Lags) $p$: 1 e 2 (Impacto da variância passada).
- Defasagens (Lags) $q$: 1 e 2 (Impacto dos choques correntes).
- Distribuição dos Resíduos: Normal e t-Student.

A variável de entrada, conforme detalhado em @subcap_processamento foi o *Delta Spread*. Para cada combinação de modelo e ativo foi calculado o Critério de Informação de Akaike (AIC) e então para cada papel o modelo escolhido
foi aquele que apresentou menor valor de AIC, cada vez que o modelo foi eleito foi considerado uma vitória. Ao final foi calculado a taxa média de vitórias de cada modelo e eleito aquele que apresentou um maior percentual de vitórias. Matematicamente, a taxa de vitória $W_j$ de um modelo $j$ é dada por:

$ W_j = (sum_{i=1}^N I_(i, j)) / N times 100 $

onde $N$ é o número total de ativos avaliados e $I_(i, j)$ é uma função indicadora que assume valor $1$ se o modelo $j$ apresentar o menor AIC para o ativo $i$ (ou seja, $"AIC"_(i, j) = min_k "AIC"_(i, k)$), e $0$ caso contrário. 

Adotou-se o modelo que maximizou $W_j$, garantindo a escolha empírica do algoritmo que melhor se adapta à maior proporção do mercado de crédito. Para amostras pequenas o destaque foi o modelo EGARCH(2,1,1) utilizando a distribuição t-student, porém, a partir de 
100 amostras, o EGARCH(1,1,1) com a distribuição t-student passou a apresentar uma maior taxa de vitórias, como se pode observar nas figuras abaixo:

#figure(
  image("../imagens/comparacao_modelos_ranking_n30_True.png", width: 90%),
  caption: [Torneio GARCH: Ranking Médio para a amostra dos 30 ativos mais líquidos.]
) <fig_ranking_30>

#figure(
  image("../imagens/comparacao_modelos_ranking_n100_True.png", width: 90%),
  caption: [Torneio GARCH: Ranking Médio para a amostra dos 100 ativos mais líquidos.]
) <fig_ranking_100>

#figure(
  image("../imagens/comparacao_modelos_ranking_n5000_True.png", width: 90%),
  caption: [Torneio GARCH: Ranking Médio para a amostra ampla de 5000 ativos.]
) <fig_ranking_5000>

Além disso, nas @fig_ranking_100, @fig_ranking_5000 podemos observar que apesar do EGARCH(1,1,1) com a distribuição t-student apresentar maior taxa de vitórias, o GARCH(1,0,1) com a distribuição t-student apresentou melhor rank médio no teste. Esse resultado é,
de certa forma, esperado, uma vez que para debentures liquidas que não possuem grandes choques, o GARCH, como visto em @cap_revisao_lit tem alto poder preditivo em condições de normalidade, enquanto o EGARCH pode ser penalizado pela tentativa de estimar 
assimetria (e parametros a mais quando comparamos apenas as versões supra citadas), uma vez que o AIC penaliza modelos que possuem parâmetros extras caso eles não tragam ganhos de aderência significativos. Contudo, nos papéis que passam por mais eventos de estresse,
é esperado que o EGARCH performe melhor, por ser capaz de capturar assimetrias, além da heterocedasticidade condicional. O que poderia justificar os resultados observados.

Como o intuito dessa pesquisa é estudar justamente os casos de estresse, e não a dinâmica da normalidade, foi adotado o modelo que apresentou maior *Win Rate*, e não aquele que apresentou o melhor rank médio. Essa escolha é justificada pelo fato de que,
desejamos possuir o modelo que possui maior taxa de acertos, em detrimento da otimização de parâmetros, o que também justifica a escolha do AIC como métrica principal em detrimento do BIC, que possui maior 
penalização por parâmetros extras, favorecendo modelos mais simples. Além disso, o EGARCH modela a variancia em escala logarítmica, o que garante que a variancia seja sempre positiva, diferentemente do GARCH tradicional.

Após a eleição do EGARCH(1,1,1) com distribuição t-Student como o motor principal de volatilidade condicional, foram aplicados testes de diagnóstico aos resíduos gerados por este modelo para atestar sua qualidade estatística:

1. *Ljung-Box (Lag 10)*: Para confirmar a ausência de autocorrelação serial remanescente, atestando que a média condicional AR(1) foi bem especificada.
2. *ARCH-LM (Lag 10)*: O teste do multiplicador de Lagrange (Lagrange Multiplier) para verificar se toda a heterocedasticidade condicional foi devidamente absorvida pela variância EGARCH, impossibilitando a persistência do efeito ARCH nos resíduos.

Como a modelagem GARCH é realizada univariadamente (ativo a ativo), ajustou-se o modelo campeão para o universo viável de debêntures do período de teste, totalizando uma amostra de 529 debêntures. 
Este número representa a quantidade de debentures na amostra utilizada para o período que preencheram simultaneamente os critérios de elegibilidade: 
alta liquidez (exclusão de dias com volume "Até 1MM"), convergência numérica no otimizador de máxima verossimilhança e um histórico contínuo mínimo de 50 observações válidas. 
Os testes de hipótese foram aplicados aos resíduos de cada um dos ativos, considerando um nível de significância de 5%.

Os resultados demonstram um excelente grau de aderência do modelo ao mercado de crédito secundário brasileiro. 
Conforme ilustrado na @fig_diagnostico_residuos, 86,4% dos papéis modelados passaram no teste de Ljung-Box e 94,9% dos ativos passaram no teste ARCH-LM. 
A aprovação no teste ARCH-LM evidencia que o modelo EGARCH é adequado para a maioria das debêntures analisadas.

#figure(
  image("../imagens/diagnostico_residuos_egarch.png", width: 85%),
  caption: [Taxa de aprovação dos testes de diagnóstico nos resíduos padronizados do EGARCH(1,1,1) t-Student para 529 debêntures.]
) <fig_diagnostico_residuos>

Para mais detalhes a respeito dessa implementação, consultar o script `diagnostico_residuos.py` e a classe `ValidadorEconometrico`.

Uma vez definido e implementado o modelo EGARCH(1,1,1) com distribuição t-Student, a distribuição estimada para cada ativo foi utilizada também para o cálculo do Valor em Risco (VaR) e Expected Shortfall (ES) (com percentil de
99%, que foram atribuidos as variaveis `VaR_99` e `Expected_Shortfall_99`, respectivamente) como forma de precificar o risco das debentures
analisadas baseado na série de volatilidade estimada. Como a distribuição escolhida para os resíduos foi a t-student, se $nu <= 2$ então a variancia da distribuição se torna infinita, levando a erros numericos no python quando se tenta calcular o VaR e ES,
para evitar tais erros, foi aplicado um limite nos graus de liberdade, de forma que $nu$ sempre será maior que 2.05, matematicamente, temos que o tratamento aplicado foi:

$ nu = max(2.05, nu_("est")) $

Onde $nu_("est")$ é o valor estimado pelo modelo EGARCH(1,1,1). Além disso, durante a estimação da volatilidade, foram encontrados alguns problemas de otimização devido a instabilidade de algumas séries, principalmente as que permanecem dias sem negociação e quando
são negociadas apresentam "saltos" no spread. Como o intuito do modelo é uma classificação de warning, aplicou-se uma limitação na volatilidade calculada, de forma que caso o EGARCH estime um valor que seja 20 vezes maior que o percentil 99% da volatilidade 
observada do ativo, estimada pelo desvio padrão, o valor é removido da amostra e replica-se a volatilidade observada no dia anterior, matematicamente, temos que o tratamento aplicado foi:

$ sigma_("est")(t) = sigma_("est")(t-1) quad "se" quad sigma_("est")(t) > v_("teto") $

onde $sigma_("est")(t)$ é a volatilidade estimada pelo modelo EGARCH(1,1,1) no dia $t$, e $v_("teto")$ é o limite superior definido como 20 vezes o percentil 99 da série in-sample. Para mais detalhes a respeito dessa implementação, consultar o script
`volatility.py` e a classe `VolatilityEstimator`.

=== Seleção de variáveis

Nas seções @subcap_processamento e @subcap_egarch foram listadas as variáveis calculadas: 
- Taxa_ZScore
- Volatilidade_EGARCH
- VaR_99
- Expected_Shortfall_99
- Spread_Equivalente
- Spread_Range_Intraday
- Spread_Skew_Intraday

Estas variáveis foram utilizadas como um input para um processo de seleção de variáveis, que eligiu as mais relevantes para utilização nos modelos propostos. Devido a natureza não supervisionada desses modelos, a determinação da relevância dessas variáveis
não pode ser realizada através dos métodos usuais que são utilizados para os processos de aprendizado supervisionado. Por essa razão, a seleção de variáveis implementada realiza combinações iterativas por meio de um *Grid Search* sobre subconjuntos das 
variáveis candidatas utilizando os dados de treinamento (*In-Sample*). Com intuito de garantir significado econômico aos clusters, a variável `Taxa_ZScore` foi mantida como obrigatória em todas as combinações. Impedindo que o algoritmo selecione apenas
variáveis de risco correlacionadas (como a volatilidade EGARCH e o VaR), o que não agregaria valor discriminatório aos clusters, devido a carencia da preficicação relativa ao spread de crédito.

Para cada subconjunto testado, os dados foram padronizados utilizando  *RobustScaler* devido a sua capacidade de lidar com outliers, conforme apresentado em @cap_revisao_lit. Os subconjuntos foram então submetidos a uma clusterização primára utilizando K-Means
com $k=3$ regimes. A qualidade de separabilidade de cada agrupamento foi mensurada através de três métricas:

1. *Silhouette Score* (#cite(<rousseeuw1987>, form: "prose")): Mede a coesão intra-cluster frente à separabilidade inter-cluster, variando no intervalo $[-1, 1]$. Nesta métrica, valores maiores indicam melhor adequação, ou seja, valores próximos a 1 
sugerem clusters perfeitamente densos e bem separados, enquanto valores próximos a 0 ou negativos indicam forte sobreposição.
2. *Índice Davies-Bouldin* (#cite(<davies1979cluster>, form: "prose")): Avalia a razão média da dispersão interna do cluster pela distância euclidiana entre os centróides, penalizando sobreposições. Diferente do Silhouette, nesta métrica valores menores indicam melhor adequação, pois 
um índice menor (com limite inferior tendendo a zero) significa que os clusters são compactos internamente e distantes uns dos outros.
3. *Índice Calinski-Harabasz* (#cite(<calinski1974dendrite>, form: "prose")): Mensura a razão entre a variância inter-cluster e a variância intra-cluster, ponderada pelos graus de liberdade do sistema. Para este índice, valores maiores indicam melhor adequação, 
denotando que a distância entre os centros dos clusters é expressivamente maior que a dispersão dos pontos dentro de cada regime.

Uma vez que as métricas atuam em ordens de grandeza e domínios matemáticos distintos, o subconjunto vencedor não é escolhido por médias absolutas, mas sim pelo método de agregação de Ranks de Borda (*Borda Count*). 
O algoritmo computa a posição de cada combinação no ranking individual de cada métrica. O *Borda Score* final é dado pela soma das posições invertidas, garantindo uma eleição ordinal, determinística e robusta às magnitudes isoladas de índices específicos.

=== K-Means



=== HMM


== Protocolos de Validação (Kupiec POF e Backtest)
Lorem ipsum dolor sit amet, consectetur adipiscing elit.
