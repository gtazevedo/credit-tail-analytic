= Conclusão <sec_conclusao>

Este trabalho desenvolveu e avaliou um pipeline de monitoramento de risco de crédito para o mercado secundário de debêntures no Brasil, que integra a estimação econométrica 
de volatilidade condicional à classificação não supervisionada de regimes latentes. O modelo AR(1)-EGARCH(1,1) com distribuição $t$-Student foi calibrado sobre 529 debêntures 
no período _In-Sample_ (2018 a 2022) e avaliado no período _Out-of-Sample_ (2023 a 2026) sobre 663 séries, amostra que reúne os títulos ativos do treino e novas emissões negociadas 
na janela de teste.

Na etapa econométrica, a transformação dos prêmios de risco em primeira diferença (`Delta Spread`) assegurou estacionariedade em 95,7% das séries pelo teste ADF, ao passo que o 
subconjunto formado por `Taxa_ZScore`, `Volatilidade_EGARCH` e `Expected_Shortfall_99` obteve a melhor separação de grupos pela Contagem de Borda. Na validação do VaR a 99% 
fora da amostra, embora as variações discretas de cotações tenham reduzido a aprovação no teste incondicional de Kupiec (32,7%), o teste de independência de Christoffersen 
registrou não-rejeição em 88,1% dos títulos (97,5% em CDI Percentual e 90,4% em IPCA), resultado compatível com a ausência de agrupamento temporal de violações.

A comparação entre os classificadores mostrou diferenças entre a velocidade de emissão do alerta e o retorno líquido após custos. Nos episódios de deterioração gradual de 
crédito, como na Unigel (357 dias úteis) e na CVC Corp (78 dias), o Gaussian HMM antecipou os eventos antes do K-Means no regime de alerta contínuo. Todavia, na simulação 
de carteira com custo de transação de 50 bps e quarentena de 180 dias, a maior frequência de mudança de estado do HMM elevou o giro e provocou _drawdown_ de -9,74%. O 
agrupamento estático por K-Means apresentou menor número de operações em oscilações temporárias de spread, o que permitiu à estratégia K-Means Vende Amarelo atingir 
retorno acumulado de 36,18% (_Calmar Ratio_ de 1,603), acima do _Buy-and-Hold_ (22,42%) e com p-valor de 0,0416 no _Block Bootstrap_. O modelo Ensemble obteve retorno 
de 16,37%, reduzido pelas vendas e recompras decorrentes da divergência de sinais entre seus componentes.

Como limitação operacional, o uso exclusivo de preços de negócios registrados no sistema REUNE evita distorções de marcação na curva, mas restringe a atualização diária 
do modelo em emissões que permanecem longos períodos sem transação, como observado no caso do Grupo Casas Bahia, além de exigir limites numéricos para os graus de 
liberdade ($nu >= 2,05$) e para a variância condicional na estimação por máxima verossimilhança. Em estudos posteriores, a irregularidade no espaçamento entre negócios 
pode ser tratada por arquiteturas recorrentes de tempo contínuo (_Continuous-Time_ RNNs), que operam sobre intervalos desiguais sem repetição da última cotação entre 
pregões. Outra extensão consiste na inclusão de variáveis macroeconômicas e de fluxo de captação da indústria de fundos na matriz de transição do HMM, bem como na 
estimação conjunta de volatilidade e regimes via modelos _Markov-Switching_ GARCH (MS-GARCH) por métodos de Monte Carlo via Cadeias de Markov (MCMC).
