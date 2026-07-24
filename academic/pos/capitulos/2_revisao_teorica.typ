= Revisão da Literatura

A ideia central desse trabalho parte da modelagem de risco de crédito de debentures. Mas o que é risco? Existem varias definições, @jorion2006 talvez tenha uma das mais simples
e intuitivas, risco é a volatilidade dos resultados inesperados, que podem representar o valor de ativos, patrimônios ou resultados. E esse risco pode ser originado de várias formas,
criados pelos humanos como ciclos de negócios, inflação, mudanças políticas, guerras, etc, ou podem ocorrer devido a fenomenos naturais como terremotos, tsunamis, etc. É na tentativa de 
combater esses riscos que a economia cresce e as tecnologias se desenvolvem. 

Parte significativa do mercado financeiro atual foi desenvolvida na tentativa de lidar ou compartilhar esses riscos. Ao mesmo tempo que o mercado se desenvolveu,
se gerou a necessidade de limitar as perdas potenciais sem deixar de tomar risco. Existem controles `ex post`, mas esses não conseguem garantir que as perdas sejam 
próximas ao limite desejado, ao depender da sorte, podem ser maiores. A solução é o uso de modelos quantitativos `ex ante` que limitam a exposição a determinados ativos
ou fatores de risco baseados em distribuições de probabilidade, como por exemplo os modelos de Value at Risk.

O Value at Risk pode ser definido de forma intuitiva como a maior perda esperada de uma carteira em um determinado período de tempo, com um determinado nível de confiança. Ou,
de forma mais formal, é o quantil da distribuição de ganhos e perdas projetadas para um horizonte de tempo. Muitas vezes para séries temporais, essa projeção é feita por 
meio de modelos como o GARCH, que apesar de ser amplamente utilizado, falha em choques assimétricos, como observamos nos eventos recentes envolvendo o Grupo Pão de Açucar e Americanas.
Para superar essa fraqueza do modelo garch, @nelson1991conditional propõe o modelo EGARCH, que captura assimetrias na volatilidade dos ativos financeiros.


== Value-at-Risk e Modelos da Família GARCH

== A Hipótese de Mudança de Regimes (Regime-Switching)
economia e os mercados não têm um estado único. Eles transitam entre "Bull" e "Bear" (ou Calmaria e Crise).
matemática básica por trás das cadeias de Markov ocultas (transições estocásticas, estados não observáveis diretamente, apenas através das emissões/preços).

== Integração: O Modelo MS-GARCH
a literatura atual une os dois mundos: modelos GARCH cujos parâmetros mudam dependendo de um estado de Markov.