= Descrição do Problema e da Solução Proposta <sec_problema_solucao>

== O Problema de Pesquisa <problemas_pesquisa>

A modelagem de crédito evoluiu de escores contábeis #cite(<altman1968>) e modelos estruturais #cite(<merton1974>) para modelos de forma reduzida #cite(<duffie2003>). Contudo, 
dados contábeis possuem defasagem temporal de divulgação, enquanto modelos de intensidade assumem negociação contínua. No mercado de debêntures brasileiro, o prêmio de iliquidez sobrepõe-se frequentemente 
ao risco de inadimplência #cite(<correa2010aprecamento>), o que gera descontinuidades de preços #cite(<bao2011illiquidity>). Casos recentes no mercado brasileiro ilustram esse comportamento, como as perdas de 50% 
em um pregão nas Lojas Americanas (90% na semana da recuperação judicial), deságios de até 70% no Grupo Pão de Açúcar e reprecificações abruptas na Light S.A.

Modelos tradicionais de risco apresentam limitações sob tais condições. Conforme aponta #cite(<jorion2006>, form: "prose"), o VaR sob normalidade assume liquidez contínua e execução imediata ao preço em tela. Em momentos de estresse, a redução de liquidez dificulta a venda de posições sem descontos relevantes no preço. Além disso, o GARCH tradicional assume parâmetros estáticos #cite(<tsay2005analysis>) e não captura quebras estruturais que demandam mudanças de regime (_Regime-Switching_) #cite(<hamilton1994time>)#cite(<haas2004new>). O problema compreende a modelagem estatística de crédito associada ao agrupamento não supervisionado de regimes para emissão de alertas antecipados (_Early Warning_).

== Objetivos

O objetivo geral deste trabalho consiste em desenvolver e avaliar uma metodologia quantitativa de alerta antecipado para o mercado de debêntures brasileiro, voltada à detecção de transições latentes de regime para antecipar eventos de crédito e mitigar perdas patrimoniais. Os objetivos específicos compreendem: (i) padronizar o prêmio de risco reduzindo distorções de prazo via taxa ajustada ao vencimento; (ii) modelar a heterocedasticidade condicional e a assimetria dos retornos via AR(1)-EGARCH(1,1)-t; (iii) comparar o agrupamento estático (K-Means) à modelagem com dependência temporal (Gaussian HMM); (iv) verificar a calibração de cauda por testes de Kupiec e Christoffersen fora da amostra; e (v) avaliar as estratégias em _backtest_ com custos de 50 bps, sob verificação de significância do retorno excedente por _Block Bootstrap_.

== Solução Proposta

A solução proposta divide-se em duas etapas. Na primeira, realiza-se o tratamento dos dados da ANBIMA e estimam-se a volatilidade e as métricas de cauda (VaR e ES 99%) via EGARCH-t. Na segunda, essas variáveis alimentam classificadores não supervisionados que estratificam o risco em três regimes ordinais (Verde para baixo risco, Amarelo para alerta e Vermelho para crise), orientando a redução preventiva de exposição antes de reprecificações desfavoráveis.