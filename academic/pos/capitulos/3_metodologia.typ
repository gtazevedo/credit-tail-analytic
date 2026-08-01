= Metodologia e Dados

A análise do risco de crédito das debentures requer uma coleta extensa de dados e analise rigorosa de sua qualidade para que o modelo implementado seja acurado e capaz
de capturar as nuances desejadas. Este capítulo detalha os procedimentos que foram adotados para a coleta, tratamento e análise dos dados. Além dos modelos e validações
aplicados neste estudo.

Uma vez que o estudo será disponibilizado juntamente dos códigos-fonte utilizados para sua implementação, todos os procedimentos detalhados abaixo podem ser replicados pelo leitor
de forma independente. Para facilitar a reprodução, as funções utilizadas em cada etapa serão citadas, a fim de auxiliar a coomprensão do leitor. Os detalhes sobre a utilização de
cada função e da ferramenta como um todo poderão ser encontrados na documentação do projeto disponível no #link("https://github.com/gtazevedo/credit-tail-analytic")[repositório do GitHub].

== Coleta e Tratamento de Dados (ANBIMA)

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

Na etapa de pré-processamento, estruturada na classe `DataPreprocessor`, foi realizada a normalização e tratamento das variáveis. Para papéis indexados a um percentual do CDI 
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

Como a base de dados extraída da ANBIMA abrange múltiplos indexadores (como IPCA+, DI+ e % do CDI), foi necessário separar esse grupos treinar e aplicar o modelo de forma independente,
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

=== Pré-processamento de Dados e Filtros



=== EGARCH

Apesar do viés teórico discutido em @cap_revisao_lit, para se optar pelo modelo EGARCH, foram testados vários modelos da familia GARCH em um modelo de torneio de *grid-search*, para
diferentes tamanhos de amostra. O torneio avaliou os dados a partir de 2018 até o fim de 2022, que foi o período utilizado para treinamento do modelo, sendo o período a partir de 2023
o período de validação dos resultados. O código listou todos os ativos e filtrou os 30, 50, 100, 500, 1000, 3000, 5000 mais líquidos do período.

Para cada um dos ativos selecionados, o otimizador testou um grid combinatório de 32 especificações da familia GARCH (utilizando o pacote `arch`). Os hiperparâmetros iterados foram:
- Média Condicional: Fixada em um modelo Autorregressivo de ordem 1 (AR(1)).
- Famílias de Volatilidade: GARCH tradicional, EGARCH (exponencial), GJR-GARCH (assimétrico) e TARCH.
- Defasagens (Lags) $p$: 1 e 2 (Impacto da variância passada).
- Defasagens (Lags) $q$: 1 e 2 (Impacto dos choques correntes).
- Distribuição dos Resíduos: Normal (normal) e t-Student (studentst).

Para cada modelo em cada ativo foi calculado o Critério de Informação de Akaike (AIC) e o modelo eligido foi aquele que apresentou o melhor rank médio de AIC ao longo de todos os 
ativos testados, de forma a escolher o modelo que em média, se adapte melhor ao mercado. Para amostras pequenas o destaque foi o modelo GARCH(1,1,1), mas a medida que a quantidade de
amostras aumentou e se aproximou da quantidade de amostras total desse estudo, o modelo EGARCH passou a apresentar resultados superiores, como se pode observar nas figuras abaixo:




Validação de Resíduos: Após coroar o modelo vencedor (que, nos seus testes, resultou no EGARCH), o validador ainda aplica:
Teste Ljung-Box (Lag 10): Para confirmar que não restou autocorrelação serial não-explicada nos resíduos padronizados.
Teste ARCH-LM (Lag 10): Para atestar que toda a heterocedasticidade condicional foi devidamente "sugada" pelo modelo.

Para mais informações, pode ser consultada a classe `ValidadorEconometrico`, disponível em `analysis.selecao_modelos`

== Protocolos de Validação (Kupiec POF e Backtest)
Lorem ipsum dolor sit amet, consectetur adipiscing elit.
