= Conclusão <sec_conclusao>

O presente trabalho avaliou a eficácia do sistema proposto para identificação precoce de eventos de estresse (_Early Warning System_) no mercado secundário de debêntures brasileiro, investigando o impacto da combinação
entre a modelagem econométrica e o aprendizado de máquina não supervisionado na proteção de capital.

== Síntese do Estudo e Principais Achados

O pipeline combinou um motor AR(1)-EGARCH(1,1)-t para modelagem da volatilidade condicional e estimação de perdas de cauda (VaR e Expected Shortfall) com dois classificadores de regimes: o particionamento geométrico 
(K-Means) e a inferência temporal estocástica (Gaussian HMM). Os modelos foram testados empiricamente sobre uma base contínua de 529 debêntures entre 2018 e 2026.

A avaliação integrada das evidências empíricas conduz a três achados determinantes. Em primeiro lugar, comprova-se a robustez do filtro econométrico EGARCH-$t$, cuja parametrização capturou adequadamente a dependência temporal 
da variância e impediu o agrupamento sistemático de violações (_volatility clustering_), mesmo diante da sucessão de choques de crédito observados na janela fora da amostra (2023 a 2026). Em segundo lugar, identificou-se o 
paradoxo da acurácia-rentabilidade: conquanto o modelo markoviano (HMM) tenha exibido menor latência na identificação de eventos corporativos específicos — antecipando inflexões críticas de crédito com semanas de antecedência —, 
sua hipersensibilidade provocou falsos positivos e giro patrimonial excessivo. Sob atrito operacional realista (custos transacionais de 50 bps por movimento), a relativa inércia do particionamento por K-Means converteu-se em uma 
salvaguarda contra ruídos transitórios de negociação. Em termos empíricos, a estratégia "K-Means Vende Amarelo" entregou a maior rentabilidade líquida do estudo (36,18%), superando o referencial passivo _Buy and Hold_ (22,42%) com 
significância estatística respaldada pelo teste de _Block Bootstrap_ ($p = 0,0416 < 0,05$). Em terceiro lugar, constatou-se a ineficiência econômica da combinação linear em ensemble: a conciliação estocástica entre HMM e K-Means 
deflagrou o efeito chicote (_whipsaw_), incorrendo em liquidações precipitadas e custos recorrentes de recompra, desfecho que culminou no menor retorno acumulado de toda a bateria de testes.

== Limitações da Pesquisa

A metodologia proposta opera sob restrições estruturais associadas à microestrutura do mercado secundário de renda fixa no Brasil. Primeiramente, ao priorizar cotações de negócios efetivamente consumados para evitar as distorções 
inerentes às marcações teóricas a mercado, o sistema fica vulnerável a períodos de paralisia de liquidez em que a interrupção abrupta das negociações reduz o fluxo contínuo de dados de entrada. Adicionalmente, títulos caracterizados 
por negociação rarefeita durante a janela de calibração podem suscitar instabilidade numérica na estimação por máxima verossimilhança dos parâmetros do EGARCH, impondo a adoção preventiva de pisos de variância e restrições aos coeficientes de persistência.

== Perspectivas para Trabalhos Futuros

Como desdobramentos desta pesquisa, destaca-se a exploração de modelos neurais profundos adaptados a fluxos irregulares (como _Continuous-Time_ RNNs e _Transformers_ temporais), que possuam capacidade de lidar diretamente com a 
esparsidade de transações sem imputações sintéticas. Sugere-se também a incorporação de variáveis exógenas de sentimento de mercado como covariáveis dinâmicas nas matrizes de transição do HMM, além de estender a modelagem 
para arquiteturas integradas de MS-GARCH estimadas via métodos bayesianos (MCMC).