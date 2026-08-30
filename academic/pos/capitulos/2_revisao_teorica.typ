= Revisão da Literatura <cap_revisao_lit>

A ideia central deste trabalho parte da modelagem de risco de crédito de debêntures. Mas, para entender esse conceito, é necessário entender primeiramente, 
"O que é risco?". Existem várias definições, #cite(<jorion2006>, form: "prose") possui uma das mais simples
e intuitivas, na qual afirma que risco é a volatilidade dos resultados inesperados, seja no valor de ativos, patrimônio ou resultados. E esse risco pode ser originado de várias formas,
criados pelos humanos, por meio de ciclos de negócios, inflação, mudanças políticas, guerras, etc., ou pode ocorrer devido a fenômenos naturais como terremotos, tsunamis, etc. É na tentativa de 
combater e mitigar esses riscos que a economia cresce e as tecnologias se desenvolvem. 

Parte significativa do mercado financeiro atual foi desenvolvida na tentativa de lidar ou compartilhar esses riscos. Ao mesmo tempo que o mercado se desenvolveu,
foi gerada a necessidade de limitar as perdas potenciais das operações realizadas, sem deixar de tomar risco. Existem controles _ex post_, mas esses não conseguem garantir que as perdas sejam 
próximas ao limite desejado, ao depender da sorte, podem ser maiores. A solução é o uso de modelos quantitativos _ex ante_ que limitam a exposição a determinados ativos
ou fatores de risco baseados em distribuições de probabilidade, como por exemplo os modelos de _Value at Risk_.

== Modelos de Early Warning de Crédito

Os primeiros sistemas formais de alerta de _distress_ corporativo remontam ao
modelo de #cite(<altman1968>, form: "prose"), que utiliza combinações lineares de indicadores 
fundamentais (Altman Z-Score) para prever insolvência. Desde então, a literatura evoluiu para
abordagens baseadas em modelos estruturais de crédito #cite(<merton1974>), contudo, as abordagens 
tradicionais baseadas em fundamentos, obtidos em balanços e informações contábeis, geralmente divulgados
em frequência trimestral ou anual, são inadequados para sistemas de alerta em tempo real (ou com poucos dias
de defasagem) devido à frequência de divulgação dessas informações.

Para superar a dependência de demonstrações financeiras, surgiram os modelos de forma reduzida, 
conforme consolidado por #cite(<duffie2003>, form: "prose"), que modelam o risco de 
crédito diretamente através de dados de mercado. Porém, apesar de serem capazes de mitigar a
defasagem da informação contábil, a modelagem contínua exige mercados líquidos, uma vez que é 
amplamente dependente dos dados observados. No mercado de debêntures brasileiro, onde se observa
baixa liquidez e baixa atividade, essa abordagem se mostra frágil. 

Na tentativa de mitigar este problema, este trabalho propõe uma abordagem alternativa. Ao invés de mensurar o risco 
dos papéis e estimar possíveis perdas, limita-se apenas a identificar momentos em que ocorrem mudanças de regime, através 
do uso de algoritmos de aprendizado de máquina, para gerar alertas antecipados sobre a possibilidade de grandes perdas,
apesar de não ser capaz de estimá-las, como é feito por outros modelos, como o Value at Risk (VaR). 

== Value-at-Risk e Modelos da Família GARCH <subcap_vargarch>

O _Value at Risk_ (VaR) pode ser definido de forma intuitiva como a maior perda esperada de uma carteira em um determinado período de tempo, com um determinado nível de confiança. Ou,
de forma mais formal, é o quantil da distribuição de ganhos e perdas projetadas para um horizonte de tempo. Muitas vezes para séries temporais, essa projeção é feita por 
meio de modelos da família GARCH (_Generalized Autoregressive Conditional Heteroskedasticity_), cuja formulação fundamental foi introduzida por #cite(<engle1982autoregressive>, form: "prose")
e posteriormente generalizada por #cite(<bollerslev1986generalized>, form: "prose"). Apesar de amplamente utilizado, o GARCH tradicional falha em choques assimétricos, como observamos nos 
eventos recentes envolvendo o Grupo Pão de Açúcar e Americanas.
Para superar essa fraqueza, #cite(<nelson1991conditional>, form: "prose") propõe o modelo EGARCH, que captura assimetrias na volatilidade dos ativos financeiros.

Matematicamente, a especificação da variância condicional do EGARCH(1,1) de #cite(<nelson1991conditional>, form: "prose") é dada por:

#set math.equation(numbering: "(1)")
$ ln(sigma_t^2) = omega + alpha [ |z_(t-1)| - sqrt(2 / pi) ] + gamma z_(t-1) + beta ln(sigma_(t-1)^2) $ <eq_egarch>

Onde:
- $sigma_t^2$ é a variância condicional no tempo $t$.
- $z_t$ é o resíduo padronizado ($z_t = epsilon_t \/ sigma_t$).
- $alpha$ mensura o "efeito tamanho" (a magnitude do choque).
- $gamma$ captura o *efeito assimétrico* (o sinal do choque).
- $beta$ mede a persistência da volatilidade.

Se $gamma < 0$, os choques negativos em $t-1$ aumentam a variância em $t$ mais do que choques positivos da mesma magnitude, adicionando a possibilidade de efeitos assimétricos, diferentemente do modelo GARCH tradicional.

Contudo, além da assimetria, os retornos de ativos de crédito exibem forte leptocurtose (caudas pesadas), onde perdas extremas ocorrem com frequência superior ao previsto pela distribuição normal.  Para contornar 
este problema, a modelagem EGARCH pode ser combinada a uma distribuição T de Student condicional, que permite modelar as caudas da distribuição por meio dos graus de liberdade nu$$.

=== Expected Shortfall (ES) e Testes de Backtesting

Apesar de sua ampla adoção, o VaR apresenta uma limitação matemática: ele não é uma medida de risco subaditiva e, consequentemente, não é uma métrica "coerente" 
de risco, conforme #cite(<artzner1999>, form: "prose"). Em outras palavras, ele responde apenas à pergunta "Qual é a perda máxima esperada com 99% de confiança?", 
sendo cego em relação ao que ocorre na cauda extrema, ou seja, ele desconsidera, no nosso exemplo (supondo um VaR a 99%), os 1% da distribuição e os impactos de um possível evento dessa cauda.

Para solucionar essa limitação, a literatura e regulações como Basileia III têm migrado para o _Expected Shortfall_ (ES) #cite(<acerbi2002>), que calcula a perda média esperada condicionada 
ao nível de confiança. Diferentemente do VaR, o ES é uma métrica de risco coerente e possibilita uma avaliação mais robusta da magnitude das perdas extremas, porque, enquanto o VaR nos diz qual a perda máxima esperada,
por exemplo, para um dia com 99% de confiança, o ES nos informa qual a perda média esperada, caso ocorra um evento de quebra do VaR (ou seja, considerando os piores 1% dos cenários, para nosso exemplo de 99% de confiança). 

Adicionalmente, modelos de estimação de risco requerem validação estatística (_Backtesting_). Os dois métodos tradicionalmente utilizados para a validação do VaR são:
- *Teste de Proporção de Falhas (POF) de Kupiec* #cite(<kupiec1995techniques>): Avalia a "Cobertura Incondicional", ou seja, verifica se a quantidade total de falhas (quebras do limite do VaR) é estatisticamente idêntica à proporção esperada.
- *Teste de Independência e Teste Conjunto de Christoffersen* #cite(<christoffersen1998>): Avalia a "Cobertura Condicional". Testa se as violações do VaR ocorrem de forma agrupada no tempo (_volatility clustering_). Se as violações forem estatisticamente independentes, o modelo prova que capturou e exauriu corretamente a dinâmica temporal da variância, resultando em um modelo validado no Teste Conjunto (que unifica e avalia simultaneamente a Cobertura Incondicional e a Independência).

Para formalizar a validação empírica do motor de volatilidade frente às anomalias discutidas, este estudo adota a seguinte hipótese:

- *H0₁*: O modelo EGARCH-t *não* produz uma taxa de falhas estatisticamente compatível com o nível de confiança de 99% estipulado, ou seja, a frequência empírica de violações 
do VaR difere significativamente de 1%.
- *H1₁*: O modelo EGARCH-t produz uma taxa de falhas estatisticamente compatível com 1%, e as violações ocorrem de forma independente no tempo.

A rejeição generalizada de H0₁ no portfólio analisado indicaria inadequação estrutural do filtro de volatilidade para capturar as dinâmicas de cauda pesada no mercado secundário de debêntures.

== A Hipótese de Mudança de Regimes (Regime-Switching)

Porém, mesmo o modelo EGARCH que possui o tratamento da assimetria dos retornos, possui limitações. A família GARCH, como explicado por #cite(<tsay2005analysis>, form: "prose"), assume que
os parâmetros do modelo (ou seja, os pesos $omega$, $alpha$, $gamma$ e $beta$ da @eq_egarch) e a "variância incondicional" não mudam ao longo do tempo. Eles são constantes, 
baseados em uma única média do comportamento global da série.

Devido a essa constância, esses modelos têm dificuldade em se adaptarem quando existe uma quebra de regime, como os eventos de crédito que foram comentados acima, que uma vez divulgados,
alteram a dinâmica de negociação e preço dos papéis. As informações observadas antes do evento deixam de possuir a mesma relevância para prever o comportamento futuro
dos ativos afetados. #cite(<hamilton1994time>, form: "prose") mostra que tais quebras estruturais ocorrem na maioria das séries macroeconômicas ou financeiras que possuem um período
suficientemente longo. Como solução a esse problema, o autor propõe a hipótese de mudanças de regime (_Regime-Switching_). Segundo essa teoria, a economia e os mercados não têm um estado único, 
eles transitam entre diferentes estados, onde as equações que regem os preços mudam dependendo do regime atual, e devido a isso, foi proposta a utilização 
de Cadeias de Markov para modelar a transição entre diferentes estados da economia, uma vez que elas modelam o estado futuro como um estado dependente apenas do anterior.

== Aprendizado de Máquina Não Supervisionado

Enquanto alguns autores na literatura propõem a integração direta (como os modelos MS-GARCH unificados), neste trabalho adotam-se algoritmos não supervisionados para agrupar e classificar os regimes 
de risco latentes. 

Algoritmos de clusterização baseados em distância espacial euclidiana são extremamente sensíveis a valores discrepantes (_outliers_) e grandezas numéricas não uniformes. No mercado de debêntures, 
onde os ativos apresentam distorções bruscas, a padronização dos dados (pré-processamento) é indispensável. Ao invés da utilização de escalonadores tradicionais, a literatura, como em #cite(<rousseeuw2011robust>, form: "prose") sugere o uso de 
padronizadores baseados em quantis, como o `RobustScaler`. Este algoritmo subtrai a mediana e divide os dados pelo intervalo interquartil (IQR, ou seja, a diferença entre o 3º e o 1º quartil),  
mitigando estatisticamente o peso das caudas anômalas (_outliers_) e permitindo que o agrupador avalie a matriz de características 
livre de distorções induzidas por anomalias momentâneas.

=== K-Means

Um algoritmo popular para problemas de clusterização é o _K-means_ que particiona os dados em $K$ grupos distintos, minimizando a variância intra-cluster. Para utilizá-lo no problema
em questão, foram criados três clusters de acordo com o nível de risco do papel, de forma que o esperado é que, conforme um papel começe a apresentar, durante o seu período de negociação,
uma variação mais errática do seu _spread_, ou seja, um aumento da volatilidade do _spread_, ele vá migrando do cluster de baixo ao cluster de alto risco.

Para entender melhor essa aplicação vamos tomar como base #cite(<bishop2006pattern>, form: "prose"), em nosso problema temos que identificar grupos ou _clusters_ de dados em um espaço multidimensional.
Suponha que esse espaço seja dado por $\{x_1, x_2, dots, x_N\}$ onde cada um dos $N$ pontos no espaço multidimensional é um vetor de dimensão $D$.

O objetivo do algoritmo de K-means é particionar os dados em $K$ grupos distintos, de forma que a soma do quadrado das distâncias de cada ponto com o vetor
$mu_k$ mais próximo seja minimizada. Ou de forma mais formal: 

$ J = sum_{n=1}^N sum_{k=1}^K r_(n k) || x_n - mu_k ||^2 $ <eq_kmeans>

Onde $r_(n k) in \{0, 1\}$ é uma variável indicadora binária, tal que $r_(n k) = 1$ se o ponto $x_n$ foi alocado ao _cluster_ $k$, e $r_(n j) = 0$, caso contrário (para $j != k$). Por sua vez, 
$mu_k$ representa o vetor centroide do _cluster_ $k$. O objetivo é encontrar os valores de $r_(n k)$ e os centroides $mu_k$ que minimizam a função $J$. Isso é comumente realizado por meio de um
algoritmo iterativo dividido em duas etapas, conhecido como Algoritmo de Lloyd (ou, mais genericamente, algoritmo de maximização de expectativa (EM)).

O modelo, por vezes apresenta um problema conhecido como _Label Switching_, no qual os centroides gerados recebem rótulos arbitrários, 
isso ocorre porque o algoritmo inicializa os centroides ($mu_k$) de forma aleatória e busca minimizar a soma das distancias quadráticas (conforme a @eq_kmeans), 
independentemente dos rótulos atribuídos aos centróides. Porém, existem muitas formas conhecidas de tratar esse problema. A forma adotada nesse trabalho será detalhada em @subcap_kmeans, 
mas envolve a aplicação de um vetor de polaridade de risco para fixar os rótulos nos regimes Verde (baixo risco), Amarelo (alerta) e Vermelho (crise).

Apesar de sua eficiência em separar os períodos de forma estática, minimizando $J$, 
o K-Means é cego para o tempo: ele ignora a probabilidade de transição de um dia para o outro. Como será analisado posteriormente, essa ausência de memória probabilística gera dois efeitos práticos,
observados nessa pesquisa: por um lado, causa instabilidade na manutenção do regime (problemas de _flickering_ nas fronteiras dos _clusters_); por outro, exige deslocamentos geométricos 
mais severos para confirmar uma mudança definitiva de estado. Isso torna seu tempo de reação mais lento (inércia geométrica), o que pode torná-lo insensível a quebras de regime abruptas, 
mas atua, paradoxalmente, como um filtro de ruídos nas simulações financeiras realizadas na etapa de Backtest.

=== Hidden Markov Models (HMM)

Para corrigir a imperfeição temporal do K-Means, utiliza-se o HMM (_Hidden Markov Model_), um modelo probabilístico estruturado classicamente por #cite(<rabiner1989tutorial>, form: "prose") e 
adotado para modelagem de dados sequenciais com estados latentes. 
Conforme detalhado por #cite(<bishop2006pattern>, form: "prose"), o HMM parte do princípio de que os dados observados
(como o _spread_ e a volatilidade) são reflexos de um estado (chamado de variável latente ou _hidden state_), que não 
pode ser observado diretamente e que é a causa do comportamento dos preços.

Seja $z_n$ a variável latente que representa o regime oculto do mercado no tempo $n$. 
No HMM, a dinâmica temporal é regida por um processo de Markov onde a probabilidade do estado atual $z_n$ 
depende estritamente do estado imediatamente anterior $z_{n-1}$, denotado por $p(z_n | z_{n-1})$.

Como as variáveis latentes assumem $K$ regimes categóricos (neste estudo, 3 regimes de risco, detalhados em @subcap_kmeans_k3), 
essa distribuição corresponde matematicamente à matriz de transição de estados $A$. Adicionalmente, o modelo é governado 
pelas probabilidades de emissão $B$, que descrevem a distribuição contínua das observações $x_n$ dado o estado $z_n$ (modeladas aqui 
por distribuições Gaussianas), e pelo vetor de probabilidades iniciais $pi$, logo, o modelo é parametrizado por $theta = \{A, B, pi\}$.

Segundo #cite(<rabiner1989tutorial>, form: "prose"), a viabilidade do HMM depende da solução matemática de dois problemas  
presentes na arquitetura do motor de risco: a calibração dos parâmetros $theta$ e a decodificação da sequência ótima de regimes.

Para calibração do HMM de forma não supervisionada, utiliza-se o algoritmo de *Baum-Welch*, um caso especial do algoritmo de _Expectation-Maximization_ (EM). 
Na etapa de Expectativa (*E-Step*), estimam-se as probabilidades de cada estado usando o procedimento _Forward-Backward_ formalizado por 
#cite(<baum1970maximization>, form: "prose"), já a etapa _Forward_ calcula as probabilidades observando o histórico até $n$, 
denotado por $alpha(z_n)$, enquanto a etapa _Backward_ 
condensa a probabilidade sob a ótica do futuro de $n$ em diante, denotado por $beta(z_n)$.

Na etapa de Maximização (*M-Step*), as matrizes $A$, $B$ e o vetor $pi$ são iterativamente atualizados por Máxima Verossimilhança até a convergência. 
Uma vez calibrado o HMM, a identificação do nível de risco no tempo $n$ é realizada filtrando a probabilidade condicional de cada regime, decodificando a 
trajetória oculta mais provável via *Algoritmo de Viterbi*, dessa forma, o HMM captura simultaneamente a topologia multivariada dos dados e a inércia estrutural das transições de crédito.

== Seleção de Atributos e Avaliação de Clusters <sub_cap_clusters>

Para que os algoritmos não-supervisionados (como o K-Means) convirjam para partições representativas, a escolha adequada das variáveis de entrada é crucial. Como, diferentemente de algoritmos supervisionados, não existem os rótulos esperados
para guiar os modelos, a qualidade do agrupamento deve ser mensurada matematicamente por meio de métricas de validação interna da geometria dos grupos gerados:

1. _Silhouette Score_ (#cite(<rousseeuw1987silhouettes>, form: "prose")): Mede a coesão intra-_cluster_ frente à separabilidade inter-_cluster_, variando no intervalo $[-1, 1]$. Nesta métrica, valores maiores indicam melhor adequação, ou seja, valores próximos a 1 
sugerem clusters perfeitamente densos e bem separados, enquanto valores próximos a 0 ou negativos indicam forte sobreposição.
2. *Índice Davies-Bouldin* (#cite(<davies1979cluster>, form: "prose")): Avalia a razão média da dispersão interna do _cluster_ pela distância euclidiana entre os centroides, penalizando sobreposições. Diferente do Silhouette, nesta métrica valores menores indicam melhor adequação, pois 
um índice menor (com limite inferior tendendo a zero) significa que os clusters são compactos internamente e distantes uns dos outros.
3. *Índice Calinski-Harabasz* (#cite(<calinski1974dendrite>, form: "prose")): Mensura a razão entre a variância inter-_cluster_ e a variância intra-_cluster_, ponderada pelos graus de liberdade do sistema. Para este índice, valores maiores indicam melhor adequação, 
denotando que a distância entre os centros dos clusters é expressivamente maior que a dispersão dos pontos dentro de cada regime.

Dado que não existe uma solução unificada no Aprendizado de Máquina, frequentemente estas três métricas fornecem orientações sobre qual o melhor particionamento, então, a solução matemática para este problema repousa sobre as 
heurísticas de consenso, combinando os resultados de cada métrica. O *Método de Borda* (*Borda Count*), tradicionalmente um sistema de votação, foi introduzido por #cite(<borda1781>), contudo, sua adaptação computacional
moderna o torna um mecanismo imparcial e poderoso para consolidar múltiplos sistemas de classificação e validação multivariada, sendo amplamente estendido na 
literatura moderna de Aprendizado de Máquina, e validado na construção de classificadores de consenso por 
#cite(<ho1994decision>, form: "prose") e #cite(<kittler1998combining>, form: "prose"), bem como na seleção robusta de atributos (_ensembles_) por #cite(<saeys2008robust>, form: "prose"). No contexto deste trabalho, 
as _features_ são pontuadas pela posição ordinal que alcançaram em cada métrica isolada, combinando os resultados pelo *Método de Borda*, mitiga-se o viés individual de cada métrica e se converge para o subconjunto dimensionalmente mais robusto.