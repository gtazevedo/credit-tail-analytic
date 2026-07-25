= Revisão da Literatura

A ideia central deste trabalho parte da modelagem de risco de crédito de debêntures. Mas o que é risco? Existem várias definições. #cite(<jorion2006>, form: "prose") talvez tenha uma das mais simples
e intuitivas: risco é a volatilidade dos resultados inesperados, que podem representar o valor de ativos, patrimônios ou resultados. E esse risco pode ser originado de várias formas,
criados pelos humanos como ciclos de negócios, inflação, mudanças políticas, guerras, etc., ou podem ocorrer devido a fenômenos naturais como terremotos, tsunamis, etc. É na tentativa de 
combater esses riscos que a economia cresce e as tecnologias se desenvolvem. 

Parte significativa do mercado financeiro atual foi desenvolvida na tentativa de lidar ou compartilhar esses riscos. Ao mesmo tempo que o mercado se desenvolveu,
se gerou a necessidade de limitar as perdas potenciais sem deixar de tomar risco. Existem controles *ex post*, mas esses não conseguem garantir que as perdas sejam 
próximas ao limite desejado; ao depender da sorte, podem ser maiores. A solução é o uso de modelos quantitativos *ex ante* que limitam a exposição a determinados ativos
ou fatores de risco baseados em distribuições de probabilidade, como por exemplo os modelos de *Value at Risk*.

== Value-at-Risk e Modelos da Família GARCH

O *Value at Risk* (VaR) pode ser definido de forma intuitiva como a maior perda esperada de uma carteira em um determinado período de tempo, com um determinado nível de confiança. Ou,
de forma mais formal, é o quantil da distribuição de ganhos e perdas projetadas para um horizonte de tempo. Muitas vezes para séries temporais, essa projeção é feita por 
meio de modelos como o GARCH, que apesar de ser amplamente utilizado, falha em choques assimétricos, como observamos nos eventos recentes envolvendo o Grupo Pão de Açúcar e Americanas.
Para superar essa fraqueza do modelo GARCH, #cite(<nelson1991conditional>, form: "prose") propõe o modelo EGARCH, que captura assimetrias na volatilidade dos ativos financeiros.

Matematicamente, a especificação da variância condicional do EGARCH(1,1) de Nelson (1991) é dada por:

#set math.equation(numbering: "(1)")
$ ln(sigma_t^2) = omega + alpha [ |z_(t-1)| - sqrt(2 / pi) ] + gamma z_(t-1) + beta ln(sigma_(t-1)^2) $ <eq_egarch>

Onde:
- $sigma_t^2$ é a variância condicional no tempo $t$.
- $z_t$ é o resíduo padronizado ($z_t = epsilon_t \/ sigma_t$).
- $alpha$ mensura o "efeito tamanho" (a magnitude do choque).
- $gamma$ captura o *efeito assimétrico* (o sinal do choque).
- $beta$ mede a persistência da volatilidade.

Se $gamma < 0$, choques negativos em $t-1$ aumentam a variância em $t$ mais do que choques positivos da mesma magnitude, diferentemente do modelo GARCH tradicional.

== A Hipótese de Mudança de Regimes (Regime-Switching)

Porém, mesmo o modelo EGARCH que possui o tratamento da assimetria dos retornos possui limitações. A família GARCH, como explicado por #cite(<tsay2005analysis>, form: "prose"), assume que
os parâmetros do modelo (ou seja, os pesos $omega$, $alpha$, $gamma$ e $beta$ da Equação @eq_egarch) e a "variância incondicional" não mudam ao longo do tempo. Eles são constantes, baseados em uma única média do comportamento global da série.

Devido a essa constância, esses modelos tem dificuldade em se adaptarem quando existe uma quebra de regime, como os eventos de crédito que foram comentados acima, que uma vez divulgados,
alteraram toda a dinâmica de negociação e preço dos papéis, as informações que foram observadas antes do evento não são mais tão relevantes para prever o comportamento futuro
dos ativos afetados. #cite(<hamilton1994time>, form: "prose") mostra que essas quebras estruturais ocorrem na maioria das series macroeconomicas ou financeiras que possuem um período
suficientemente longo. Como solução a esse problema, o autor propõe a hipótese de mudanças de regime (*Regime-Switching*). Segundo essa teoria, a economia e os mercados não têm um estado único. 
Eles transitam entre diferentes estados, onde as equações que regem os preços mudam dependendo do regime atual. Para solucionar esse problema, foi proposto a utilização de Cadeias de Markov para modelar a transição entre diferentes estados da economia.

== Aprendizado de Máquina Não Supervisionado: K-Means e HMM

Enquanto alguns autores na literatura propõem a integração direta (como os modelos MS-GARCH unificados), uma abordagem moderna e altamente escalável para o risco de crédito utiliza algoritmos de Aprendizado de Máquina (*Machine Learning*) não supervisionados para classificar os regimes de mercado.

Neste trabalho, adotam-se dois modelos distintos para agrupar e classificar os regimes de risco, utilizando como *features* (variáveis de entrada) o *spread* de crédito e a volatilidade extraída pelo modelo EGARCH:

1. *K-Means:* Um algoritmo de clusterização baseado em distância. O K-Means particiona os dados em $K$ grupos distintos, minimizando a variância intra-cluster. Embora seja extremamente eficiente para separar períodos de alta e baixa volatilidade/spread de forma estática, ele ignora a dependência temporal (a probabilidade de transição de um dia para o outro).
2. *Hidden Markov Models (HMM):* Diferentemente do K-Means, o HMM é um modelo probabilístico que assume que o sistema é um processo de Markov com estados não observáveis (ocultos). Ele não apenas agrupa os dados baseando-se nas emissões (volatilidade e spread), mas também estima a *matriz de transição* entre os regimes, capturando perfeitamente a dinâmica temporal de "entrar" e "sair" de uma crise.