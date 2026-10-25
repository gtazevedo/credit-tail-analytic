= Descrição do Problema e da Solução Proposta <sec_problema_solucao>

== O Problema de Pesquisa <problemas_pesquisa>

A modelagem do risco de crédito corporativo desenvolveu-se historicamente por meio de abordagens contábeis, estruturais e de forma reduzida. A literatura pioneira introduziu escores lineares baseados em 
indicadores contábeis, como o Z-Score de #cite(<altman1968>, form: "prose"), utilizado para prever insolvência. Subsequentemente, avançou-se para abordagens fundamentadas em modelos estruturais de crédito, 
como #cite(<merton1974>, form: "prose"). Contudo, essas abordagens tradicionais, assentadas em balanços divulgados em periodicidade trimestral ou anual, mostram-se inadequadas para sistemas de alerta em tempo real em razão da defasagem temporal inerente à publicação dos demonstrativos contábeis.

Para superar a dependência de demonstrações financeiras, surgiram os modelos de forma reduzida, conforme consolidado por #cite(<duffie2003>, form: "prose"), que modelam o risco de 
crédito diretamente por meio de dados de mercado. Apesar de mitigarem a defasagem da informação contábil, tais formulações pressupõem mercados líquidos, dependendo da regularidade das negociações observadas. No mercado de debêntures brasileiro, no qual se observa liquidez reduzida e baixa frequência de negociações, essa abordagem se mostra frágil. 

Conforme aponta #cite(<correa2010aprecamento>, form: "prose"), o prêmio de liquidez responde por parcela expressiva do spread das debêntures, sobrepondo-se com frequência ao risco de inadimplência. 
Mercados corporativos concentram fricções operacionais que dificultam o ajuste contínuo dos preços e induzem descontinuidades e saltos nas cotações, frequentemente
acompanhados de períodos de iliquidez, conforme demonstrado por #cite(<bao2011illiquidity>, form: "prose") e evidenciado por episódios recentes no mercado brasileiro. O pedido de recuperação judicial das Lojas Americanas culminou 
em uma desvalorização de 50% no preço unitário de suas debêntures em um único pregão, acumulando perdas de 90% em uma semana. No caso do Grupo Pão de Açúcar, foram observados deságios de até 70% 
nas negociações secundárias. Emissões da Light sofreram reprecificações abruptas similares durante o processo de recuperação judicial.

Práticas tradicionais de tesouraria apresentam limitações operacionais nessas condições, porque bancos e gestoras de recursos frequentemente calculam o Valor em Risco (VaR) e modelos GARCH simétricos sob a hipótese de 
normalidade e liquidez plena de saída. Conforme aponta #cite(<jorion2006>, form: "prose"), esses métodos assumem que o investidor consegue liquidar posições instantaneamente ao preço cotado em tela. Em momentos de _stress_,
é comum observar expressiva contração da liquidez dos ativos, dificultando a liquidação tempestiva de posições ou demandando elevados deságios para sua execução.

Outra limitação teórica da família GARCH tradicional, como explica #cite(<tsay2005analysis>, form: "prose"), reside no pressuposto de que os parâmetros da equação de variância 
e a volatilidade incondicional permanecem estáticos ao longo do tempo. Esses modelos operam ancorados em uma única média global da série histórica, porém, quando ocorrem quebras estruturais 
ou eventos de crédito atípicos, essas médias sofrem deslocamento. A literatura econométrica, fundamentada por #cite(<hamilton1994time>, form: "prose"), demonstra que séries temporais financeiras 
longas sofrem quebras estruturais que exigem formulações baseadas em mudanças de regime (_Regime-Switching_). Sob essa teoria, os mercados transitam entre diferentes estados latentes, 
alterando a própria dinâmica estocástica dos preços; propostas como as de #cite(<haas2004new>, form: "prose") e #cite(<ardia2019markov>, form: "prose") buscam incorporar essas quebras na modelagem.

O problema investigado compreende a modelagem estatística de séries temporais financeiras acoplada ao agrupamento não supervisionado de regimes de risco latentes, com a finalidade de emitir sinais de 
alerta antecipado (_Early Warning_) sobre a possibilidade de perdas acentuadas antes de sua materialização, visando à preservação patrimonial do investidor.

== Objetivos

O objetivo geral deste trabalho consiste em desenvolver e avaliar uma metodologia quantitativa de alerta antecipado para o mercado secundário de debêntures brasileiro, identificando transições 
latentes de regime para antecipar choques de crédito e mitigar perdas patrimoniais.

Para atingir a proposta central, definem-se os seguintes objetivos específicos:

1. Normalizar o prêmio de risco dos ativos mitigando distorções de prazo por meio da taxa ajustada ao vencimento, contornando a exigência de curvas de juros soberanas completas;
2. Modelar a heterocedasticidade condicional e a assimetria das séries temporais de spread por meio de um motor econométrico AR(1)-EGARCH(1,1) com inovações t-Student;
3. Implementar e comparar dois métodos de agrupamento de regimes de risco: o algoritmo K-Means, adotado como linha de base geométrica e atemporal, e o Modelo Oculto de Markov (HMM Gaussiano), responsável por incorporar a dependência temporal nas transições;
4. Validar o motor econométrico de cauda por meio dos testes de hipótese de Kupiec POF e Christoffersen sobre o período fora da amostra;
5. Simular estratégias táticas de liquidação de portfólio em um ambiente de _backtest_ financeiro realista, submetido a custos de transação de 0,5% e validado estatisticamente pela técnica de _Block Bootstrap_.

== Solução Proposta

A solução desenvolvida apoia-se em uma arquitetura híbrida de duas camadas operacionais, na qual a primeira camada executa o saneamento econométrico dos dados de negociação da ANBIMA, 
eliminando ruídos causados por dias sem negócios e estimando a variância condicional e o risco de cauda com o motor EGARCH-t. A segunda camada consome as métricas tratadas e alimenta 
algoritmos de agrupamento não supervisionado.

Esses algoritmos particionam o espaço de estados latentes em três estados objetivos: Verde (baixo risco), Amarelo (alerta) e Vermelho (crise), o que viabiliza a emissão de alertas antecipados para a liquidação defensiva
das posições antes da consolidação do choque financeiro.