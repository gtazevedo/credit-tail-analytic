#set heading(numbering: none)

= Resumo

O mercado secundário de debêntures no Brasil impõe aos investidores desafios severos: assimetria de retornos, baixa liquidez e um histórico recente de eventos de crédito abruptos que os modelos tradicionais de risco 
costumam ter dificuldade para capturar. Diante desse cenário, esta dissertação propõe e valida um sistema de alerta precoce (_Early Warning System_) capaz de identificar e sinalizar este tipo de eventos, através da classificação
de regimes de risco. A metodologia utiliza um motor EGARCH-t para absorver a volatilidade condicional e padronizar os ruídos dos spreads de crédito e, em seguida, aplica algoritmos de aprendizado de máquina não supervisionado 
(K-Means e Modelos Ocultos de Markov) para classificar os ativos em regimes de baixo risco, alerta e crise. Ao longo do estudo empírico, baseado em dados de negociação públicos disponibilizados pela plataforma REUNE da ANBIMA, 
foi descoberta, no escopo das simulações realizadas, uma dicotomia entre a precisão teórica e o ganho prático, ilustrando o conhecido "Paradoxo da Acurácia-Rentabilidade" (_Accuracy-Profitability Paradox_). O HMM provou ser o modelo mais 
reativo, sendo capaz de antecipar diversos dos eventos de crédito observados. No entanto, sua alta sensibilidade temporal gerou falsos alarmes e custos excessivos no _trading_. Por outro lado, a inércia do K-Means funcionou como um filtro natural 
contra os ruídos do mercado, poupando a carteira dos custos de negociação de giro excessivo, sendo a única estratégia a superar financeiramente o carrego passivo (_Buy and Hold_) de forma estatisticamente comprovada. Os resultados finais atestam 
que aliar ferramentas preditivas quantitativas a regras operacionais robustas (como as travas de quarentena temporal) é necessário para mitigar impactos adversos decorrentes do "Paradoxo da Acurácia-Rentabilidade" e da instabilidade em manutenção de
 estados (como problemas de _flickering_). Nesse aspecto, a união entre modelagem e tática se mostra como a melhor alternativa para proteger o capital de forma eficaz em mercados de crédito ilíquidos.

*Palavras-chave:* Risco de Crédito. Early Warning. Debêntures. EGARCH. Cadeias de Markov. K-Means.

= Abstract

The Brazilian secondary debenture market imposes severe challenges on investors: return asymmetry, structural illiquidity, and a recent history of abrupt corporate defaults that traditional risk models often struggle to capture. In this context, 
this dissertation proposes and validates an Early Warning System capable of identifying and signaling such events through risk regime classification. The methodology employs an EGARCH-t engine to absorb conditional volatility and standardize credit 
spread noise, followed by the application of unsupervised machine learning algorithms (K-Means and Hidden Markov Models) to classify assets into low-risk, warning, and crisis regimes. Throughout the empirical study, based on public trading data provided 
by ANBIMA's REUNE platform, a dichotomy emerged within the scope of the performed simulations between theoretical accuracy and practical financial gain, illustrating the well-known "Accuracy-Profitability Paradox". The HMM proved to be the most 
reactive model, capable of anticipating several of the observed credit events. However, its high temporal sensitivity generated false alarms and excessive trading costs. Conversely, the inertia of the K-Means acted as a natural filter against market 
noise, sparing the portfolio from excessive turnover costs and becoming the only strategy to financially outperform the passive Buy-and-Hold approach with proven statistical significance. The final results demonstrate that combining predictive 
quantitative tools with robust operational rules (such as temporal quarantines) is necessary to mitigate adverse impacts arising from the "Accuracy-Profitability Paradox" and state maintenance instability (such as flickering issues). In this regard, 
the union between modeling and tactics proves to be the best alternative for effectively protecting capital in illiquid credit markets.

*Keywords:* Credit Risk. Early Warning. Debentures. EGARCH. Markov Chains. K-Means.

= Lista de Figuras
#outline(
  title: none,
  target: figure.where(kind: image)
)

= Lista de Tabelas
#outline(
  title: none,
  target: figure.where(kind: table)
)

#set heading(numbering: "1.1")
