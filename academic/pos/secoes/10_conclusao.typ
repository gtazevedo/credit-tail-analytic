= Conclusão <sec_conclusao>

Esta pesquisa desenvolveu e validou uma metodologia quantitativa para identificação precoce de eventos de estresse (_Early Warning System_) no mercado secundário de debêntures brasileiro. Motivada pela 
assimetria de retornos, pela liquidez estrutural reduzida e por quebras severas de crédito corporativo recentes, a investigação avaliou como a integração entre econometria e aprendizado de máquina não-supervisionado 
viabiliza a proteção de capital em carteiras institucionais.

== Síntese do Estudo e Principais Achados

O pipeline combinou um motor AR(1)-EGARCH(1,1)-t para modelagem da volatilidade condicional e estimação de perdas de cauda (VaR e Expected Shortfall) com dois classificadores de regimes: o particionamento geométrico 
(K-Means) e a inferência temporal estocástica (Gaussian HMM). Os modelos foram testados empiricamente sobre uma base contínua de 529 debêntures entre 2018 e 2026.

Os resultados consolidaram três descobertas empíricas centrais:

1. *Validação da Modelagem de Cauda:* O filtro EGARCH-t demonstrou capacidade estatística de absorver a dependência temporal da variância e evitar o agrupamento de violações (_volatility clustering_), mesmo frente aos choques severos do período _Out-of-Sample_ (2023 a 2026);
2. *O Paradoxo da Acurácia-Rentabilidade:* O HMM comprovou maior agilidade analítica, antecipando eventos de crédito com semanas de antecedência nos estudos de caso corporativos. No entanto, sua alta sensibilidade gerou falsos alarmes e giro excessivo de portfólio. Sob custos de transação realistas (0,5% por operação), a inércia do K-Means funcionou como um filtro contra ruídos passageiros de mercado. A estratégia K-Means Vende Amarelo entregou o maior retorno acumulado do período (36,18%), sendo a única a superar o _Buy-and-Hold_ (22,42%) com significância estatística comprovada por _Block Bootstrap_ ($p = 0,0416 < 0,05$);
3. *Ineficiência da Abordagem* _Ensemble_: A mescla linear entre HMM e K-Means induziu ao efeito chicote (_whipsaw_), acumulando custos operacionais em vendas precipitadas e recompras tardias, registrando o pior retorno líquido da simulação.

== Limitações da Pesquisa

A modelagem proposta opera sob restrições práticas inerentes ao mercado de capitais brasileiro:

- *Dependência de Negócios Realizados:* O sistema utiliza cotações de negócios efetivos para evitar distorções de marcações teóricas. Em episódios de estresse extremo em que o mercado cessa completamente as transações (secamento total do _bid-ask spread_), o modelo perde a fonte contínua de dados de entrada;
- *Convergência Numérica em Ativos Extremos:* Títulos com longos intervalos sem transações no histórico de calibração podem introduzir instabilidade na estimação por máxima verossimilhança, exigindo a aplicação de pisos de variância e exclusões manuais preventivas.

== Perspectivas para Trabalhos Futuros

Para expandir os achados deste trabalho, recomendam-se as seguintes frentes de pesquisa:

1. Adoção de modelos de Aprendizado Profundo voltados a séries temporais irregulares (_Transformers_ e LSTMs com codificação temporal contínua), lidando nativamente com espaços esparsos de negociação;
2. Inclusão de variáveis exógenas macroeconômicas e análise de sentimento de notícias corporativas (_Natural Language Processing_) atuando diretamente como covariáveis nas probabilidades de transição do HMM;
3. Estimação integrada de regimes de volatilidade por meio de modelos _Markov-Switching GARCH_ (MS-GARCH) calibrados via inferência Bayesiana (MCMC);
4. Mapeamento de risco sistêmico e contágio financeiro entre emissores por meio de Teoria de Redes Complexas acoplada a Cópulas Extremas.
