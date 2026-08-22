#set heading(numbering: none)

= Resumo

O mercado secundário de crédito privado brasileiro, com foco em debêntures, apresenta o desafio da escassez de liquidez estrutural e da assimetria de retornos. Recentes eventos de estresse em grandes empresas corporativas brasileiras expuseram a incapacidade de métricas tradicionais de risco (como o VaR) em precificar corretamente o risco de cauda e alertar investidores de forma tempestiva. Neste contexto, este trabalho propõe a construção e a validação de um _Early Warning System_ tático, arquitetado como um modelo de múltiplos estágios que combina aprendizado de máquina não supervisionado e volatilidade condicional. Inicialmente, o motor EGARCH-t é empregado para filtrar a variância condicional e amortecer o risco isolado, mitigando os retornos não-normais e padronizando as características latentes dos ativos. Posteriormente, o algoritmo K-Means e os Modelos Ocultos de Markov (HMM) particionam os ativos em três regimes de risco distintos: baixo risco, alerta e crise. O estudo demonstra a dicotomia inerente entre as abordagens topológicas e probabilísticas: enquanto o HMM evidencia maior acurácia de decodificação a mercado e reatividade temporal aos choques, o K-Means atinge os melhores retornos ajustados ao risco em simulações financeiras (_Backtest_), atuando como um filtro de inércia que poupa o portfólio de alarmes falsos e custos transacionais. Por fim, a pesquisa valida a ineficácia do modelo _Ensemble_ misto. Os resultados comprovam a viabilidade e a superioridade de sistemas autônomos e táticos de crédito na proteção do capital frente a estratégias passivas (_Buy and Hold_) durante choques extremos.

*Palavras-chave:* Risco de Crédito. Early Warning. Debêntures. EGARCH. Cadeias de Markov. K-Means.

= Abstract

The secondary market for Brazilian private credit, particularly debentures, faces structural challenges regarding liquidity and asymmetric returns. Recent credit events in large corporations have exposed the inability of traditional risk metrics (such as VaR) to properly price tail risk and warn investors in a timely manner. In this context, this study proposes the construction and validation of a tactical Early Warning System, architected as a multi-stage model combining unsupervised machine learning and conditional volatility. Initially, the EGARCH-t engine is employed to filter conditional variance and dampen isolated risk, standardizing non-normal returns. Subsequently, the K-Means algorithm and Gaussian Hidden Markov Models (HMM) partition the assets into three distinct risk regimes: low risk, warning, and crisis. The study demonstrates an inherent dichotomy between the topological and probabilistic approaches: while the HMM shows higher mark-to-market decoding accuracy and temporal reactivity to shocks, the K-Means achieves the best risk-adjusted returns in financial simulations (Backtest) by acting as an inertia filter that saves the portfolio from false alarms and transaction costs. Finally, the research validates the ineffectiveness of the mixed Ensemble model. The results confirm the viability and superiority of autonomous tactical credit systems in preserving capital against passive (Buy and Hold) strategies during extreme market shocks.

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
