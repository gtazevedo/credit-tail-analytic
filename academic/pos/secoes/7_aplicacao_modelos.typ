= Aplicação de Modelos <sec_aplicacao_modelos>

A arquitetura analítica combina um motor estatístico de volatilidade condicional a algoritmos de aprendizado de máquina para classificação de regimes. A abordagem compara diretamente métodos com e sem dependência temporal, 
investigando o ganho marginal da modelagem markoviana em séries de crédito privado.

== Motor Econométrico de Volatilidade (EGARCH-t)

Para modelar a variância dos retornos de spread, realizou-se um torneio combinatório de 32 especificações da família GARCH utilizando a biblioteca `arch`. A linhagem teórica desses modelos remonta à introdução 
dos processos heterocedásticos autorregressivos (ARCH) por #cite(<engle1982autoregressive>, form: "prose"), generalizados posteriormente por #cite(<bollerslev1986generalized>, form: "prose") na classe GARCH. As iterações avaliaram ordens autorregressivas 
AR(1) para a média condicional, variações de defasagens ($p, q in \{1, 2\}$), diferentes funções de variância (GARCH tradicional, EGARCH, GJR-GARCH e TARCH) e distribuições de resíduos Normal e t-Student.

A eleição do modelo campeão baseou-se na taxa de vitórias (_Win Rate_) pelo Critério de Informação de Akaike (AIC) em 529 debêntures no período _In-Sample_. A taxa de vitória $W_j$ expressa a proporção da 
amostra em que o modelo $j$ alcançou o menor AIC:

$ W_j = (sum_{i=1}^N I_(i, j)) / N times 100 $

sendo $I_(i, j) = 1$ quando o modelo $j$ obtém o menor AIC no ativo $i$, e $0$ caso contrário. As figuras @fig_ranking_30, @fig_ranking_100 e @fig_ranking_500 apresentam os rankings médios obtidos 
para amostras de 30, 100 e 500 debêntures.

#figure(
  image("../imagens/comparacao_modelos_ranking_n30_True.png", width: 85%),
  caption: [Torneio GARCH: Ranking Médio para a amostra dos 30 ativos mais líquidos.]
) <fig_ranking_30>

#figure(
  image("../imagens/comparacao_modelos_ranking_n100_True.png", width: 85%),
  caption: [Torneio GARCH: Ranking Médio para a amostra dos 100 ativos mais líquidos.]
) <fig_ranking_100>

#figure(
  image("../imagens/comparacao_modelos_ranking_n500_True.png", width: 85%),
  caption: [Torneio GARCH: Ranking Médio para a amostra ampla de 500 ativos.]
) <fig_ranking_500>

O modelo AR(1)-EGARCH(1,1) com inovação t-Student alcançou a maior taxa de vitórias nos grupos amplos. Formulado originalmente por #cite(<nelson1991conditional>, form: "prose"), o EGARCH modela a variância condicional 
em escala logarítmica, dispensando restrições de não-negatividade sobre os parâmetros e capturando a assimetria característica de ativos corporativos:

$ ln(sigma_t^2) = omega + beta ln(sigma_(t-1)^2) + alpha ( |z_(t-1)| - E[|z_(t-1)|] ) + gamma z_(t-1) $

sendo $z_t = epsilon_t / sigma_t$ os resíduos padronizados. Quando $gamma < 0$, choques negativos elevam a volatilidade com maior intensidade que choques positivos de igual magnitude.

Para assegurar estabilidade numérica em ativos ilíquidos com quebras temporárias de cotação, implementaram-se duas travas matemáticas:

1. Piso para graus de liberdade: $nu = max(2.05, nu_("est"))$, impedindo variância infinita na distribuição t-Student;
2. Teto de variância: $sigma_("est")(t) = sigma_("est")(t-1)$ quando $sigma_("est")(t) > 20 times P_(99)(sigma_("IS"))$, contendo explosões pontuais causadas por dias isolados de iliquidez severa.

O diagnóstico dos resíduos padronizados do modelo EGARCH(1,1)-t para os 529 papéis confirmou a adequação estatística da especificação. A @fig_diagnostico_residuos exibe as taxas de aprovação nos testes de 
Ljung-Box (86,4%) e ARCH-LM (94,9%) ao nível de 5%, atestando a remoção de autocorrelação serial e a eliminação de heterocedasticidade remanescente.

#figure(
  image("../imagens/diagnostico_residuos_egarch.png", width: 80%),
  caption: [Taxa de aprovação dos testes de diagnóstico nos resíduos do EGARCH(1,1) t-Student.]
) <fig_diagnostico_residuos>

Após a calibração da volatilidade condicional, computaram-se o Valor em Risco (VaR 99%) e o Expected Shortfall (ES 99%) para cada papel e pregão.

== Agrupamento Não-Supervisionado: K-Means

O algoritmo K-Means atua como linha de base estática. Conforme formulado por #cite(<bishop2006pattern>, form: "prose"), o K-Means particiona $N$ observações em $K$ grupos minimizando a soma das distâncias quadráticas aos 
centróides mais próximos por meio do algoritmo iterativo de Lloyd (Maximização de Expectativa). O modelo assume propositalmente independência temporal entre as observações para isolar o efeito da geometria dos dados.

A quantidade de agrupamentos foi fixada em $k=3$ regimes: Verde (baixo risco), Amarelo (alerta) e Vermelho (crise). A escolha recebeu validação formal pelo Método do Cotovelo (_Elbow Method_) e pelo _Silhouette Score_ 
para $k in \{2, 3, 4, 5, 6, 7\}$ sobre os dados de treinamento, conforme exibe a @fig_cluster_validation.

#figure(
  grid(
    columns: 1,
    gutter: 12pt,
    image("../imagens/val_IPCA_elbow_silhouette.png", width: 85%),
    image("../imagens/val_CDI_Spread_elbow_silhouette.png", width: 85%)
  ),
  caption: [Elbow Method e Silhouette Score por número de clusters (Superior: IPCA, Inferior: CDI Spread).]
) <fig_cluster_validation>

A curva de inércia apresenta flexão em $k=3$, patamar que maximiza a interpretação financeira dos regimes. Devido à natureza não-supervisionada do K-Means, 
os centróides gerados recebem rótulos arbitrários (este é um problema conhecido como _Label Switching_), o modelo resolve este problema através de um vetor 
de polaridade de risco (onde valores maiores de volatilidade e _Z-Score_ implicam maior risco), ordenando as médias dos agrupamentos para classificar 
deterministicamente os regimes em Verde (baixo risco), Amarelo (alerta) e Vermelho (crise). Na etapa preditiva, para a construção de um modelo misto ponderado 
(conforme será abordado em @subcap_modelo_ensemble), a probabilidade de crise (`Prob_Crise_KMeans`) é definida 
com base na distância euclidiana inversa de cada observação _Out-of-Sample_ até o centróide Vermelho.

== Modelos Ocultos de Markov (HMM)

O Modelo Oculto de Markov (Gaussian HMM), estruturado classicamente por #cite(<rabiner1989tutorial>, form: "prose"), introduz dependência temporal estocástica na classificação dos regimes. A dinâmica pressupõe uma cadeia de Markov 
latente de primeira ordem com três estados não observáveis, em que a probabilidade de transição depende exclusivamente do estado imediatamente anterior:

$ P(S_t = j mid S_(t-1) = i) = A_(i j) $

O treinamento estimou as médias, as covariâncias diagonais e as probabilidades de transição por meio do algoritmo de Baum-Welch sobre os dados sequenciais _In-Sample_, fundamentado na teoria de máxima verossimilhança de #cite(<baum1970maximization>, form: "prose").

Para impedir que estados extremos se transformassem em regimes absorventes por ausência de transições históricas na base de treino, aplicou-se a Suavização Aditiva de Laplace combinada a um piso de 1% nas probabilidades de transição:

$ P'_{i j} = (C_{i j} + alpha) / ( sum_{k=1}^K C_{i k} + K alpha ) $

$ P''_{i j} = max(P'_{i j}, 0.01) quad ==> quad P_(i j) = P''_{i j} / (sum_{k=1}^K P''_{i k}) $

adotando-se $alpha = 1$ e $K=3$. A inferência fora da amostra utilizou o algoritmo de Viterbi para decodificar a trajetória latente mais provável e o procedimento Forward-Backward para calcular a probabilidade pontual de crise (`Prob_Crise_HMM`).

== Modelo Ensemble <subcap_modelo_ensemble>

O modelo misto buscou conciliar a inércia do particionamento geométrico à agilidade temporal da inferência bayesiana, aplicando princípios de combinação de múltiplos classificadores explorados por #cite(<kittler1998combining>, form: "prose") e 
#cite(<ho1994decision>, form: "prose"). A ponderação ideal foi determinada por um _Grid Search_ sobre as predições de calibração visando maximizar o _Calmar Ratio_ (Razão do Retorno Anualizado (CAGR - _Compound Annual Growth Rate_) 
pelo _Maximum Drawdown_) do portfólio. Essa métrica foi escolhida no lugar de métricas mais conhecidas como _Sharpe Ratio_ uma vez que debêntures pós-fixadas (atreladas ao CDI) possuem correlação direta com a 
taxa de juros e volatilidade intrínseca artificialmente próxima a zero, o que distorce o índice (_Sharpe Ratio_) na avaliação de prêmio de risco 
(tornando-o assintótico frente a prêmios negativos).

#figure(
  image("../imagens/sensitivity_ensemble_amarelo.png", width: 85%),
  caption: [Análise de Sensibilidade dos pesos do Ensemble no período In-Sample.]
) <fig_ensemble_sensitivity>

A combinação ótima alocou 70% de peso para o HMM e 30% para o K-Means:

$ "Probabilidade Sintética"_t = 0.70 times "Prob_Crise_HMM"_t + 0.30 times "Prob_Crise_KMeans"_t $

O sinal resultante recebeu suavização por média móvel exponencial de três dias ($"EMA"_3$, com fator $alpha = 0,5$), gerando a pontuação final de risco e atenuando oscilações de alta frequência.

== Protocolos de Validação Operacional <subcap_kupiec_backtest>

A validação operacional estruturou-se em duas frentes complementares sobre o período _Out-of-Sample_:

1. *Validação Estatística:* Teste de Proporção de Falhas de #cite(<kupiec1995techniques>, form: "prose") para cobertura incondicional e Teste de Cobertura Condicional de #cite(<christoffersen1998>, form: "prose") para verificar a independência temporal das violações do VaR a 99%;
2. *Simulador Financeiro de* _Backtest_: Execução diária de estratégias táticas de venda defensiva confrontadas com o carrego passivo (_Buy and Hold_). O simulador aplicou taxa de custo de transação de 0,5% (50 bps) por operação, remuneração diária de caixa a 100% do CDI, quarentena de 180 dias sem eventos para recompra e trava de _payback_ mínimo de 3 meses.

== Implementação em Código-Fonte

As rotinas a seguir, integradas a partir de `volatility.py` e `regime.py`, implementam a estimação do modelo EGARCH(1,1)-t, a derivação analítica das medidas de cauda com as travas matemáticas de estabilidade 
e o treinamento do classificador markoviano com suavização de Laplace:

```python
import numpy as np
import pandas as pd
import scipy.stats as stats
from arch import arch_model
from hmmlearn.hmm import GaussianHMM

class EconometricRiskEngine:
    """Estimação AR(1)-EGARCH(1,1)-t, VaR/ES analíticos e HMM regularizado."""

    @staticmethod
    def estimar_egarch_t(returns: pd.Series, split_idx: int, alpha: float = 0.01):
        """Calibra EGARCH(1,1)-t com restrições numéricas e deriva VaR e ES analíticos."""
        model = arch_model(returns * 100, mean='AR', lags=1, vol='EGARCH', p=1, o=1, q=1, dist='t', rescale=False)
        res_is = model.fit(last_obs=split_idx, disp='off', show_warning=False)
        res_oos = model.fix(res_is.params)

        cond_vol = res_oos.conditional_volatility / 100
        cond_mean = (returns * 100 - res_oos.resid) / 100
        nu = res_is.params.get('nu', 5.0)

        # 1. Trava matemática para caudas ultra-pesadas: nu ancorado marginalmente acima de 2
        nu_es = max(nu, 2.05)
        q_t = stats.t.ppf(1 - alpha, df=nu)
        es_t = stats.t.pdf(q_t, df=nu) / alpha * (nu + q_t**2) / (nu - 1) if nu > 1.01 else 5.0
        scale = np.sqrt(nu_es / (nu_es - 2))
        es_t_padronizado = es_t / scale

        # VaR e Expected Shortfall condicionais
        q_alpha = model.distribution.ppf(1 - alpha, nu)
        var_99 = cond_mean + cond_vol * q_alpha
        es_99 = cond_mean + cond_vol * es_t_padronizado

        # 2. Trava de teto de volatilidade: 20x o percentil 99 In-Sample contra divergência numérica
        vol_is_p99 = np.nanpercentile(cond_vol.iloc[:split_idx], 99)
        vol_teto = max(vol_is_p99 * 20.0, 0.05)
        invalid = cond_vol > vol_teto
        cond_vol[invalid] = np.nan
        cond_vol = cond_vol.ffill().bfill()

        return cond_vol, np.minimum(var_99, 1.0), np.minimum(es_99, 1.0)

    @staticmethod
    def treinar_hmm_regularizado(X_treino: np.ndarray, lengths: list, n_estados: int = 3):
        """Ajusta Gaussian HMM impondo Suavização de Laplace e piso de 1% nas transições."""
        hmm = GaussianHMM(n_components=n_estados, covariance_type='diag', n_iter=100, random_state=42)
        hmm.fit(X_treino, lengths)

        # Matriz de transição empírica recalibrada sem transições inter-ticker
        states = hmm.predict(X_treino, lengths)
        trans_counts = np.zeros((n_estados, n_estados))
        pos = 0
        for l in lengths:
            seq = states[pos : pos + l]
            for t in range(len(seq) - 1):
                trans_counts[seq[t], seq[t + 1]] += 1
            pos += l

        # Suavização de Laplace e piso estocástico de 1%
        trans_counts += 1.0
        A = trans_counts / trans_counts.sum(axis=1, keepdims=True)
        A_piso = np.maximum(A, 0.01)
        hmm.transmat_ = A_piso / A_piso.sum(axis=1, keepdims=True)
        return hmm
```
