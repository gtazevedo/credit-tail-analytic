= Metodologia e Dados <cap_metodologia>

A análise do risco de crédito das debentures requer uma coleta extensa de dados e analise rigorosa de sua qualidade para que o modelo implementado seja acurado e capaz
de capturar as nuances desejadas. Este capítulo detalha os procedimentos que foram adotados para a coleta, tratamento e análise dos dados. Além dos modelos e validações
aplicados neste estudo.

Uma vez que o estudo será disponibilizado juntamente dos códigos-fonte utilizados para sua implementação, todos os procedimentos detalhados abaixo podem ser replicados pelo leitor
de forma independente. Para facilitar a reprodução, as funções utilizadas em cada etapa serão citadas, a fim de auxiliar a compreensão do leitor. Os detalhes sobre a utilização de
cada função e da ferramenta como um todo poderão ser encontrados na documentação do projeto disponível no #link("https://github.com/gtazevedo/credit-tail-analytic")[repositório do GitHub].

== Coleta e Tratamento de Dados (ANBIMA) <subcap_coleta_dados>

Os dados base de _spread_ por debênture e dia de negociação, que alimentam essa pesquisa foram extraidos do site da ANBIMA, mais especificamente na seção de Prévias Públicas de Negociação de Instrumentos Financeiros,
que pertence ao sistema REUNE. O período da amostra foi do segundo dia de janeiro de 2018 a 10 de julho de 2026. Os dados diários extraidos possuem as seguintes colunas:
Codigo Cetip, Tipo, Agrupamento, Taxa Mínima, Taxa Média, Taxa Máxima, Preço Mínimo, Preço Médio, Preço Máximo e Faixa de Volume.
O leitor interessado em reproduzir esta coleta de dados pode consultar as rotinas de raspagem de dados (_web scraping_) e os _scripts_ de unificação disponibilizados no repositório público desta pesquisa no #link("https://github.com/gtazevedo/credit-tail-analytic")[GitHub], 
uma vez que o download gera um arquivo csv por dia de consulta.

Já as informações cadastrais foram obtidas na página #link("https://www.debentures.com.br")[Debentures.com.br] (que será substituida pelo #link("https://data.anbima.com.br/")[ANBIMA Data]) por meio de consulta utilizando o pacote `debentures_dot_com`
(mantido pelo autor desse trabalho). As informações 
obtidas são referentes a emissão das debentures e incluem informações como: Ticker, Indexador, Data de Emissão, Data Vencimento, Empresa, CNPJ, Emissão, Situação, Classe, Garantia, Quantidade Emitida,
Quantidade Mercado, Taxa Emissão, Motivo de Saida, entre outras; para mais informações sobre os campos citados ou campos disponíveis consultar a página do #link("https://data.anbima.com.br/")[ANBIMA Data] e/ou o
pacote `debentures_dot_com`. A rotina automatizada para o cruzamento destas informações cadastrais também encontra-se documentada no repositório do projeto.

As informações macroeconomicas (CDI, Selic, IPCA Mensal e 12M e IGPM Mensal) foram extraidas utilizando o pacote `python-bcb`. O leitor pode replicar esse download por meio
da aplicação direta do pacote de #cite(<freitaspythonbcb>, form: "prose") para as variaveis de interesse, cujos _scripts_ constam no repositório do projeto.

Na etapa de pré-processamento, mais detalhada na @subcap_processamento, foi realizada a normalização e tratamento das variáveis. Como a base de dados extraída da ANBIMA abrange múltiplos indexadores (como IPCA+, DI+ e % do CDI), 
foi necessário separar esses grupos para treinar e aplicar o modelo de forma independente,
criando uma instância de modelagem por indexador, 
conforme será detalhado nas sessões seguintes,
uma vez que os papéis de diferentes indexadores possuem comportamento de risco distintos, assim como distinta sensibilidade a variação da taxa. 

Como citado na @cap_introducao, um desafio inerente ao mercado secundário de crédito privado brasileiro é a baixa liquidez dos ativos, inclusive com alguns chegando a possuir
dias sem negociação. A ANBIMA classifica o volume de negociação, no sistema de informações consultado, em faixas, sendo a faixa mais baixa dada por "Até 1MM", e portanto, dado as informações possuídas na realização dessa pesquisa,
esses são os ativos definidos como ilíquidos. Para lidar com essa característica, desenvolveu-se uma rotina algorítmica de tratamento, que, quando habilitada, 
remove da base de dados para treinamento (que será detalhada posteriormente em @subcap_processamento), os ativos que permaneceram como iliquidos durante um período igual ou superior a 95% da amostra.
O propósito dessa funcionalidade é impedir que, caso sejam observados
eventos de variação de _spread_ espúrios, devido a baixa liquidez, eles não sejam propagados para o modelo EGARCH, o que poderia corromper a estimação da persistência e dos choques 
(parâmetros $alpha$ e $beta$) da variância condicional. É importante notar que esses ativos foram removidos apenas da amostra de teste, com a exceção de RDVT11, que foi removido manualmente da amostra
devido aos seguintes fatores:
- O ativo não tinha dados de negociação durante a etapa de treinamento, então seria considerado posteriormente, mesmo iliquido.
- A série de preços do ativo apresenta grandes variações, com um espaçamento elevado entre os dados, o que pode introduzir vieses na estimação.
    - Em 05/12/2023 o ativo foi negociado com PU de 1001.77, sendo negociado novamente apenas em 20/03/2024 com PU de 1.40 e posterio em 21/03/2024 com PU de 0.000014. Voltando a ser negociado em 26/07/2024 com PU de 38.04 e em 28/02/2025 com PU de 754.31.
- A empresa passou por eventos de reestruturação e recuperação judicial

A princípio, a empresa deveria ser um exemplo natural de evento de _tail risk_ que o modelo deveria prever. Contudo, devido ao espaçamento temporal irregular de marcações a mercado e à extrema escassez de liquidez, 
as séries de retorno tornaram-se puramente espúrias, o que pode comprometer severamente a convergência do estimador de máxima verossimilhança do motor EGARCH, além disso, como o ativo permanece durante o periodo
_Out-of-Sample_, ele seria considerado no _backtest_, gerando PnLs espurios. Por esse motivo, a exclusão sumária deste ativo da amostra 
final foi necessária para preservar a integridade estatística da modelagem e coerencia dos resultados observados.

== O Pipeline de Risco (EGARCH, K-Means e HMM)

Para a implementação dos modelos, foi criado um _pipeline_ de risco, que, através de um fluxo linear estima as variáveis de maior impacto para o modelo, realiza o cálculo do volatilidade,
VaR e _Expected Shortfall_ (ES) por papel e, por fim, aplica o algoritmo K-Means e o Modelo Oculto de Markov (HMM). Uma vez obtidos os resultados do K-Means e HMM, se gera um modelo
_Ensemble_, ponderando os resultados de cada modelo. Abaixo será detalhada a metodologia aplicada em cada etapa. 
Para facilitar a compreensão sistêmica, a @fig_pipeline ilustra a arquitetura global do _pipeline_, desde a coleta de dados e divisão temporal até o processamento nos motores estocásticos e a simulação final (_Backtest_).

#import "@preview/diagraph:0.3.2": raw-render

#figure(
  pad(bottom: 1.5em,
    raw-render(
```dot
digraph G {
    rankdir=TB;
    node [shape=box, style=rounded, fontname="Arial"];
    
    anbima [label="Dados ANBIMA"];
    macro [label="Dados Macro"];
    pre [label="Pré-Processamento\n& Filtro de Liquidez"];
    egarch [label="Motor EGARCH-t\n(Filtro de Volatilidade)"];
    
    is [label="Amostra In-Sample\n(2018 - 2022)"];
    oos [label="Amostra Out-of-Sample\n(2023 - 2026)"];
    
    kmeans_train [label="Treino K-Means\n(Validação k=3)"];
    hmm_train [label="Treino HMM\n(Gaussiano)"];
    grid [label="Grid-Search Ensemble\n(Otimização de Pesos)"];
    
    kmeans_pred [label="Predição K-Means"];
    hmm_pred [label="Predição HMM"];
    ensemble [label="Ensemble Misto\n(70% HMM / 30% KMeans)"];
    
    backtest [label="Backtest Financeiro\n(Estratégias de Liquidação)"];
    resultado [label="Performance vs BnH", peripheries=2];

    anbima -> pre;
    macro -> pre;
    pre -> egarch [label=" Toda a Série"];
    
    egarch -> is;
    egarch -> oos;
    
    is -> kmeans_train;
    is -> hmm_train;
    
    kmeans_train -> grid [label=" Scores IS"];
    hmm_train -> grid [label=" Probs IS"];
    
    oos -> kmeans_pred;
    oos -> hmm_pred;
    
    kmeans_train -> kmeans_pred [label=" Centróides", style=dashed];
    hmm_train -> hmm_pred [label=" Matrizes", style=dashed];
    
    grid -> ensemble [label=" Pesos Ótimos"];
    kmeans_pred -> ensemble;
    hmm_pred -> ensemble;
    
    ensemble -> backtest;
    backtest -> resultado;
}
```
    )
  ),
  caption: [Arquitetura do Pipeline de Risco e Backtest]
) <fig_pipeline>



=== Pré-processamento de Dados e Filtros <subcap_processamento>

Os dados coletados em @subcap_coleta_dados foram divididos em dois períodos _In-Sample_ e _Out-of-Sample_, sendo o período _In-Sample_, iniciado em janeiro de 2018 até dezembro de 2022
 utilizados para a seleção e estimação dos parametros dos modelos e o período _Out-of-Sample_, iniciado em janeiro de 2023 até julho de 2026, utilizado para a implementação, observação e validação dos modelos,
 incluindo a avaliação do modelo em eventos de crédito realizado como o Grupo Pão de Açúcar, amplamente citado nessa pesquisa, devido a suas proporções e ao fato de ter sido o evento mais recente, dado o momento em que 
 este trabalho foi escrito.

 Além disso, as variáveis obtidas na etapa @subcap_coleta_dados foram utilizadas como base para o cálculo de outras métricas. Para papéis indexados a um percentual do CDI 
(ex: 120% do DI), foi realizada uma conversão explícita baseada na taxa CDI anualizada (extraída via `python-bcb`, conforme a @subcap_coleta_dados). 
A transformação anualiza o fator diário do título e extrai o prêmio absoluto sobre a taxa livre de risco, conforme abaixo:
$ F_"cdi" = (1 + "CDI"_t / 100)^(1/252) $
$ F_"titulo" = (F_"cdi" - 1) times ("Taxa do Ativo"_t / 100) + 1 $
$ S_t = ( (F_"titulo")^252 - 1 ) times 100 - "CDI"_t $

Para os títulos atrelados a índices de inflação (como IPCA, IGPM) ou por um prêmio direto sobre o DI (DI Spread), a própria taxa informada no secundário já reflete o prêmio de risco:
$ S_t = "Taxa do Ativo"_t $. 

A partir dessa informação, foi calculado a variação diária do _spread_ (*Delta Spread*), que atua como o principal input para o ajuste temporal do modelo EGARCH.

$ Delta S_t = S_t - S_(t-1) $

Devido a indisponibilidade de dados suficientes para o cálculo de duration se utilizou como base a quantidade de dias úteis para o vencimento do papel (limitado ao minimo de dois dias), para calcular a taxa ajustada ao prazo, conforme abaixo:

$ "Taxa"_"prazo" = S_t / ln(max("DU", 2)) $

Foi tambem calculado o _z-score_ do _spread_, utilizando uma janela móvel de 60 dias, além do _Spread Range Intraday_ e _Spread Skew Intraday_, dados respectivamente por:

$ S_("range") = "Taxa do Ativo"_"max" - "Taxa do Ativo"_"min" $

$ S_("skew") = ("Taxa do Ativo" - "Taxa do Ativo"_"min") / (S_("range") + epsilon) $

Sendo $epsilon = 1e-6$ utilizado para evitar divisão por zero.

=== EGARCH <subcap_egarch>

Apesar do viés teórico discutido em @cap_revisao_lit, foram testados vários modelos da familia GARCH em um modelo de torneio de _grid-search_, para
diferentes tamanhos de amostra, o modelo EGARCH foi aquele que apresentou melhor desempenho. O torneio avaliou os dados a partir de 2018 até o fim de 2022, que foi o período utilizado para treinamento do modelo, 
sendo o período a partir de 2023 o período de validação dos resultados, conforme detalhado em @subcap_processamento. O código listou todos os ativos e filtrou os $n$ mais líquidos do período, sendo testado para diferentes valores de $n$.

Para cada um dos ativos selecionados, o otimizador testou um grid combinatório de 32 especificações da familia GARCH (utilizando o pacote `arch`). Os hiperparâmetros iterados foram:
- Média Condicional: Fixada em um modelo Autorregressivo de ordem 1 (AR(1)).
- Famílias de Volatilidade: GARCH tradicional, EGARCH (exponencial), GJR-GARCH (assimétrico) e TARCH.
- Defasagens (Lags) $p$: 1 e 2 (Impacto da variância passada).
- Defasagens (Lags) $q$: 1 e 2 (Impacto dos choques correntes).
- Distribuição dos Resíduos: Normal e t-Student.

A variável de entrada, conforme detalhado em @subcap_processamento foi o *Delta Spread*. Para cada combinação de modelo e ativo foi calculado o Critério de Informação de Akaike (AIC) e então para cada papel o modelo escolhido
foi aquele que apresentou menor valor de AIC, cada vez que o modelo foi eleito foi considerado uma vitória. Ao final foi calculado a taxa média de vitórias de cada modelo e eleito aquele que apresentou um maior percentual de vitórias. 
Matematicamente, a taxa de vitória $W_j$ de um modelo $j$ é dada por:

$ W_j = (sum_{i=1}^N I_(i, j)) / N times 100 $

onde $N$ é o número total de ativos avaliados e $I_(i, j)$ é uma função indicadora que assume valor $1$ se o modelo $j$ apresentar o menor AIC para o ativo $i$ (ou seja, $"AIC"_(i, j) = min_k "AIC"_(i, k)$), e $0$ caso contrário. 

Adotou-se o modelo que maximizou $W_j$, garantindo a escolha empírica do algoritmo que melhor se adapta à maior proporção do mercado de crédito. Para amostras pequenas o destaque foi o modelo EGARCH(2,1,1) utilizando a distribuição t-student, porém, a partir de 
100 amostras ($n=100$), o EGARCH(1,1,1) com a distribuição t-student passou a apresentar uma maior taxa de vitórias, como se pode observar nas figuras abaixo:

#figure(
  image("../imagens/comparacao_modelos_ranking_n30_True.png", width: 90%),
  caption: [Torneio GARCH: Ranking Médio para a amostra dos 30 ativos mais líquidos.]
) <fig_ranking_30>

#figure(
  image("../imagens/comparacao_modelos_ranking_n100_True.png", width: 90%),
  caption: [Torneio GARCH: Ranking Médio para a amostra dos 100 ativos mais líquidos.]
) <fig_ranking_100>

#figure(
  image("../imagens/comparacao_modelos_ranking_n500_True.png", width: 90%),
  caption: [Torneio GARCH: Ranking Médio para a amostra ampla de 500 ativos.]
) <fig_ranking_500>

Além disso, nas @fig_ranking_100, @fig_ranking_500 podemos observar que apesar do EGARCH(1,1,1) com a distribuição t-student apresentar maior taxa de vitórias, o GARCH(1,0,1) com a distribuição t-student apresentou melhor rank médio no teste. Esse resultado é,
de certa forma, esperado, uma vez que para debentures liquidas que não possuem grandes choques, o GARCH, como visto em @cap_revisao_lit tem alto poder preditivo em condições de normalidade, enquanto o EGARCH pode ser penalizado pela tentativa de estimar 
assimetria (e parametros a mais quando comparamos apenas as versões supra citadas), uma vez que o AIC penaliza modelos que possuem parâmetros extras caso eles não tragam ganhos de aderência significativos. Contudo, nos papéis que passam por mais eventos de estresse,
é esperado que o EGARCH performe melhor, por ser capaz de capturar assimetrias, além da heterocedasticidade condicional. O que poderia justificar os resultados observados.

Como o intuito dessa pesquisa é estudar justamente os casos de estresse, e não a dinâmica da normalidade, foi adotado o modelo que apresentou maior _Win Rate_, e não aquele que apresentou o melhor rank médio. Essa escolha é justificada pelo fato de que,
desejamos possuir o modelo que possui maior taxa de acertos, em detrimento da otimização de parâmetros, o que também justifica a escolha do AIC como métrica principal em detrimento do BIC, que possui maior 
penalização por parâmetros extras, favorecendo modelos mais simples. Além disso, o EGARCH modela a variancia em escala logarítmica, o que garante que a variancia seja sempre positiva, diferentemente do GARCH tradicional.

Após a eleição do EGARCH(1,1,1) com distribuição t-Student como o motor principal de volatilidade condicional, foram aplicados testes de diagnóstico aos resíduos gerados por este modelo para verificar sua qualidade estatística:

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

Uma vez definido e implementado o modelo EGARCH(1,1,1) com distribuição t-Student, a distribuição estimada para cada ativo foi utilizada também para o cálculo do Valor em Risco (VaR) e Expected Shortfall (ES) (com percentil de
99%, que foram atribuidos as variaveis `VaR_99` e `Expected_Shortfall_99`, respectivamente) como forma de precificar o risco das debentures
analisadas baseado na série de volatilidade estimada. Como a distribuição escolhida para os resíduos foi a t-student, se $nu <= 2$ então a variancia da distribuição se torna infinita, levando a erros numericos no python quando se tenta calcular o VaR e ES,
para evitar tais erros, foi aplicado um limite nos graus de liberdade, de forma que $nu$ sempre será maior que 2.05, matematicamente, temos que o tratamento aplicado foi:

$ nu = max(2.05, nu_("est")) $

Onde $nu_("est")$ é o valor estimado pelo modelo EGARCH(1,1,1). Além disso, durante a estimação da volatilidade, foram encontrados alguns problemas de otimização devido a instabilidade de algumas séries, principalmente as que permanecem dias sem negociação e quando
são negociadas apresentam "saltos" no _spread_. Como o intuito do modelo é uma classificação de _warning_, e não uma quantificação exata do risco, ou do valor esperado da perda, aplicou-se uma limitação na volatilidade calculada, de forma que caso o EGARCH 
estime um valor que seja 20 vezes maior que o percentil 99% da volatilidade 
observada do ativo, estimada pelo desvio padrão, o valor é removido da amostra e replica-se a volatilidade observada no dia anterior, matematicamente, temos que o tratamento aplicado foi:

$ sigma_("est")(t) = sigma_("est")(t-1) quad "se" quad sigma_("est")(t) > v_("teto") $

onde $sigma_("est")(t)$ é a volatilidade estimada pelo modelo EGARCH(1,1,1) no dia $t$, e $v_("teto")$ é o limite superior definido como 20 vezes o percentil 99 da série _in-sample_. 

=== Teste de Estacionariedade dos Spreads

A aplicação de modelos da família GARCH pressupõe que a série temporal analisada seja estacionária em covariância. Antes do ajuste do EGARCH-t, verificou-se, portanto, a estacionariedade das séries de retorno 
de _spread_ utilizadas como insumo do motor de volatilidade.

Para tanto, aplicou-se o Teste de Dickey-Fuller Aumentado (ADF) sobre as séries de primeiro incremento de _spread_ (`Delta_Spread`) dos 529 ativos selecionados para modelagem.
O teste avalia a hipótese nula de raiz unitária (série não-estacionária):

- *H0* (ADF): A série de `Delta_Spread` possui raiz unitária (não-estacionária).
- *H1* (ADF): A série é estacionária (rejeita H0).

A especificação adotada inclui constante sem tendência determinística, com seleção automática de defasagens por Critério de Informação de Akaike (AIC). Os resultados, reportados 
na @tab_adf, demonstram que a série de _spread_ bruto (`Taxa_Ativo`) é não-estacionária em 91% dos casos, como esperado (a nível de _spread_, as séries são integradas de ordem 1). Após a primeira 
diferença (`Delta Spread`), *95,7% das séries rejeitam H0 ao nível de 5%*, validando o pressuposto de estacionariedade necessário para o EGARCH.

#figure(
  table(
    stroke: 0.5pt,
    columns: (1.5fr, 1fr, 1fr, 1.2fr, 1.2fr),
    align: center + horizon,
    [*Indexador*], [*Total*], [*Estacionárias \ (Delta Spread)*], [*Taxa \ (%)*], [*Spread Bruto \ (Taxa Ativo)*],
    [IPCA], [286], [275], [96,2%], [NE],
    [CDI Spread], [239], [227], [95,0%], [NE],
    [PRE], [4], [4], [100,0%], [NE],
    [*Total*], [*529*], [*506*], [*95,7%*], [—],
  ),
  caption: [Resultados do Teste ADF ($alpha = 5\%$) — Estacionariedade por Indexador. \ *Nota*: NE = Não-Estacionário.]
) <tab_adf>

Os ativos que compõem os 3,4% restantes que não rejeitam H0 são, em sua maioria, papeis com histórico extremamente curto (entre 30 e 60 observações) e perfil de iliquidez estrutural, 
nos quais a baixa frequência de negociação gera séries com longos períodos de retornos nulos que distorcem a convergência do teste. Para esses casos, o motor EGARCH produz estimativas de volatilidade 
de menor confiança, conforme documentado na @subcap_egarch.

=== Seleção de variáveis

Nas seções @subcap_processamento e @subcap_egarch foram listadas as variáveis calculadas: 
  - Taxa_ZScore
  - Volatilidade_EGARCH
  - VaR_99
  - Expected_Shortfall_99
  - Spread_Equivalente
  - Spread_Range_Intraday
  - Spread_Skew_Intraday


Elas foram utilizadas como um input para um processo de seleção de variáveis, que eligiu as mais relevantes para utilização nos modelos propostos. Devido a natureza não supervisionada desses modelos, a determinação da relevância dessas variáveis
não pode ser realizada através dos métodos usuais que são utilizados para os processos de aprendizado supervisionado. Por essa razão, a seleção implementada realiza combinações iterativas por meio de um _Grid Search_ sobre subconjuntos das 
variáveis candidatas utilizando os dados de treinamento (_In-Sample_). Com intuito de garantir significado econômico aos clusters, a variável `Taxa_ZScore` foi mantida como obrigatória em todas as combinações. Impedindo que o algoritmo selecione apenas
variáveis de risco correlacionadas (como a volatilidade EGARCH e o VaR), o que não agregaria valor discriminatório aos _clusters_, devido a carencia da preficicação relativa ao _spread_ de crédito.

Para cada subconjunto testado, os dados foram padronizados utilizando  _RobustScaler_ devido a sua capacidade de lidar com outliers, conforme apresentado em @cap_revisao_lit. Os subconjuntos foram então submetidos a uma clusterização primára utilizando K-Means
com $k=3$ regimes (a escolha dos regimes é justificada empiricamente na @subcap_kmeans_k3). A qualidade de separabilidade dos agrupamentos foi mensurada através das três métricas listadas na @sub_cap_clusters ( *_Silhouette Score_* , *Índice Davies-Bouldin* e *Índice Calinski-Harabasz*).

Uma vez que as métricas atuam em ordens de grandeza e domínios matemáticos distintos, o subconjunto vencedor não é escolhido por médias, mas sim pelo método de agregação de Ranks de Borda (*Borda Count*)#footnote[A classificação integral de todas as combinações de variáveis testadas no _Grid Search_, contendo o ranking detalhado de cada métrica de particionamento e o Borda Score final, está disponível no repositório público da pesquisa, no diretório `anexos_digitais/`.]. 
O algoritmo computa a posição de cada combinação no ranking individual de cada métrica. O *Borda Score* final é dado pela soma das posições invertidas, garantindo uma eleição ordinal, determinística e 
robusta às magnitudes isoladas de índices específicos.

Como resultado da otimização matemática (*Borda Score*), o subconjunto `Taxa_ZScore` e `Volatilidade_EGARCH` obteve a pontuação máxima no particionamento empírico. No entanto, o subconjunto eleito para a modelagem final 
incorporou também a estimativa de risco de cauda (`Expected_Shortfall_99`), formando o trio `Taxa_ZScore`, `Volatilidade_EGARCH` e `Expected_Shortfall_99`, que figurou em segundo lugar no ranking geral. 
A @fig_feature_selection ilustra o Top 10 das combinações avaliadas. A escolha tática pelo trio justifica-se pela necessidade imperativa de o modelo possuir sensibilidade preditiva a perdas financeiras extremas, 
agregando significado econômico aos _clusters_ formados.

#figure(
  image("../imagens/feature_selection_ranking.png", width: 90%),
  caption: [Top 10 Subconjuntos de Variáveis classificados pelo método de Borda Count.]
) <fig_feature_selection>

Uma forma mais lúdica de observar o desempenho dessas variáveis é realizar a comparação de forma multidimensional. A @fig_feature_radar 
ilustra o desempenho das quatro principais combinações normalizado nos três eixos de avaliação (Coesão, Dispersão e Separação). O gráfico demonstra 
como a combinação escolhida consegue maximizar satisfatoriamente o _Silhouette Score_ e o *Calinski-Harabasz*, mantendo a competitividade no índice de 
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
coerente, reforçando sua escolha, em detrimento do VaR.

=== K-Means <subcap_kmeans>

Eleitas as variáveis de entrada do modelo (`Taxa_ZScore`, `Volatilidade_EGARCH` e `Expected_Shortfall_99`), o algoritmo K-Means atua propositalmente como uma _baseline_ ingênua (_naive_). Reconhece-se que a aplicação do K-Means em 
séries temporais financeiras viola o pressuposto de observações independentes e identicamente distribuídas (i.i.d.), uma vez que os retornos apresentam comprovada autocorrelação da variância. Contudo, essa violação metodológica é assumida de 
forma deliberada no desenho da pesquisa para servir como contraponto determinístico ao modelo markoviano (HMM). A intenção é provar valor marginal preditivo que a memória temporal agrega sobre a classificação puramente estática, de forma empíric a e quantitativa.
O processo é realizado iterativamente para cada grupo de indexador (ex: DI, IPCA), a fim de respeitar as dinâmicas particulares de cada mercado.

==== Justificativa Empírica do Número de Clusters ($k=3$) <subcap_kmeans_k3>

A escolha de $k=3$ regimes — Verde (baixo risco), Amarelo (alerta) e Vermelho (crise) — foi motivada, primariamente, pela semântica financeira do sistema de alertas (analoga aos semaforos, comumente utilizados em risco de crédito). 
Contudo, para validar formalmente essa escolha, aplicou-se a análise de _Elbow Method_ (inerçia da soma dos quadrados intra-_cluster_ em função de $k$) e o _Silhouette Score_ médio para $k in \{2, 3, 4, 5, 6, 7\}$, 
utilizando rigorosamente os dados padronizados do período _In-Sample_ para evitar viés prospectivo (_Data Snooping_).

Os resultados, ilustrados na @fig_cluster_validation, mostram que para os indexadores IPCA e DI _Spread_: 
(i) a curva de inerçia exibe uma inflexão (_Elbow_) em $k=3$, indicando redução marginal decrescente a partir deste ponto; 
(ii) o _Silhouette Score_ para $k=3$ é consistentemente superior ao de $k=2$ em ambos os grupos, ao mesmo tempo em que $k=4$ e 
$k=5$ não oferecem ganho relevantes de separabilidade. Conclui-se, portanto, que $k=3$ é a escolha *parcimoniosa* que maximiza a interpretação econômica e a coerência geométrica dos regimes.

#figure(
  grid(
    columns: 1,
    gutter: 15pt,
    image("../imagens/val_IPCA_elbow_silhouette.png", width: 90%),
    image("../imagens/val_CDI_Spread_elbow_silhouette.png", width: 90%)
  ),
  caption: [Elbow Method e Silhouette Score por número de clusters $k$ — Superior: IPCA, Inferior: CDI Spread]
) <fig_cluster_validation>

O primeiro passo é a separação da amostra de treino e teste (_In-Sample_ para treino, _Out-of-Sample_ para teste), conforme detalhado em @subcap_processamento.
Para garantir que _outliers_ extremos (como casos que discutimos nas seções anteriores, em que ativos passam dias sem negociação e depois quando voltam a ser negociados
apresentam saltos no _spread_), aplica-se uma Winsorização (clipagem) no 1º e 99º percentis utilizando os dados _In-Sample_. Esses limites são posteriormente aplicados aos dados
_Out-of-Sample_, prevenindo o viés de antecipação de informação (_look-ahead bias_).

Em seguida, os dados são padronizados através do algoritmo `RobustScaler`. Para capturar o risco relativo de cada papel, o escalonamento é 
feito individualmente por ativo, possuindo como limitador inferior 10% da variância (IQR) global do indexador, evitando que ativos estruturalmente ilíquidos 
sofram explosões numéricas. Já, que, uma vez o _RobustScaler_ é dado por:

$ "Scaled"(x) = (x - Q_2(x)) / (Q_3(x) - Q_1(x)) $

Caso o IQR ($Q_3(x) - Q_1(x)$) seja nulo ou próximo de zero, o escalonamento se torna indefinido.

O K-Means é então treinado nos dados padronizados com $k=3$ agrupamentos. Devido à natureza não-supervisionada do K-Means, 
os centróides gerados recebem rótulos arbitrários (este é um problema conhecido como _Label Switching_). O modelo resolve este problema através de um vetor de polaridade de risco (onde valores maiores de volatilidade e 
_Z-Score_ implicam maior risco), ordenando as médias dos agrupamentos para classificar deterministicamente os regimes em Verde (baixo risco), Amarelo (alerta) e Vermelho (crise). 

Na etapa preditiva, para a construção de um modelo misto ponderado (conforme será abordado em @subcap_modelo_misto), a probabilidade de crise (`Prob_Crise_KMeans`) é definida 
com base na distância euclidiana inversa de cada observação 
_Out-of-Sample_ até o centróide Vermelho.

=== HMM <subcap_hmm>

Para investigar o valor da memória latente no reconhecimento de padrões da série temporal, estabelecemos a segunda hipótese deste estudo:

- *H0₂*: A inclusão da dependência temporal (matriz de transição markoviana) *não* melhora a capacidade de identificação precoce de eventos de estresse em relação ao particionamento geométrico atemporal (K-Means).
- *H1₂*: O modelo HMM, ao modelar a inércia dos regimes de risco, antecipa a deterioração do crédito com maior _lead time_ do que o K-Means para os eventos de crédito observados no período _Out-of-Sample_.

Esta hipótese é avaliada qualitativamente por meio de estudos de caso para uma cesta de debentures e da comparação do primeiro alerta por modelo.

O Modelo Oculto de Markov (HMM - _Hidden Markov Model_) acrescenta a dependência temporal que o K-Means ignora. O pré-processamento para o HMM segue as exatas mesmas premissas 
de divisão, winsorização e padronização geométrica (piso de variância) descritas em @subcap_kmeans, adicionando apenas a restrição de que a massa de dados obedeça estritamente a 
ordenação sequencial no tempo. Já que para o HMM, essa ordenação é de extrema importância para que o modelo consiga modelar as transições entre os estados latentes.

O treinamento _In-Sample_ é realizado através de um HMM Gaussiano (`GaussianHMM`) de 3 estados latentes com matriz de covariância diagonal, aplicando o 
algoritmo de otimização de *Baum-Welch*. Apesar de ter sido demonstrado em @cap_revisao_lit que os retornos do _spread_ exigem uma distribuição leptocúrtica (t-Student), as _features_ alimentadas 
ao HMM neste estágio (`Taxa_ZScore` e `Volatilidade_EGARCH`) já foram previamente modeladas e padronizadas, com a volatilidade condicional já capturando o impacto da cauda pesada. 

Para validar empiricamente esta premissa na modelagem, analisou-se o Excesso de Curtose (medida estatística de "peso da cauda") das séries temporais no período _In-Sample_. Foi constatado que os retornos (sobre as séries de _spread_) apresentaram um Excesso de Curtose de $2683,30$, 
indicando eventos extremos e caudas ultra-pesadas que inviabilizariam o uso de uma matriz Gaussiana. Todavia, a _feature_ `Taxa_ZScore`, resultante do filtro estocástico do EGARCH-t, reduziu este Excesso de Curtose para apenas $1,17$. Em 
finanças quantitativas e modelagem multivariada, excessos de curtose localizados no intervalo de $-2$ a $+2$ (e mesmo sob critérios mais relaxados, até $+7$) são considerados comportados e largamente aceitáveis para a adoção de premissas de 
normalidade em estimações por Máxima Verossimilhança sem enviesamento grave dos estimadores @hair2010multivariate. Consequentemente, o espaço latente do HMM encontra-se num domínio de eventos extremos mitigado, o que valida a 
escolha do modelo Gaussiano para assegurar a estabilidade numérica e convergência na calibração das matrizes.
Da mesma forma, os vetores de médias estimadas para as emissões Gaussianas sofrem a correção heurística de _Label Switching_ para rotular os estados como Verde, Amarelo e Vermelho.

Uma alteração fundamental feita no HMM padrão diz respeito à calibração da Matriz de Transição de Estados ($A$). Em bases de dados com regimes muito duradouros, pode haver a total ausência empírica de transições entre estados extremos (como saltos diretos de Verde para Vermelho) 
na amostra de treinamento. Isso gera probabilidades de transição iguais a zero, 
transformando os regimes em "estados absorventes" (uma vez que o modelo entre nesse estado, a probabilidade de sair matematicamente se anula). Para mitigar esse problema, aplicou-se primeiramente a *Suavização de Laplace* (_Additive Smoothing_) sobre a matriz empírica de contagens de transição:

$ P'_{i j} = (C_{i j} + alpha) / ( sum_{k=1}^K C_{i k} + K alpha ) $ <eq_laplace_hmm>

onde $C_{i j}$ é a contagem empírica de transições do estado $i$ para o estado $j$ observadas na sequência latente decodificada do _In-Sample_, $K=3$ é o número de estados, e $alpha = 1$ atua como o pseudo-fator aditivo. 

Complementarmente à @eq_laplace_hmm, para garantir matematicamente que o modelo permaneça reativo aos novos choques de mercado e não dependa excessivamente da inércia do estado anterior, 
impôs-se um limiar (piso) arbitrário de 1% ($0.01$) sobre a matriz de probabilidade de transição, seguido por uma re-normalização linha a linha (para assegurar que o somatório das probabilidades convirja para 1):

$ P''_{i j} = max(P'_{i j}, 0.01) $
$ P_{i j} = P''_{i j} / (sum_{k=1}^K P''_{i k}) $ <eq_hmm_piso>

Esse mecanismo em duas etapas força o modelo a manter vias probabilísticas ativas e o impede de se tornar inerte, especialmente para a saída do estado de crise (Vermelho).

A inferência nos dados _Out-of-Sample_ é desenhada para evitar viés do futuro. Para estimar a probabilidade de um ativo estar em crise no dia $t$, 
o modelo recebe apenas a sequência de variáveis observáveis do instante inicial até o instante $t$ (janela causal). A sequência ótima de estados latentes é decodificada utilizando o *Algoritmo de Viterbi*, 
e a probabilidade marginal instantânea de crise (`Prob_Crise_HMM`) é inferida simultaneamente pelo _Forward-Backward_.


=== Modelo Misto (Ensemble) <subcap_modelo_misto>

A intuição de mesclar diferentes modelos pode parecer promissora, mas exige verificação empírica. A quarta hipótese que permeia este trabalho contesta o benefício da modelagem mista:

- *H0₄*: A combinação ponderada (Ensemble) dos modelos K-Means e HMM *não* produz uma estratégia de alocação inferior às estratégias individuais de cada componente, em termos de retorno ajustado ao risco.
- *H1₄*: A ponderação dos sinais dos modelos K-Means e HMM, sem calibração empírica dos pesos, induz ao efeito _whipsaw_ e resulta em performance inferior às estratégias individuais.

A avaliação é realizada pela comparação do Calmar Ratio e Retorno Total do Ensemble contra K-Means e HMM individuais nos resultados do Backtest.

As predições individuais do K-Means (detalhada em @subcap_kmeans) e do HMM (detalhada em @subcap_hmm) são posteriormente combinadas em uma pontuação final, 
buscando mesclar a estabilidade do particionamento geométrico (K-Means) com a memória temporal do filtro bayesiano (HMM).

A combinação matemática é realizada através de uma média ponderada das probabilidades individuais de cada modelo.
Para determinar a alocação de pesos ótima e evitar decisões arbitrárias ou vieses prospectivos (_Data Snooping_), executou-se uma rotina de otimização de hiperparâmetros via _Grid-Search_ de Força Bruta ($w_"HMM" \in [0.0, 1.0]$, em incrementos de 0.10) 
estritamente sobre as predições do período _In-Sample_.  A métrica alvo para a otimização foi o *Calmar Ratio* (retorno anualizado sobre rebaixamento máximo) gerado pelo simulador financeiro. 
O resultado empírico demonstrou que o melhor retorno ajustado ao risco na amostra de treinamento ocorreu com a proporção de 70% de peso para o HMM e 30% para o K-Means. A @fig_ensemble_sensitivity ilustra as métricas financeiras obtidas para 
diferentes combinações de pesos no simulador tático _in-sample_ (assumindo liquidação defensiva a partir do estágio de Alerta), ratificando o pico otimizado em $w_"HMM" = 0.70$.

#figure(
  image("../imagens/sensitivity_ensemble_amarelo.png", width: 90%),
  caption: [Análise de Sensibilidade (_Grid-Search_) dos pesos do modelo Ensemble no período _In-Sample_.]
) <fig_ensemble_sensitivity>

A @tab_ensemble_weights detalha os resultados quantitativos extraídos da simulação estática, evidenciando como a alocação de 70% do peso para o motor probabilístico (HMM) minimizou o declínio e ofereceu o equilíbrio ótimo frente a estratégias puramente mono-modelo.

#figure(
  table(
    stroke: 0.5pt,
    columns: (1fr, 1fr, 1.2fr, 1.5fr, 1.2fr),
    align: center + horizon,
    [*w_HMM*], [*w_KMeans*], [_CAGR (%)_], [_Max Drawdown (%)_], [*Calmar Ratio*],
    [0.0], [1.0], [-2.938], [-98.289], [-0.0299],
    [0.1], [0.9], [-1.711], [-98.817], [-0.0173],
    [0.2], [0.8], [-1.982], [-99.163], [-0.0200],
    [0.3], [0.7], [-1.725], [-43.616], [-0.0396],
    [0.4], [0.6], [-1.511], [-51.129], [-0.0296],
    [0.5], [0.5], [-1.330], [-64.830], [-0.0205],
    [0.6], [0.4], [-1.128], [-58.108], [-0.0194],
    [*0.7*], [*0.3*], [*-1.097*], [*-64.392*], [*-0.0170*],
    [0.8], [0.2], [-1.115], [-64.648], [-0.0173],
    [0.9], [0.1], [-1.160], [-64.542], [-0.0180],
    [1.0], [0.0], [-1.165], [-63.599], [-0.0183]
  ),
  caption: [Métricas da grade de sensibilidade (_In-Sample_) por par de pesos.]
) <tab_ensemble_weights>

A equação do _Ensemble_ aplicada na fase preditiva (_Out-of-Sample_), no instante $t$, é dada por:

$ "Probabilidade Sintética"_t = 0.70 times "Prob_Crise_HMM"_t + 0.30 times "Prob_Crise_KMeans"_t $ 

Por fim, para garantir uma combinação mais suave e menos suscetível a ruídos de alta frequência, aplicou-se um filtro de 
média móvel exponencial de 3 dias ($"EMA"_3$) sobre a "Probabilidade Sintética", gerando a pontuação final de risco
(que também foi considerado durante a etapa de _Grid Search_ para eleição dos pesos, como descrito anteriormente). A fórmula 
da Média Móvel Exponencial é calculada recursivamente da seguinte forma:

$ "Pontuação Final"_t = alpha times "Probabilidade Sintética"_t + (1 - alpha) times "Pontuação Final"_{t-1} $

onde $alpha$ é o fator de suavização, definido por $alpha = 2 / (N + 1)$. Para uma janela de $N=3$ dias, o fator 
resulta em $alpha = 0.5$. Dessa forma, a "Pontuação Final" de risco absorve os choques recentes rapidamente, 
mas preserva a memória de curto prazo para evitar que a volatilidade diária acione alarmes falsos de crise.

== Protocolos de Validação (Kupiec POF e Backtest) <subcap_kupiec_backtest>

Para testar a robustez e a aplicabilidade prática do modelo desenvolvido, a etapa de validação foi estruturada em duas 
dimensões complementares, aplicadas sobre o período _Out-of-Sample_ para garantir a ausencia de viés prospectivo
(_Look-Ahead Bias_). A primeira dimensão avaliada diz respeito a acurácia estatistica do modelo, aplicada sobre
as saídas do motor EGARCH-t. Foi utilizado o Teste de Proporção de Falhas (_POF - Proportion of Failures_) desenvolvido por 
#cite(<kupiec1995techniques>, form: "prose"), que avalia se a frequência empírica de violações (quantidade de dias em que a perda
real do ativo excedeu a perda máxima estimada pelo VaR) é estatisticamente compatível com o nível de confiança estipulado
pelo modelo. Rejeitar a hipótese nula do teste indica que o motor de volatilidade subestima ou superestima
sistematicamente as caudas pesadas observadas no mercado.

A segunda dimensão avalia a qualidade preditiva do modelo no contexto do mercado de crédito corporativo brasileiro por meio
de um _Backtest_ financeiro, focado em avaliar a eficácia dos diferentes "Regimes de Risco" sugeridos pelos modelos apresentados.
O _backtest_ simula o impacto de diferentes estratégias de liquidação de portfólio baseadas nas pontuações de risco dos modelos
(Verde, Amarelo ou Vermelho), comparando duas abordagens de liquidação para cada modelo:

  - Venda Retardada: Estratégia reativa, onde a liquidação ocorre quando o modelo acusa um Regime de Risco Vermelho. Idealmente, caso o modelo seja capaz de prever o estado vermelho antes do choque, esse modelo deveria gerar rentabilidade superior, uma vez que a venda ocorre antes ou no exato momento do choque, evitando assim perdas substanciais. Todavia, se o modelo não for capaz de prever o estado vermelho antes do choque, essa estratégia tende a gerar perdas operacionais, uma vez que o choque já ocorreu e a venda só será realizada após a materialização dos choques no preço dos ativos.
  - Venda Preventiva: Estratégia ofensiva, onde a liquidação ocorre quando o modelo acusa um Regime de Risco Amarelo. Idealmente, deveria ser superada pela venda retardada em caso de um modelo ideal, porém, na prática, em cenários onde o modelo pode demorar a reagir na classificaçao para o regime vermelho, essa estratégia tende a gerar rentabilidade superior, uma vez que a venda ocorre assim que são observados os primeiros sinais de deterioração do ativo, antes da materialização completa do choque. Todavia, caso hajam muitos falsos positivos, essa estratégia tende a gerar rentabilidade inferior à venda retardada, uma vez que gera custos operacionais desnecessários e reduz o ganho em cenários de alta volatilidade.

Para tornar a simulação o mais realista possível e capturar a penalidade financeira do _whipsaw_ (falsos rompimentos que geram múltiplos sinais de entrada e saída), o _backtest_ incorpora uma taxa de 
custo de transação de 0,5% (50 _bps_). No mercado secundário de crédito brasileiro, caracterizado por menor liquidez e _spreads_ de _bid-ask_ mais elásticos do que o mercado de ações, a inclusão desse custo é fundamental.
 Ele atua como um fator de desconto sobre estratégias excessivamente reativas (com alta rotatividade/_turnover_), testando assim o real valor econômico agregado pelos sinais preditivos contra os custos operacionais de executá-los na prática.

O resultado das estratégias táticas é comparado contra o desempenho passivo de um portfólio _Buy-and-Hold_. Para assegurar o rigor técnico e a reprodutibilidade da simulação financeira, 
o algoritmo do _backtest_ foi estruturado sob as seguintes premissas operacionais:

- *Carteira Inicial:* No primeiro dia útil da janela _Out-of-Sample_, o capital inicial é distribuído de forma equiponderada (_equal-weight_) entre todas as debêntures elegíveis disponíveis na base de dados naquela data.
- *Regra de Venda (Liquidação):* A liquidação ocorre integralmente no momento em que o modelo classifica o ativo no regime de _stop_ estipulado pela estratégia (seja "Vermelho" na estratégia retardada, ou "Amarelo/Vermelho" na preventiva). O capital obtido pela venda é deduzido do custo de transação de 0,5% e mantido em caixa.
- *Remuneração de Caixa:* Qualquer montante não alocado em debêntures (caixa livre) é remunerado diariamente pela taxa DI (CDI) histórica real correspondente ao dia da simulação, refletindo o custo de oportunidade livre de risco (_risk-free_). E tentando simular o que ocorreria na realidade,
porque um fundo ou uma pessoa fisica alocaria esse dinheiro em um CDB-DI com liquidez diária ou fundo de zeragem, por exemplo.
- *Regra de Recompra:* Para evitar re-entradas prematuras (_dead cat bounces_) e a corrosão da rentabilidade pelo excesso de giro, o capital em caixa é redistribuído igualitariamente apenas entre ativos que 
atendam simultaneamente aos três filtros:
  1. *Quarentena Temporal:* O ativo não pode ter estado em um regime de alerta/crise nos últimos 180 dias (6 meses).
  2. *Inércia de Estabilidade:* O ativo deve permanecer ininterruptamente no regime "Verde" por pelo menos 15 dias úteis, confirmando o fim da volatilidade.
  3. *Filtro de Payback:* O prêmio de risco anualizado do ativo no instante da compra deve ser matematicamente suficiente para recuperar o pedágio do custo de transação em, no máximo, 3 meses. A condição de elegibilidade é formalizada pela seguinte restrição:
  
  $ "Spread Mínimo" = c times 12 / M $ <eq_filtro_payback>

  onde $c$ é a taxa do custo de transação (0,5%) e $M$ é o período máximo tolerado de _payback_ em meses ($M=3$). Se o _spread_ ofertado pela debênture for inferior a este limite mínimo calculado (neste cenário, 2,0% ao ano), a compra é abortada, visto que o prêmio de risco não justifica o custo operacional e financeiro do giro de portfólio.

- *Tratamento para Vencimentos*: Caso um ativo vença, o caixa recebido na data do vencimento é reaplicado nas debêntures da carteira. Para as carteiras táticas do modelo (que não representam o _benchmark Buy-and-Hold_), a reaplicação do caixa obedece rigorosamente às mesmas regras e filtros de recompra acima. Já para o portfólio de _benchmark_ (_Buy-and-Hold_), o capital oriundo de vencimentos é redistribuído de forma equiponderada entre os ativos remanescentes da carteira inicial, sem a aplicação de quaisquer filtros táticos ou preditivos.

Essa arquitetura algorítmica de simulação garante que a performance do modelo preditivo não seja um mero artefato teórico, testando a viabilidade de seus sinais diretamente contra as restrições operacionais e os atritos do mercado corporativo brasileiro.
