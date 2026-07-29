= Revisão da Literatura <cap_revisao_lit>

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

Enquanto alguns autores na literatura propõem a integração direta (como os modelos MS-GARCH unificados), neste trabalho adotam-se dois modelos tintos para agrupar e classificar os regimes de risco
utilizando como variáveis de entrada o *spread* de crédito e a volatilidade extraída pelo modelo EGARCH. Esses modelos são:

=== K-Means

Um algoritmo popular para problemas de clusterização é o *K-means* que particiona os dados em $K$ grupos distintos, minimizando a variância intra-cluster. Para utilizá-lo no problema
em questão, foram criados três clusters de acordo com o nível de risco do papel, de forma que o esperado é que conforme um papel começa apresentar durante o seu período de negociação
uma variação mais errática do seu spread ele vá migrando do cluster de baixo ao cluster de alto risco.

Para entender melhor essa aplicação vamos tomar como base #cite(<bishop2006pattern>, form: "prose"), em nosso problema temos que identificar grupos ou *clusters* de dados em um espaço multidimensional.
Suponha que esse espaço seja dado por $\{x_1, x_2, dots, x_N\}$ onde cada um dos $N$ pontos no espaço multidimensional é um vetor de dimensão $D$.

O objetivo do algoritmo de K-means é particionar os dados em $K$ grupos distintos, de forma que a soma do quadrado das distancias de cada ponto com o vetor
$\mu_k$ mais próximo seja minimizada. Ou de forma mais formal: 


$ J = sum_{n=1}^N sum_{k=1}^K r_{n k} || x_n - mu_k ||^2 $ <eq_kmeans>

Onde $r_{n k} in \{0, 1\}$ é uma variável indicadora que assume o valor $1$ se o ponto $x_n$ for atribuído ao *cluster* $k$ (e $0$ caso contrário), 
enquanto $mu_k$ representa o vetor centroide do *cluster* $k$. O objetivo é encontrar os valores de ${r_{nk}}$ e ${mu_k}$ que minimizam $J$. Isso pode ser realizado por meio de um
processo iterativo; para mais detalhes recomenda-se consultar #cite(<bishop2006pattern>, form: "prose").

Apesar de sua eficiência em separar os períodos de forma estática, minimizando $J$, 
o K-Means é cego para o tempo: ele ignora a probabilidade de transição de um dia para o outro, e como será analisado posteriormente, isso dá maior estabilidade aos resultados, porém,
faz com seu tempo de reação seja mais lento, ou em alguns casos seja insensível devido a uma quebra de regime abrupta.

=== Hidden Markov Models (HMM)

Para corrigir a imperfeição temporal do K-Means, utiliza-se o HMM, um modelo probabilístico ideal para utilização em dados sequenciais. 
Conforme detalhado por #cite(<bishop2006pattern>, form: "prose"), o HMM parte do princípio de que os dados que medidos no mercado 
(como, por exemplo, o *spread* e a volatilidade) são reflexos de um estado que não pode ser observado.
Esse estado é a causa do comportamento dos preços, e é chamado de **variável latente** (ou *hidden state*).

Seja $z_n$ a variável latente que representa o estado ou regime oculto do mercado no tempo $n$ . 
No HMM, assume-se que o comportamento do variável observada é gerado por um processo de Markov onde a probabilidade do estado atual $z_n$ 
depende diretamente do estado imediatamente 
anterior $z_{n-1}$, o que é expresso por meio de uma distribuição condicional $p(z_n | z_{n-1})$.

Como as variáveis latentes assumem um conjunto finito de $K$ regimes categóricos (neste estudo, 3 níveis de risco), 
essa distribuição condicional $p(z_n | z_{n-1})$ corresponde matematicamente a uma tabela de valores que denotaremos pela matriz $A$. 
Os elementos dessa matriz $A$ são conhecidos como *probabilidades de transição* e representam a chance do mercado migrar do regime $i$ para o regime $j$ de um instante de 
tempo para o outro.

Isso é similar ao tratamento que se faz com matrizes de transição de rating, onde assume-se que uma empresa com rating AAA tem uma chance $p_{AAA \to AA}$ de migrar para o rating AA 
em um dado ano, uma chance $p_{AAA \to A}$ de migrar para o rating A, e assim sucessivamente.

Dessa forma, o HMM não apenas agrupa os dados de forma estática com base nas emissões observadas (volatilidade e *spread*), mas também estima a matriz de transição estocástica $A$. 
É justamente o uso das variáveis latentes $z_n$ e $z_{n-1}$ que permite ao modelo capturar a 
inércia do mercado de debêntures e modelar a dinâmica de transições entre regimes.