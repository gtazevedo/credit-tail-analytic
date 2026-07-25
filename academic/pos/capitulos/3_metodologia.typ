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

Na etapa de pré-processamento, estruturada na classe `DataPreprocessor`, foi realizada a normalização e tratamento das variáveis para garantir que 
todas as debêntures pudessem ser comparadas de forma equitativa, independentemente de seus indexadores. Primeiramente, as observações foram agrupadas por *tickers* e ordenadas cronologicamente.

Como a base de dados extraida da ANBIMA abrange múltiplos indexadores (como IPCA+, DI+ e % do CDI), foi necessário unificar a medida de risco por meio do cálculo do
*Spread Equivalente* ($S_t$). Para os títulos atrelados a índices de inflação (como IPCA, IGPM) ou compostos por um prêmio direto sobre o DI (DI Spread), 
a própria taxa informada no secundário já reflete diretamente o prêmio de risco:
$ S_t = "Taxa do Ativo"_t $

Contudo, para papéis indexados a um percentual do CDI (ex: 120% do DI), foi realizada uma conversão explícita baseada na taxa CDI anualizada extraida do pacote `python-bcb` 
para isolar a taxa adicional. A transformação anualiza o fator diário do título e extrai o prêmio sobre a taxa livre de risco:
$ F_"cdi" = (1 + "CDI"_t / 100)^(1/252) $
$ F_"titulo" = (F_"cdi" - 1) times ("Taxa do Ativo"_t / 100) + 1 $
$ S_t = ( (F_"titulo")^252 - 1 ) times 100 - "CDI"_t $

Após o cálculo e padronização do *spread* equivalente em toda a amostra, foi calculado o *Delta Spread* ($\Delta S_t$), que representa a variação diária do spread do titulo obtido na etapa
anterior:
$ Delta S_t = S_t - S_(t-1) $

$\Delta S_t$ atua como o principal input para o modelo EGARCH implementado.

Como citado em @cap_introducao, um desafio inerente ao mercado secundário de crédito privado brasileiro é a baixa liquidez dos ativos, inclusive com alguns chegando a possuir
dias sem nego. A ANBIMA classifica o volume de negociação em faixas, sendo a faixa mais baixa dada por "Até 1MM", e portanto, dado as informações possuídas na realização dessa pesquisa,
esses são os ativos definidos como ilíquidos. No código implementado, desenvolveu-se uma rotina de tratamento governada pela flag `filter_low_liquidity`. Quando habilitada, 
essa rotina transforma o *Delta Spread* dos dias classificados na faixa de menor liquidez em valores nulos (`NaN`). O propósito dessa funcionalidade é impedir que, caso sejam observados
eventos de variação de spread expurios, devido a baixa liquidez, eles não sejam propagados para o modelo EGARCH, o que poderia corromper a estimação da persistência e dos choques 
(parâmetros $alpha$ e $beta$) da variância condicional. Além disso, ao substituir o *spread* por nulo em vez de deletar a linha do banco de dados, garante-se a 
integridade da sequência temporal (os dias continuam existindo), requisito obrigatório para o treinamento das Cadeias de Markov.

Contudo, com o objetivo de capturar o comportamento do mercado de crédito de forma irrestrita e avaliar a robustez do algoritmo de K-Means 
e da matriz de transição do HMM mesmo diante dos ruídos típicos de negociação e baixa liquidez, para os resultados que serão apresentados neste trabalho, 
a configuração `filter_low_liquidity` foi mantida como `False`. Consequentemente, o modelo de risco processou a totalidade dos dados extraidos do sistema REUNE, sem a supressão 
ou anulação das variações de preço oriundas das faixas de baixa liquidez.

== O Pipeline de Risco (EGARCH, K-Means e HMM)
Lorem ipsum dolor sit amet, consectetur adipiscing elit.

== Protocolos de Validação (Kupiec POF e Backtest)
Lorem ipsum dolor sit amet, consectetur adipiscing elit.
