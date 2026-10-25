= Conclusão <sec_conclusao>

O presente trabalho avaliou a eficácia do sistema proposto para identificação precoce de eventos de estresse (_Early Warning System_) no mercado secundário de debêntures brasileiro, investigando o impacto da combinação
entre a modelagem econométrica e o aprendizado de máquina não supervisionado na proteção de capital.

== Síntese do Estudo e Principais Achados

O pipeline combinou um motor AR(1)-EGARCH(1,1)-t para modelagem da volatilidade condicional e estimação de perdas de cauda (VaR e Expected Shortfall) com dois classificadores de regimes: o particionamento geométrico 
(K-Means) e a inferência temporal estocástica (Gaussian HMM). Os modelos foram testados empiricamente sobre uma base contínua de 529 debêntures entre 2018 e 2026.

A análise dos resultados observados conduziu a três principais conclusões:

1. *Validação da Modelagem de Cauda:* O filtro EGARCH-t demonstrou capacidade estatística de absorver a dependência temporal da variância e evitar o agrupamento de violações (_volatility clustering_), mesmo frente aos choques atípicos do período _Out-of-Sample_ (2023 a 2026);
2. *O Paradoxo da Acurácia-Rentabilidade:* O HMM apresentou menor latência de detecção, antecipando eventos de crédito com semanas de antecedência nos estudos de caso corporativos. No entanto, sua alta sensibilidade gerou falsos positivos e giro excessivo de portfólio. Sob custos de transação realistas (0,5% por operação), a inércia do K-Means funcionou como um filtro contra ruídos transitórios de mercado. A estratégia K-Means Vende Amarelo entregou o maior retorno acumulado do período (36,18%), sendo a única a superar o _Buy-and-Hold_ (22,42%) com significância estatística comprovada por _Block Bootstrap_ ($p = 0,0416 < 0,05$);
3. *Ineficiência da Abordagem* _Ensemble_: A mescla linear entre HMM e K-Means induziu ao efeito chicote (_whipsaw_), acumulando custos operacionais em vendas precipitadas e recompras tardias, registrando o menor retorno líquido acumulado da simulação.

== Limitações da Pesquisa

A modelagem proposta opera sob restrições práticas inerentes ao mercado de capitais brasileiro:

- *Dependência de Negócios Realizados:* O sistema utiliza cotações de negócios efetivos para evitar distorções de marcações teóricas. Em episódios de estresse extremo em que o mercado interrompe ou reduz substancialmente o número de transações, o modelo perde a fonte contínua de dados de entrada;
- *Ativos com Negociação Esparsa:* Títulos com longos intervalos sem transações no histórico de calibração podem introduzir instabilidade na estimação por máxima verossimilhança, exigindo a aplicação de pisos de variância e salvaguardas numéricas preventivas.

== Perspectivas para Trabalhos Futuros

Como desdobramentos desta pesquisa, destaca-se a exploração de modelos neurais profundos adaptados a fluxos irregulares (como _Continuous-Time_ RNNs e _Transformers_ temporais), que possuam capacidade de lidar diretamente com a 
esparsidade de transações sem imputações sintéticas. Sugere-se também a incorporação de variáveis exógenas de sentimento de mercado como covariáveis dinâmicas nas matrizes de transição do HMM, além de estender a modelagem 
para arquiteturas integradas de MS-GARCH estimadas via métodos bayesianos (MCMC).