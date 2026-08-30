= Conclusão

Esta dissertação teve como objetivo desenvolver e avaliar uma metodologia quantitativa baseada em Aprendizado de Máquina Não Supervisionado para a identificação precoce 
de eventos de estresse (_Early Warning_), por meio da criação e monitoramento de regimes de risco no mercado secundário de 
debêntures brasileiro. Motivada pela assimetria de retornos inerente aos ativos de crédito privado, pela baixa liquidez estrutural e pelos recentes e severos eventos de crédito 
(como os casos Lojas Americanas, Light e Grupo Pão de Açúcar), a pesquisa buscou responder se algoritmos de clusterização poderiam atuar como ferramentas táticas 
viáveis para a mitigação de perdas severas, superando o carrego passivo de portfólios.

== Principais Descobertas

O estudo revelou achados importantes que conectam a modelagem teórica à aplicabilidade financeira prática:

1. *Adequação da Modelagem de Cauda (EGARCH-t):* A adoção do modelo EGARCH-t acoplado ao _Expected Shortfall_ provou-se eficaz na precificação do risco isolado dos ativos. A validação por meio dos 
testes conjuntos de Christoffersen, conforme apresentado na @subcap_valest, confirmou que o modelo é capaz de absorver a heterocedasticidade condicional e evitar o agrupamento de violações (_volatility clustering_), 
mesmo frente aos massivos choques de iliquidez do período _Out-of-Sample_, respondendo, assim, às falhas dos modelos de VaR tradicionais citados na @subcap_vargarch.

2. *O Paradoxo entre Acurácia Preditiva e Desempenho Financeiro:* Observou-se uma dicotomia robusta e quantificada entre o Modelo Oculto de Markov (HMM) e o particionamento geométrico atemporal (K-Means). Conforme 
demonstrado através da análise sistêmica de *Lead Time* (Antecipação de Alerta), o HMM demonstrou superioridade analítica preditiva ao integrar a dependência temporal via matrizes de transição, antecipando eventos de crédito 
severos de forma significativamente mais ágil que as demais metodologias em múltiplos cenários corporativos independentes (como no caso da CVC Corp e do Grupo Pão de Açúcar). Contudo, no _backtest_ financeiro, a estratégia de liquidação 
pautada pelo K-Means (*Vende Amarelo*) não apenas entregou o maior retorno financeiro absoluto do período (36,18%), mas foi a *única* capaz de superar a estratégia passiva (_Buy-and-Hold_) com significância estatística comprovada por _Block Bootstrap_
(p-valor < 0,05). Este fenômeno consolida empiricamente o impacto do *Paradoxo da Acurácia-Rentabilidade* (_Accuracy-Profitability Paradox_): a inércia do K-Means funcionou como um filtro de ruído contra a volatilidade secundária, 
poupando a carteira do excesso de giro impulsionado pelas matrizes de transição do HMM. Em cenários de iliquidez e altos custos de transação (0,5% por operação), essa ineficiência preditiva transmuta-se, paradoxalmente, em proteção de capital.

3. *A Armadilha da Combinação de Modelos:* O estudo documentou a falha do modelo _Ensemble_. Ao tentar fundir a reatividade do HMM com a inércia do K-Means, 
a modelagem mista deixou a carteira vulnerável ao efeito chicote (_whipsaw_). O modelo realizava vendas impulsionadas pelo HMM e recompras tardias pelo K-Means, 
corroendo o capital com excesso de custos transacionais, entregando o pior retorno do período. A combinação acabou exacerbando os defeitos de cada modelo, e reforçando 
a importância da avaliação do momento de compra e venda dos papéis para evitar que o carrego obtido seja consumido por custos transacionais e perdas decorrentes
de operações em momentos inoportunos.

== Implicações Práticas

Para a indústria de gestão de recursos, a metodologia desenvolvida oferece um arcabouço robusto e sistemático para a gestão tática em carteiras de crédito privado. Em um mercado caracterizado por baixa liquidez estrutural 
e precificação ocasionalmente defasada, a adoção de gatilhos quantitativos pode substituir ou auxiliar o viés comportamental humano, que frequentemente leva gestores a reter posições perdedoras na esperança de uma reversão que muitas vezes não ocorre.

A operacionalização desta pesquisa demonstra que o melhor modelo preditivo não é, necessariamente, a melhor estratégia de _trading_. A escolha do motor de decisão deve estar alinhada aos atritos do mercado e às regras táticas de execução 
(como, por exemplo, a regra de "quarentena de 180 dias", que atuou como ponte operacional para viabilizar os sinais do K-Means). Os resultados observados foram frutos de simulações históricas baseadas em parâmetros de 
_Backtest_ (custo de 0,5% e liquidez plena); na prática real de tesouraria, o momento exato do _early warning_ sofrerá o impacto do secamento do _bid-ask spread_, reiterando que o alerta não garante, por si só, 
o sucesso da liquidação em mercados de crédito ilíquidos.

== Limitações e Recomendações para Trabalhos Futuros

Apesar dos resultados promissores, o presente estudo possui limitações inerentes à estrutura e à qualidade dos dados financeiros brasileiros. A principal limitação concentrou-se na convergência da volatilidade condicional (EGARCH) 
para ativos extremos, onde longos históricos de ausência de negociação distorceram a estimação dos parâmetros de risco no período _In-Sample_. Adicionalmente, ao pautar a modelagem em dados de negócios efetivamente realizados 
(mitigando o viés da marcação a mercado teórica), o sistema herda uma dependência do fluxo contínuo de liquidez secundária, o que significa que o modelo pode ficar "cego" nos momentos de maior estresse, quando o mercado 
cessa suas negociações.

Para trabalhos futuros, recomenda-se a exploração das seguintes frentes: 
- A incorporação de modelos de aprendizado profundo focados em sequências temporais não-lineares, como Redes Neurais Recorrentes (LSTMs) ou _Transformers_, 
que podem lidar de maneira mais nativa com espaços irregulares de negociação (_irregularly sampled time-series_); 
- A inclusão de dados não-estruturados, como Análise de Sentimento de notícias corporativas (_Natural Language Processing_) e dados macroeconômicos em tempo real, atuando como variáveis preditoras exógenas (covariáveis) 
diretamente nas matrizes de transição probabilísticas do HMM, na tentativa de reduzir a ocorrência de falsos alarmes causados por contágio de mercado secundário;
- A adoção de modelos integrados de volatilidade condicional e mudança de regime, como o _Markov-Switching GARCH_ (MS-GARCH) modelado via inferência Bayesiana (_Markov Chain Monte Carlo_ - MCMC), 
permitindo a calibração unificada do modelo e a inserção de conhecimento de especialistas como distribuições *a priori*;
- O mapeamento do contágio e do risco sistêmico entre emissores por meio da Teoria de Redes e de Cópulas Extremas (_Extreme Copulas_), 
para capturar a dependência não-linear de cauda e a topologia de propagação de choques de liquidez no mercado de crédito corporativo.
