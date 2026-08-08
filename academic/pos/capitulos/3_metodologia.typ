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
Abaixo será detalhada a metodologia aplicada em cada etapa. Para facilitar a compreensão sistêmica, a @fig_pipeline ilustra a arquitetura global do *pipeline*, desde a coleta de dados e divisão temporal até o processamento nos motores estocásticos e a simulação final (*Backtest*).

#import "@preview/diagraph:0.3.2": raw-render

#figure(
  raw-render(
```dot
digraph G {
    rankdir=TB;
    node [shape=box, style=rounded, fontname="Arial"];
    
    anbima [label="Dados ANBIMA"];
    macro [label="Dados Macro"];
    pre [label="Pré-Processamento\n& Filtro de Liquidez"];
    is [label="Treinamento (IS)"];
    oos [label="Backtest (OOS)"];
    egarch [label="Motor EGARCH-t\n(Volatilidade)"];
    kmeans [label="K-Means\n(Topológico)"];
    hmm [label="HMM\n(Temporal)"];
    ensemble [label="Ensemble Misto\n(EMA 3 dias)"];
    backtest [label="Estratégias de Liquidação\n(Defesas de Re-entrada)"];
    resultado [label="Performance vs BnH", shape=box, peripheries=2];

    anbima -> pre;
    macro -> pre;
    pre -> is [label=" In-Sample"];
    pre -> oos [label=" Out-of-Sample"];
    is -> egarch;
    egarch -> kmeans;
    egarch -> hmm;
    kmeans -> ensemble;
    hmm -> ensemble;
    ensemble -> backtest;
    oos -> backtest;
    backtest -> resultado;
}
```
  ),
  caption: [Arquitetura do Pipeline de Risco e Backtest]
) <fig_pipeline>



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

Como resultado da otimização, o subconjunto eleito como vencedor combinou as variáveis `Taxa_ZScore`, `Volatilidade_EGARCH` e `Expected_Shortfall_99`. A @fig_feature_selection ilustra o Top 10 das combinações avaliadas, ordenadas pelo *Borda Score*, evidenciando o 
desempenho superior do trio escolhido na capacidade de particionamento latente.

#figure(
  image("../imagens/feature_selection_ranking.png", width: 90%),
  caption: [Top 10 Subconjuntos de Variáveis classificados pelo método de Borda Count.]
) <fig_feature_selection>

Uma forma mais ludica de observar o desempenho superior dessas variáveis, é realizar a comparação de forma multidimensional, a @fig_feature_radar 
ilustra o desempenho das quatro principais combinações normalizado nos três eixos de avaliação (Coesão, Dispersão e Separação). O gráfico demonstra 
graficamente como a combinação vencedora consegue maximizar simultaneamente o *Silhouette Score* e o *Calinski-Harabasz*, enquanto minimiza o índice de 
*Davies-Bouldin*.

#figure(
  image("../imagens/feature_selection_radar.png", width: 90%),
  caption: [Comparação Multidimensional das métricas de particionamento (Min-Max Scaled).]
) <fig_feature_radar>

Na @fig_feature_radar, o conjunto dado pelas variáveis `Taxa_ZScore`, `Volatilidade_EGARCH` e `Expected_Shortfall_99` e o conjunto dado pelas variáveis `Taxa_ZScore`, `Volatilidade_EGARCH` e `VaR_99`
parecem ter um desempenho muito similar, mas quando observamos a @fig_feature_selection, o primeiro conjunto possui um score superior. A única diferença entre eles é a substituição
do Expected Shortfall pelo VaR, porém, o Expected Shortfall possui um score superior em todas as métricas, apesar de ser visualmente dificil a identificação na @fig_feature_radar.
Além disso, como foi abordado em @cap_revisao_lit o Expected shortfall é uma métrica superior, pois enquanto o VaR responde a pergunta "Qual é a perda máxima que posso esperar com 99% de confiança?", 
o Expected Shortfall responde a pergunta "Qual é a perda média que posso esperar quando o VaR for excedido?". Além disso, diferentemente do VaR, o Expected Shortfall é uma medida de risco
coerente, o que o torna uma métrica superior.

=== K-Means <subcap_kmeans>

Eleitas as variáveis de entrada do modelo (`Taxa_ZScore`, `Volatilidade_EGARCH` e `Expected_Shortfall_99`), o algoritmo K-Means atua como uma *baseline* atemporal.
O processo é realizado iterativamente para cada grupo de indexador (ex: DI, IPCA), a fim de respeitar as dinâmicas particulares de cada mercado.

O primeiro passo é a separação da amostra de treino e teste (*In-Sample* para treino, *Out-of-Sample* para teste), conforme detalhado em @subcap_processamento.
Para garantir que *outliers* extremos (como casos que discutimos nas seções anteriores, em que ativos passam dias sem negociação e depois quando voltam a ser negociados
apresentam saltos no spread), aplica-se uma Winsorização (clipagem) no 1º e 99º percentis utilizando os dados *In-Sample*. Esses limites são posteriormente aplicados aos dados
*Out-of-Sample*, prevenindo o viés de antecipação de informação (*look-ahead bias*).

Em seguida, os dados são padronizados através do algoritmo `RobustScaler`. Para capturar o risco relativo de cada papel, o escalonamento é 
feito individualmente por ativo, possuindo como limitador inferior 10% da variância (IQR) global do indexador, evitando que ativos estruturalmente ilíquidos 
sofram explosões numéricas. Já, que, uma vez o *RobustScaler* é dado por:

$ "Scaled"(x) = (x - Q_2(x)) / (Q_3(x) - Q_1(x)) $

Caso o IQR ($Q_3(x) - Q_1(x)$) seja nulo ou próximo de zero, o escalonamento se torna indefinido.

O K-Means é então treinado nos dados padronizados com $k=3$ agrupamentos. Devido à natureza não-supervisionada do K-Means (o problema do *Label Switching*), 
os centróides gerados recebem rótulos arbitrários. O modelo resolve este problema através de um vetor de polaridade de risco (onde valores maiores de volatilidade e 
*Z-Score* implicam maior risco), ordenando as médias dos agrupamentos para classificar deterministicamente os regimes em Verde (baixo risco), Amarelo (alerta) e Vermelho (crise). 

Na etapa preditiva, para a construção de um modelo misto ponderado (conforme será abordado em @subcap_modelo_misto), a probabilidade de crise (`Prob_Crise_KMeans`) é definida 
com base na distância euclidiana inversa de cada observação 
*Out-of-Sample* até o centróide Vermelho.

=== HMM <subcap_hmm>

O Modelo Oculto de Markov (HMM - *Hidden Markov Model*) acrescenta a dependência temporal que o K-Means ignora. O pré-processamento para o HMM segue as exatas mesmas premissas 
de divisão, winsorização e padronização geométrica (piso de variância) descritas em @subcap_kmeans, adicionando apenas a restrição de que a massa de dados obedeça estritamente a 
ordenação sequencial no tempo. Já que para o HMM, essa ordanação é de extrema importância para que o modelo consiga modelar as transições entre os estados latentes.

O treinamento *In-Sample* é realizado através de um HMM Gaussiano (`GaussianHMM`) de 3 estados latentes com matriz de covariância diagonal, aplicando o 
algoritmo de otimização de *Baum-Welch*. Da mesma forma, os vetores de médias estimadas para as emissões Gaussianas sofrem a correção heurística de *Label Switching* 
para rotular os estados como Verde, Amarelo e Vermelho.

Uma alteração fundamental feita no HMM padrão diz respeito à calibração da Matriz de Transição de Estados ($A$). Em bases de dados com regimes muito duradouros, pode haver a total ausência empírica de transições entre estados extremos (como saltos diretos de Verde para Vermelho) na amostra de treinamento. 
Isso gera probabilidades de transição iguais a zero, 
transformando os regimes em "estados absorventes" (uma vez que o modelo entre nesse estado, a probabilidade de sair matematicamente se anula). Para mitigar esse problema, aplicou-se primeiramente a *Suavização de Laplace* (*Additive Smoothing*) sobre a matriz empírica de contagens de transição:

$ P'_{i j} = (C_{i j} + alpha) / ( sum_{k=1}^K C_{i k} + K alpha ) $ <eq_laplace_hmm>

onde $C_{i j}$ é a contagem empírica de transições do estado $i$ para o estado $j$ observadas na sequência latente decodificada do *In-Sample*, $K=3$ é o número de estados, e $alpha = 1$ atua como o pseudo-fator aditivo. 

Complementarmente à equação @eq_laplace_hmm, para garantir matematicamente que o modelo permaneça reativo aos novos choques de mercado em tempo real e não dependa excessivamente da inércia do estado anterior, 
impôs-se um limiar (piso) arbitrário de 1% ($0.01$) sobre a matriz de probabilidade de transição, seguido por uma re-normalização linha a linha (para assegurar que o somatório das probabilidades convirja para 1):

$ P''_{i j} = max(P'_{i j}, 0.01) $
$ P_{i j} = P''_{i j} / (sum_{k=1}^K P''_{i k}) $ <eq_hmm_piso>

Esse mecanismo em duas etapas força o modelo a manter vias probabilísticas ativas e o impede de tornar-se inerte, especialmente para a saída do estado de crise (Vermelho).

A inferência nos dados *Out-of-Sample* é rigorosamente desenhada para evitar viés do futuro. Para estimar a probabilidade de um ativo estar em crise no dia $t$, 
o modelo recebe apenas a sequência de variáveis observáveis do instante inicial até o instante $t$ (janela expansiva causal). A sequência ótima de estados latentes é decodificada utilizando o *Algoritmo de Viterbi*, 
e a probabilidade marginal instantânea de crise (`Prob_Crise_HMM`) é inferida simultaneamente pelo algoritmo *Forward-Backward*.


=== Modelo Misto (Ensemble) <subcap_modelo_misto>

As predições individuais do K-Means (detalhada em @subcap_kmeans) e do HMM (detalhada em @subcap_hmm) são posteriormente combinadas em uma pontuação final, 
buscando mesclar a estabilidade atemporal do particionamento geométrico (K-Means) com a agilidade e memória temporal do 
filtro bayesiano (HMM).

A combinação matemática é realizada através de uma média ponderada das probabilidades individuais de cada modelo,
sendo os pesos definidos *a priori*. Atribui-se um peso de 70% a probabilidade do modelo HMM devido a premissa de que
o mercado e os agentes nele inseridos possuem memoria e inercia, ou seja, conseguem reagir de forma mais rápida a choques
que tragam informações sobre um possível evento de cauda. Os 30% restantes foram atribuidos ao modelo K-Means, atuando como uma
âncora temporal de estabilidade, tentando reduzir as varias oscilações observadas no HMM. A equação do *Ensemble* no instante $t$ é dada por:

$ "Probabilidade Sintética"_t = 0.70 times "Prob_Crise_HMM"_t + 0.30 times "Prob_Crise_KMeans"_t $ 

Por fim, para garantir uma combinação mais suave e menos suscetível a ruídos de alta frequência, aplicou-se um filtro de 
média móvel exponencial de 3 dias ($"EMA"_3$) sobre a "Probabilidade Sintética", gerando a pontuação final de risco. A fórmula 
da Média Móvel Exponencial é calculada recursivamente da seguinte forma:

$ "Pontuação Final"_t = alpha times "Probabilidade Sintética"_t + (1 - alpha) times "Pontuação Final"_{t-1} $

onde $alpha$ é o fator de suavização, definido por $alpha = 2 / (N + 1)$. Para uma janela de $N=3$ dias, o fator 
resulta em $alpha = 0.5$. Dessa forma, a "Pontuação Final" de risco absorve os choques recentes rapidamente, 
mas preserva a memória de curto prazo para evitar que a volatilidade diária acione alarmes falsos de crise.

== Protocolos de Validação (Kupiec POF e Backtest)

Para testar a robustez e a aplicabilidade prática do modelo desenvolvido, a etapa de validação foi estruturada em duas 
dimensões complementares, aplicadas sobre o período *Out-of-Sample* para garantir a ausencia de viés prospectivo
(*Look-Ahead Bias*). A primeira dimensão avaliada diz respeito a acurácia estatistica do modelo, aplicada sobre
as saídas do motor EGARCH-t. Foi utilizado o Teste de Proporção de Falhas (*POF - Proportion of Failures*) desenvolvido por 
#cite(<kupiec1995techniques>, form: "prose"), que avalia se a frequência empírica de violações (quantidade de dias em que a perda
real do ativo excedeu a perda máxima estimada pelo VaR) é estatisticamente compatível com o nível de confiança estipulado
pelo modelo. Rejeitar a hipótese nula do teste indica que o motor de volatilidade subestima ou superestima
sistematicamente as caudas pesadas observadas no mercado.

A segunda dimensão avalia a qualidade preditiva do modelo no contexto do mercado de crédito corporativo brasileiro por meio
de um *Backtest* financeiro, focado em avaliar a eficácia dos diferentes "Regimes de Risco" sugeridos pelos modelos apresentados.
O *backtest* simula o impacto de diferentes estratégias de liquidação de portfólio baseadas nas pontuações de risco dos modelos
(Verde, Amarelo ou Vermelho), comparando duas abordagens de liquidação para cada modelo:

  - Venda Retardada: Estratégia reativa, onde a liquidação ocorre quando o modelo acusa um Regime de Risco Vermelho. Idealmente, 
  caso o modelo seja capaz de prever o estado vermelho antes do choque, esse modelo deveria gerar rentabilidade superior, uma vez
  que a venda ocorre antes ou no exato momento do choque, evitando assim perdas substanciais. Todavia, se o modelo não for capaz de
  prever o estado vermelho antes do choque, essa estratégia tende a gerar perdas operacionais, uma vez que o choque já ocorreu
  e a venda só será realizada após a materialização dos choques no preço dos ativos.
  - Venda Preventiva: Estratégia ofensiva, onde a liquidação ocorre quando o modelo acusa um Regime de Risco Amarelo. Idealmente,
  deveria ser superada pela venda retardada em caso de um modelo ideal, porém, na prática, em cenários onde o modelo pode demorar
  a reagir na classificaçao para o regime vermelho, essa estratégia tende a gerar rentabilidade superior, uma vez que a venda 
  ocorre assim que são observados os primeiros sinais de deterioração do ativo, antes da materialização completa do choque. Todavia,
  caso hajam muitos falsos positivos, essa estratégia tende a gerar rentabilidade inferior à venda retardada, uma vez que gera custos
  operacionais desnecessários e reduz o ganho em cenários de alta volatilidade.

Para tornar a simulação o mais realista possível e capturar a penalidade financeira do *whipsaw* (falsos rompimentos que geram múltiplos sinais de entrada e saída), o *backtest* incorpora uma taxa de custo de transação de 0,5% (50 *bps*). No mercado secundário de crédito brasileiro, caracterizado por menor liquidez e *spreads* de *bid-ask* mais elásticos do que o mercado de ações, a inclusão desse custo é fundamental. Ele atua como um fator de desconto sobre estratégias excessivamente reativas (com alta rotatividade/*turnover*), testando assim o real valor econômico agregado pelos sinais preditivos contra os custos operacionais de executá-los na prática.

O resultado das estratégias táticas é comparado contra o desempenho passivo de um portfólio *Buy-and-Hold*. Para assegurar o rigor técnico e a reprodutibilidade da simulação financeira, 
o algoritmo do *backtest* foi estruturado sob as seguintes premissas operacionais:

- *Carteira Inicial:* No primeiro dia útil da janela *Out-of-Sample*, o capital inicial é distribuído de forma equiponderada (*equal-weight*) entre todas as debêntures elegíveis disponíveis na base de dados naquela data.
- *Regra de Venda (Liquidação):* A liquidação ocorre integralmente no momento em que o modelo classifica o ativo no regime de *stop* estipulado pela estratégia (seja "Vermelho" na estratégia retardada, ou "Amarelo/Vermelho" na preventiva). O capital obtido pela venda é deduzido do custo de transação de 0,5% e mantido em caixa.
- *Remuneração de Caixa:* Qualquer montante não alocado em debêntures (caixa livre) é remunerado diariamente pela taxa DI (CDI) histórica real correspondente ao dia da simulação, refletindo o custo de oportunidade livre de risco (*risk-free*). E tentando simular o que ocorreria na realidade,
porque um fundo ou uma pessoa fisica alocaria esse dinheiro em um CDB-DI com liquidez diária ou fundo de zeragem, por exemplo.
- *Regra de Recompra:* Para evitar re-entradas prematuras (*dead cat bounces*) e a corrosão da rentabilidade pelo excesso de giro, o capital em caixa é redistribuído igualitariamente apenas entre ativos que 
atendam simultaneamente aos três filtros:
  1. *Quarentena Temporal:* O ativo não pode ter estado em um regime de alerta/crise nos últimos 180 dias (6 meses).
  2. *Inércia de Estabilidade:* O ativo deve permanecer ininterruptamente no regime "Verde" por pelo menos 15 dias úteis, confirmando o fim da volatilidade.
  3. *Filtro de Payback:* O prêmio de risco anualizado do ativo no instante da compra deve ser matematicamente suficiente para recuperar o pedágio do custo de transação em, no máximo, 3 meses. A condição de elegibilidade é formalizada pela seguinte restrição:

  $ "Spread Mínimo" = c times 12 / M $ <eq_filtro_payback>

  onde $c$ é a taxa do custo de transação (0,5%) e $M$ é o período máximo tolerado de *payback* em meses ($M=3$). Se a taxa (*spread*) ofertada pela debênture for inferior a este limite mínimo (neste caso, 2,0% ao ano), a compra é abortada, visto que o spread comprimido não justifica o risco operacional e financeiro do giro de portfólio.

Essa arquitetura algorítmica de simulação garante que a performance do modelo preditivo não seja um mero artefato teórico, testando a viabilidade de seus sinais diretamente contra as restrições operacionais e os atritos do mercado corporativo brasileiro.
