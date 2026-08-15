= Conclusão

Esta dissertação teve como objetivo desenvolver e avaliar uma metodologia quantitativa baseada em Aprendizado de Máquina Não Supervisionado para a identificação precoce 
de eventos de estresse (*Early Warning*), por meio da criação e monitoramento de regimes de risco no mercado secundário de 
debêntures brasileiro. Motivada pela assimetria de retornos inerente aos ativos de crédito privado, pela baixa liquidez estrutural e pelos recentes e severos eventos de crédito 
(como os casos Lojas Americanas, Light e Grupo Pão de Açúcar), a pesquisa buscou responder se algoritmos de clusterização poderiam atuar como ferramentas táticas 
viáveis para a mitigação de perdas severas, superando o carrego passivo de portfólios.

== Principais Descobertas

O estudo revelou achados importantes que conectam a modelagem teórica à aplicabilidade financeira prática:

1. *Adequação da Modelagem de Cauda (EGARCH-t):* A adoção do modelo EGARCH-t acoplado ao *Expected Shortfall* provou-se eficaz na precificação do risco isolado dos ativos. A validação por meio dos 
testes conjuntos de Christoffersen, conforme apresentado na @subcap_valest, confirmou que o modelo é capaz de absorver a heterocedasticidade condicional e evitar o agrupamento de violações (*volatility clustering*), 
mesmo frente aos massivos choques de iliquidez do período *Out-of-Sample*, respondendo, assim, as falha dos modelos de VaR tradicionais citados na @subcap_vargarch.

2. *O Paradoxo entre Acurácia Preditiva e Desempenho Financeiro:* Observou-se uma dicotomia entre o Modelo Oculto de Markov (HMM) e o particionamento geométrico (K-Means). O HMM demonstrou superioridade 
analítica ao integrar a dependência temporal (matrizes de transição), conseguindo antecipar de forma ágil a deterioração de crédito em eventos como o do Grupo Pão de Açúcar, conforme 
apresentado na @subcap_rkmeans e @subcap_rhmm. Contudo, 
no *backtest* financeiro, a estratégia baseada no K-Means (*Vende Amarelo*) entregou a melhor relação risco-retorno (*Calmar Ratio* de 1,603 contra 0,866 do HMM). 
Conforme apresentado na @subcap_resultadosbacktest, a "lentidão" apresentada pelo K-Means para mudança de regimes funcionou como um filtro de ruído contra o efeito 
contágio do mercado, poupando a carteira do excesso de giro e dos custos de transação (que conforme @subcap_kupiec_backtest, foi definido como 0,5% por operação) 
que penalizaram o HMM com *drawdowns* profundos gerados por alarmes falsos.

3. *A Armadilha da Combinação de Modelos:* O estudo documentou a falha do modelo *Ensemble*. Ao tentar fundir a reatividade do HMM com a estabilidade do K-Means, 
a modelagem mista deixou a carteira vulnerável ao efeito chicote (*whipsaw*). O modelo realizava vendas impulsionadas pelo HMM e recompras tardias pelo K-Means, 
corroendo o capital com excesso de custos transacionais, entregando o pior retorno do período. A combinação acabou exacerbando os defeitos de cada modelo, e reforçando 
a necessidade da importância da avaliação do momento de compra e venda dos papéis para evitar que o carrego obtido seja consumido por custos transacionais e perdas decorrentes
de operações em momentos inoportunos.

== Implicações Práticas

Para a indústria de gestão de recursos, a metodologia desenvolvida oferece um arcabouço robusto e sistemático para a gestão tática em carteiras de crédito privado. Em um mercado caracterizado por baixa liquidez estrutural 
e precificação ocasionalmente defasada, a adoção de gatilhos quantitativos pode substituir ou auxiliar o viés comportamental humano, que frequentemente leva gestores a reter posições perdedoras na esperança de uma reversão que muitas vezes não ocorre.

A operacionalização desta pesquisa demonstra que o melhor modelo preditivo não é, necessariamente, a melhor estratégia de *trading*. A escolha do motor de decisão deve estar alinhada aos atritos do mercado e aos objetivos do portfólio. Os resultados observados
foram frutos de simulações históricas baseado em regras fixadas e comparados contra uma estratégia buy-and-hold, durante uma atuação no mercado secundário para fechamento de posições devido a early warnings, outros fatores podem influenciar no preço e capacidade
de liquidação das posições

== Limitações e Recomendações para Trabalhos Futuros

Apesar dos resultados promissores, o presente estudo possui limitações inerentes à estrutura e à qualidade dos dados financeiros brasileiros. A principal limitação concentrou-se na convergência da volatilidade condicional (EGARCH) para ativos extremos, 
onde longos históricos de ausência de negociação distorceram a estimação dos parâmetros de risco no período *In-Sample*. Além disso, a dependência exclusiva da curva de apreçamento divulgada pela Anbima impõe que o modelo herde a possível ineficiência 
temporal ou "suavização" de preços inerente ao fechamento indicativo da associação.

Para trabalhos futuros, recomenda-se a exploração das seguintes frentes: 
- A incorporação de modelos de aprendizado profundo focados em sequências temporais não-lineares, como Redes Neurais Recorrentes (LSTMs) ou *Transformers*, 
que podem lidar de maneira mais nativa com espaços irregulares de negociação (*irregularly sampled time-series*); 
- A inclusão de dados não-estruturados, como Análise de Sentimento de notícias corporativas (*Natural Language Processing*) e dados macroeconômicos em tempo real, atuando como variáveis preditoras exógenas (covariáveis) 
diretamente nas matrizes de transição probabilísticas do HMM, na tentativa de reduzir a ocorrência de falsos alarmes causados por contágio de mercado secundário;
- A adoção de modelos integrados de volatilidade condicional e mudança de regime, como o *Markov-Switching GARCH* (MS-GARCH) modelado via inferência Bayesiana (*Markov Chain Monte Carlo* - MCMC), 
permitindo a calibração unificada do modelo e a inserção de conhecimento de especialistas como distribuições *a priori*;
- O mapeamento do contágio e do risco sistêmico entre emissores por meio da Teoria de Redes e de Cópulas Extremas (*Extreme Copulas*), 
para capturar a dependência não-linear de cauda e a topologia de propagação de choques de liquidez no mercado de crédito corporativo.
