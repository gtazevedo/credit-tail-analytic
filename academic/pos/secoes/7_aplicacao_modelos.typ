= Aplicação de Modelos <sec_aplicacao_modelos>

A arquitetura analítica combina um modelo econométrico de volatilidade condicional a algoritmos de aprendizado de máquina para classificação de regimes, investigando o ganho marginal da dependência temporal em séries de crédito.

== Modelagem Econométrica de Volatilidade (EGARCH-t)

Avaliaram-se 32 especificações da família GARCH #cite(<engle1982autoregressive>)#cite(<bollerslev1986generalized>) combinando ordens AR(1), defasagens ($p, q in \{1, 2\}$), funções de variância (GARCH, EGARCH, GJR, TARCH) 
e inovações Normal e t-Student. A seleção elegeu o modelo com menor AIC em 529 debêntures no período _In-Sample_ ($W_j = (sum I_(i,j)/N) times 100$). A @fig_ranking_garch exibe o ranking médio das especificações 
avaliadas para o universo de debêntures ($N=500$).

#figure(
  image("../imagens/comparacao_modelos_ranking_n500_True.png", width: 65%),
  caption: [Ranking Comparativo de Modelos GARCH por Menor AIC ($N=500$).]
) <fig_ranking_garch>

O modelo AR(1)-EGARCH(1,1) com inovação t-Student #cite(<nelson1991conditional>) obteve a maior taxa de seleção nos grupos amplos, modelando a variância em escala logarítmica com sensibilidade assimétrica ($gamma < 0$):

$ ln(sigma_t^2) = omega + beta ln(sigma_(t-1)^2) + alpha ( abs(z_(t-1)) - E[abs(z_(t-1))] ) + gamma z_(t-1) $

Para assegurar estabilidade numérica em séries com baixa liquidez, adotaram-se duas restrições analíticas: fixou-se um piso para os graus de liberdade em $nu = max(2.05, nu_("est"))$, 
condição necessária para a existência do segundo momento estatístico, além de um teto de volatilidade que retém $sigma_("est")(t) = sigma_("est")(t-1)$ quando a estimativa supera $20 times P_(99)(sigma_("IS"))$. A @fig_diagnostico_residuos 
confirma aprovação de 86,4% no teste de Ljung-Box e 94,9% no ARCH-LM ($alpha = 5\%$).

#figure(
  image("../imagens/diagnostico_residuos_egarch.png", width: 45%),
  caption: [Taxa de aprovação dos testes de diagnóstico nos resíduos do EGARCH(1,1) t-Student.]
) <fig_diagnostico_residuos>

== Agrupamento Não Supervisionado: K-Means

O K-Means atua como linha de base estática #cite(<bishop2006pattern>), particionando observações em $k=3$ regimes via algoritmo de Lloyd. A fixação de $k=3$ 
reflete a classificação ordinal de três níveis de criticidade adotada na gestão de crédito, recebendo confirmação empírica pelo _Elbow Method_ e _Silhouette Score_ (@fig_cluster_validation). 
O _Label Switching_ foi mitigado pela ordenação dos centroides segundo um vetor determinístico de polaridade de risco (volatilidade condicional e Z-Score).

#figure(
  image("../imagens/cluster_val_elbow_silhouette.png", width: 65%),
  caption: [Elbow Method (Inércia Intra-Cluster) e Silhouette Score Médio por Número de Clusters ($k$).]
) <fig_cluster_validation>

== Modelos Ocultos de Markov (HMM)

O modelo Gaussian HMM #cite(<rabiner1989tutorial>) incorpora a dependência temporal por meio de uma cadeia de Markov oculta de três estados ($P(S_t = j | S_(t-1) = i) = A_(i j)$), com parâmetros estimados pelo algoritmo de Baum-Welch #cite(<baum1970maximization>). 
Para evitar estados absorventes, aplicou-se regularização de Laplace com piso de 1%:

$ P'_(i j) = (C_(i j) + 1) / ( sum_(k=1)^3 C_(i k) + 3 ), quad P_(i j) = max(P'_(i j), 0.01) / (sum_(k=1)^3 max(P'_(i k), 0.01)) $

A sequência mais provável de regimes foi obtida pelo algoritmo de Viterbi, enquanto as probabilidades filtradas de crise (`Prob_Crise_HMM`) foram calculadas pelo algoritmo Forward-Backward.

== Modelo Ensemble <subcap_modelo_ensemble>

O modelo combinado integra a classificação estática do K-Means com a probabilidade de transição temporal do HMM #cite(<kittler1998combining>)#cite(<ho1994decision>). A ponderação foi otimizada por _Grid Search_ 
visando maximizar o _Calmar Ratio_ (@fig_ensemble_sensitivity), métrica selecionada pela correlação de debêntures com o CDI e baixa dispersão diária de cotação.

#figure(
  image("../imagens/sensitivity_ensemble_amarelo.png", width: 65%),
  caption: [Análise de Sensibilidade dos pesos do Ensemble no período In-Sample.]
) <fig_ensemble_sensitivity>

A alocação ótima estabeleceu pesos de 70% para o HMM e 30% para o K-Means, com suavização por média móvel exponencial de 21 dias úteis, dada por: $"Score"_t = "EMA"_(21)(0.70 times "Prob_Crise_HMM"_t + 0.30 times "Prob_Crise_KMeans"_t)$.

== Protocolos de Validação Operacional <subcap_kupiec_backtest>

O protocolo no período _Out-of-Sample_ compreendeu duas fases. Inicialmente, realizou-se a validação estatística de cobertura incondicional de #cite(<kupiec1995techniques>, form: "prose") 
e condicional de #cite(<christoffersen1998>, form: "prose") para o VaR a 99%. Em seguida, executou-se a simulação financeira (_backtest_) frente ao _Buy and Hold_, considerando custo 
de transação de 50 bps, quarentena mínima de 180 dias e remuneração de caixa a 100% do CDI.

== Implementação em Código-Fonte

As rotinas de modelagem e restrições analíticas encontram-se em `volatility.py` e `regime.py`:

```python
# Trava de graus de liberdade, VaR/ES analíticos e teto prudencial (volatility.py)
nu_es = max(res_is.params.get('nu', 5.0), 2.05)
q_t = stats.t.ppf(1 - alpha, df=nu)
es_pad = (stats.t.pdf(q_t, df=nu) / alpha * (nu + q_t**2) / (nu - 1)) / np.sqrt(nu_es / (nu_es - 2))
var_99, es_99 = cond_mean + cond_vol * model.distribution.ppf(1 - alpha, nu), cond_mean + cond_vol * es_pad
cond_vol = cond_vol.mask(cond_vol > max(np.nanpercentile(cond_vol.iloc[:split_idx], 99) * 20.0, 0.05)).ffill().bfill()

# Gaussian HMM com suavização de Laplace e piso estocástico (regime.py)
A = (trans_counts + 1.0) / (trans_counts + 1.0).sum(axis=1, keepdims=True)
hmm.transmat_ = np.maximum(A, 0.01) / np.maximum(A, 0.01).sum(axis=1, keepdims=True)
```
