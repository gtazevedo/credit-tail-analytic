= Introdução

O mercado de crédito privado brasileiro vem crescendo continuamente, e se consolidando como uma ferramenta de captação de recursos para as empresas, como se pode observar em @anbima2026recorde. Uma das principais ferramentas de crédito privado utilizadas são as debêntures, que tiveram um crescimento de 307% no volume de emissões quando comparamos o volume observado em 2020 contra o volume observado em 2025. 
Porém, esse mercado enfrenta problemas de liquidez, e conforme @sheng2008liquidez, apresenta as seguintes características:

- As transações são dispersas e ocorrem em duas diferentes instituições - Bolsa de Valores de São Paulo (Bovespa Fix) e Sistema Nacional de Debêntures (SND);
- Existe baixa atividade, não havendo registro de transações para períodos longos e, em algumas emissões de debêntures, o volume de transações no mercado secundário é quase nulo e o valor total em reais é baixo;
- Existe um baixo número de negociações diárias;
- Predominância de debêntures de médio prazo (vencimento em torno de quatro anos);
- Demanda significativa por investidores institucionais e fundos de pensão;
- Em geral as emissões não são conversíveis em ações;
- Alguns investidores adquirem debêntures e as mantêm até o vencimento;

Apesar de algumas dessas características estruturais se manterem verdadeiras, como:
- A baixa liquidez (onde mais da metade das marcações diárias do mercado giram volumes inferiores a R\$ 1 milhão);
- A exclusividade de emissões do tipo simples;

e outras características, como:
- A baixa presença de pessoas físicas e investidores estrangeiros;
- O fato de os intermediários manterem os papéis na carteira até o vencimento;

serem reforçadas por estudos mais recentes como @barra2021estudo e @anbima2026recorde, houve algumas mudanças relevantes que sugerem um amadurecimento institucional. A amostra deste estudo indica que as empresas têm conseguido alongar o perfil de suas dívidas, com as debêntures apresentando uma mediana de sete anos de prazo até o vencimento.

== O Problema de Pesquisa

Apesar do crescimento e amadurecimento do mercado de crédito privado brasileiro, a baixa liquidez no mercado secundário representa um desafio para a precificação e acompanhamento de risco do papel.
Estudos como @correa2010aprecamento focam em problemas de apreçamento do spread de crédito, enquanto estudos como @sheng2008liquidez analisam os fatores que afetam o prêmio de liquidez em debêntures. 
Contudo, muitos modelos assumem situações normais de mercado, enquanto outros fazem suposições ainda mais fortes que não condizem com a realidade do mercado brasileiro. Bancos e assets muitas vezes seguem
controlando o risco de cauda de debêntures baseado em GARCH e VaR contínuos, que possuem suposições violadas quando ocorrem eventos extremos, e podem estar subestimando o risco observado.

Como demonstrado por @bao2011illiquidity, o mercado de crédito corporativo apresenta fricções de liquidez que impedem o ajuste contínuo dos preços, eventos recentes envolvendo o Grupo Pão de Açucar e Americanas são exemplos dos 
saltos observados nos precos das debêntures desses emissores; No caso das Americanas, houve uma queda de 50% no valor das debentures em um dia, acumulando perdas de cerca de 90% em uma semana; Já no caso do Grupo Pão de Açucar,
foram observados deságios de até cerca de 70%. Nessas situações, modelos GARCH e VaR tradicionais falham em capturar o risco de cauda, uma vez que segundo @jorion2006, assumem que a liquidação será instantanea a preço de tela.
Para corrigir essas suposições e capturar quebras estruturais, a literatura mais moderna defende a transição para modelos baseados em mudanças de regime (Markov-Switching), conforme proposto por @haas2004new e @ardia2019markov.

== Objetivos (Geral e Específicos)

A proposta desse trabalho é desenvolver e avaliar os resultados de uma modelagem de risco de crédito adotada a realidade do mercado brasileiro de debêntures. Ao invés de tentarmos
prever flutuações contínuas, o modelo busca identificar eventos de mudança de regime para disparar alertas de risco antes de que se observem grandes perdas, possibilitando ao detentor das
debentures, um tempo hábil para tentar vender o papel antes que as perdas se materializem.  

Para isso, serão utilizadas duas abordages de modelagem de risco, uma baseada em K-Means e outra em HMM, ambas utilizando como features a volatilidade e o spread das debentures, utilizando dados
abertos divulgados pela Anbima. Além disso, toda a aplicação, feita em python, será disponibilizada para consulta pública no github, permitindo que qualquer interessado possa replicar os resultados,
incluindo o download das informações utilizadas no trabalho, já que os dados são públicos.
