= Descrição do Problema e da Solução Proposta <sec_problema_solucao>

== O Problema de Pesquisa <problemas_pesquisa>

A modelagem do risco de crédito corporativo evoluiu historicamente por meio de abordagens contábeis, estruturais e de forma reduzida. A literatura pioneira introduziu escores lineares baseados em 
indicadores contábeis, como o Z-Score de #cite(<altman1968>), utilizado para prever insolvência. Desde então, a literatura evoluiu para abordagens baseadas em modelos estruturais de crédito, 
como #cite(<merton1974>, form: "prose"). Contudo, estas abordagens tradicionais, baseadas em fundamentos, em geral obtidos em balanços e informações contábeis, usualmente divulgados
em frequência trimestral ou anual, são inadequados para sistemas de alerta em tempo real (ou com poucos dias de defasagem) devido à frequência de divulgação dessas informações.

Para superar a dependência de demonstrações financeiras, surgiram os modelos de forma reduzida, conforme consolidado por #cite(<duffie2003>, form: "prose"), que modelam o risco de 
crédito diretamente através de dados de mercado. Apesar de serem capazes de mitigar a defasagem da informação contábil, a modelagem contínua exige mercados líquidos, uma vez que é 
amplamente dependente dos dados observados. No mercado de debêntures brasileiro, onde se observa baixa liquidez e baixa atividade, essa abordagem se mostra frágil. 

Conforme aponta #cite(<correa2010aprecamento>), o prêmio de liquidez responde por parcela expressiva do spread das debêntures, sobrepondo-se com frequência ao risco de inadimplência. 
Mercados corporativos concentram fricções operacionais que dificultam o ajuste contínuo dos preços e fazem com que sejam observados saltos no preço dos ativos, por vezes
acompanhados de períodos de iliquidez, conforme demonstrado por #cite(<bao2011illiquidity>) e comprovado por eventos recentes no mercado brasileiro. O colapso das Lojas Americanas culminou 
em uma desvalorização de 50% no preço unitário de suas debêntures em um único pregão, acumulando perdas de 90% em uma semana. No caso do Grupo Pão de Açúcar, foram observados deságios de até 70% 
nas negociações secundárias. Emissões da Light sofreram reprecificações abruptas similares durante o processo de recuperação judicial.

Práticas tradicionais de tesouraria falham nesse ambiente. Bancos e gestoras de recursos frequentemente calculam o Valor em Risco (VaR) e modelos GARCH simétricos sob a hipótese de 
normalidade e liquidez plena de saída. Conforme aponta #cite(<jorion2006>), esses métodos assumem que o investidor consegue liquidar posições instantaneamente ao preço visualizado na tela. Em momentos 
de stress, muitas vezes a liquidez seca e o investidor é incapaz de liquidar suas posições, ou o faz com descontos massivos. 

Outra limitação teórica da família GARCH tradicional, como explica #cite(<tsay2005analysis>), reside no pressuposto de que os parâmetros da equação de variância 
e a volatilidade incondicional permanecem estáticos ao longo do tempo. Esses modelos operam ancorados em uma única média global da série histórica, porém, quando ocorrem quebras estruturais 
ou eventos de crédito severos, essas médias acabam sendo deslocadas. A literatura econométrica, fundamentada por #cite(<hamilton1994time>), demonstra que séries temporais financeiras 
longas sofrem quebras estruturais que exigem formulações baseadas em mudanças de regime (*Regime-Switching*). Sob essa teoria, os mercados transitam entre diferentes estados latentes, 
alterando a própria dinâmica estocástica dos preços, propostas como #cite(<haas2004new>) e #cite(<ardia2019markov>), buscam incorporar essas quebras na modelagem.

A natureza do problema investigado, portanto, compreende a modelagem estatística de séries temporais financeiras acoplada ao agrupamento não-supervisionado de regimes de risco latentes. 
O desafio central reside em disparar sinais de alerta preventivo (*Early Warning*) antes que perdas severas ocorram, preservando o capital do investidor.

== Objetivos

O objetivo geral deste trabalho consiste em desenvolver e avaliar uma metodologia quantitativa de alerta antecipado para o mercado secundário de debêntures brasileiro, identificando transições 
latentes de regime para antecipar choques de crédito e mitigar perdas patrimoniais.

Para atingir a proposta central, definem-se os seguintes objetivos específicos:

1. Normalizar o prêmio de risco dos ativos mitigando distorções de prazo por meio da taxa ajustada ao vencimento, contornando a exigência de curvas de juros soberanas completas;
2. Modelar a heterocedasticidade condicional e a assimetria das séries temporais de spread por meio de um motor econométrico AR(1)-EGARCH(1,1) com inovações t-Student;
3. Implementar e comparar dois métodos de agrupamento de regimes de risco: o algoritmo K-Means, adotado como linha de base geométrica e atemporal, e o Modelo Oculto de Markov (HMM Gaussiano), responsável por incorporar a dependência temporal nas transições;
4. Validar o motor econométrico de cauda por meio dos testes de hipótese de Kupiec POF e Christoffersen sobre o período fora da amostra;
5. Simular estratégias táticas de liquidação de portfólio em um ambiente de *backtest* financeiro realístico, submetido a custos de transação de 0,5% e validado estatisticamente pela técnica de *Block Bootstrap*.

== Solução Proposta

A solução desenvolvida apoia-se em uma arquitetura híbrida de duas camadas operacionais, na qual a primeira camada executa o saneamento econométrico dos dados de negociação da ANBIMA, 
eliminando ruídos causados por dias sem negócios e estimando a variância condicional e o risco de cauda com o motor EGARCH-t. A segunda, por sua vez, consome as métricas tratadas e alimenta 
algoritmos de agrupamento não-supervisionado.

Esses algoritmos particionam o espaço de estados latentes em três estados objetivos: Verde (baixo risco), Amarelo (alerta) e Vermelho (crise) de forma a enviar um sinal tático antecipado ao investidor, de forma que 
este possa optar pela venda das debêntures antes da materialização definitiva do evento.
