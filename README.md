# Credit Tail Analytics

> **Sistema Quantitativo de Alerta Antecipado e Inferência de Regimes Latentes de Crédito Privado no Mercado Brasileiro**

[![Python 3.10+](https://img.shields.io/badge/python-3.10%2B-blue.svg)](https://www.python.org/)
[![Poetry](https://img.shields.io/badge/dependency-poetry-purple.svg)](https://python-poetry.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Typst](https://img.shields.io/badge/docs-Typst%20ABNT-blueviolet.svg)](https://typst.app/)
[![Code Style: Black](https://img.shields.io/badge/code%20style-black-000000.svg)](https://github.com/psf/black)

O **Credit Tail Analytics** compreende um arcabouço computacional e econométrico ponta a ponta (*End-to-End*) concebido para a modelagem estocástica de risco de cauda e identificação de mudanças estruturais de regime (*Credit Regime Switching*) em debêntures corporativas negociadas no mercado secundário brasileiro de balcão (*over-the-counter*).

O projeto constitui o Trabalho de Conclusão de Curso do Programa de Pós-graduação *Lato Sensu* em Estatística para Ciências de Dados da Pontifícia Universidade Católica de Minas Gerais (PUC Minas). A investigação confronta diretamente métodos estocásticos com memória temporal latente (**Modelos Ocultos de Markov - Gaussian HMM**) e métodos geométricos atemporais (**K-Means**) integrados a filtros assimétricos de heterocedasticidade condicional (**AR(1)-EGARCH(1,1)-t**), avaliando o ganho marginal da dependência temporal na sinalização tempestiva de estresse corporativo e proteção patrimonial de carteiras sob fricção transacional.

---

## 1. Contexto Estrutural e Microestrutura do Mercado de Crédito Doméstico

Diferentemente das economias desenvolvidas com mercados de capitais maduros e contratos padronizados de *Credit Default Swaps* (CDS), o mercado brasileiro de dívida privada corporativa opera sob idiossincrasias microestruturais severas catalogadas por Sheng e Lora (2008):

1. **Fragmentação e Baixa Liquidez Secundária:** Grande dispersão de emissões com reduzido volume diário negociado, concentrando transações em balcão não organizado;
2. **Concentração em Títulos Pós-Fixados:** Ampla predominância de debêntures indexadas à taxa DI (CDI) ou ao IPCA acrescido de prêmio pré-fixado;
3. **Predomínio de Investidores Institucionais:** Concentração de custódia em fundos de investimento locais e seguradoras que adotam majoritariamente estratégias de carrego (*Buy and Hold*);
4. **Assimetria Informacional Acentuada:** Dependência crônica de relatórios defasados de agências de classificação de risco de crédito (*credit rating*), frequentemente reativas a eventos de estresse;
5. **Escassez de Derivativos de Proteção:** Ausência de liquidez em contratos líquidos de derivativos de crédito dedicados a debêntures locais, inviabilizando operações de *hedge* dinâmico puro;
6. **Dependência de Garantias Reais e Fidejussórias:** Estruturação de covenants contratuais complexos com renegociação lenta em recuperações judiciais;
7. **Prazos Médios Curtos a Intermediários:** Maturidades concentradas de curto a médio prazo, ampliando o risco de refinanciamento corporativo.

Sob essa configuração de mercado, a observabilidade contínua de preços é prejudicada por cotações meramente indicativas e ausência de *market makers*. Isso gera um desafio econométrico de primeira grandeza: séries temporais com saltos repentinos de reprecificação, heterocedasticidade condicional severa, assimetria de cauda e quebras estruturais de volatilidade.

---

## 2. Fundamentação Metodológica e Formulações Matemáticas Estritas

O sistema opera a partir de uma arquitetura modular de três camadas complementares:

```
┌────────────────────────────────────────────────────────────────────────┐
│                   Camada 1: Econometria de Cauda                       │
│    Séries de Spread ──► AR(1)-EGARCH(1,1)-t ──► VaR(99%) & ES(99%)     │
│       Travas Numéricas: ν >= 2.05 | Teto Volatilidade <= 20x P99       │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ Features Saneadas e Causalmente Padronizadas
┌───────────────────────────────────▼────────────────────────────────────┐
│              Camada 2: Inferência de Regimes Latentes                  │
│    Seleção por Borda Count ──► K-Means Polarizado (Lloyd, k=3)         │
│                            └──► Gaussian HMM (Laplace & Piso 1%, k=3)  │
│                 Ensemble Ponderado (70% HMM / 30% KM) + EMA3           │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ Probabilidade Sintética de Estresse
┌───────────────────────────────────▼────────────────────────────────────┐
│            Camada 3: Validação Operacional e Auditoria                 │
│  Backtest Tático (50 bps, Quarentena 180d) ──► Kupiec POF / Christoff. │
│  Auditoria Estatística Não Paramétrica via Block Bootstrap (10.000 it) │
└────────────────────────────────────────────────────────────────────────┘
```

### 2.1 Modelagem da Volatilidade Condicional e Medidas Coerentes de Risco

Para modelar o comportamento de dispersão condicional dos prêmios de risco de crédito ($\Delta S_t = S_t - S_{t-1}$), implementa-se o modelo autorregressivo com variância condicional exponencial (AR(1)-EGARCH(1,1)) parametrizado sob inovação t-Student (Nelson, 1991):

#### Equação da Média Condicional:
$$\Delta S_t = \mu + \phi \Delta S_{t-1} + \epsilon_t, \quad \epsilon_t = \sigma_t z_t$$

onde $z_t \sim t_\nu(0, 1)$ representa uma variável aleatória t-Student padronizada com $\nu > 2$ graus de liberdade e função de densidade de probabilidade dada por:

$$f(z; \nu) = \frac{\Gamma\left(\frac{\nu+1}{2}\right)}{\sqrt{\pi(\nu-2)}\,\Gamma\left(\frac{\nu}{2}\right)} \left(1 + \frac{z^2}{\nu-2}\right)^{-\frac{\nu+1}{2}}$$

#### Equação da Variância Condicional Logarítmica:
$$\ln(\sigma_t^2) = \omega + \beta \ln(\sigma_{t-1}^2) + \alpha \left( |z_{t-1}| - \mathbb{E}[|z_{t-1}|] \right) + \gamma z_{t-1}$$

sendo a esperança matemática do valor absoluto dos resíduos padronizados t-Student expressa analiticamente por:

$$\mathbb{E}[|z_t|] = \frac{2 \sqrt{\nu - 2} \, \Gamma\left(\frac{\nu + 1}{2}\right)}{(\nu - 1) \sqrt{\pi} \, \Gamma\left(\frac{\nu}{2}\right)}$$

- **Efeito de Assimetria de Crédito:** O parâmetro $\gamma$ capta a assimetria na resposta da volatilidade. No mercado de crédito, $\gamma < 0$ indica que choques negativos de solvência (alargamento nos spreads, $z_{t-1} > 0$ sob convenção de risco ou $\epsilon_{t-1} > 0$) elevam a volatilidade com intensidade exponencialmente superior a variações de estreitamento de mesma magnitude.
- **Persistência Volátil:** O coeficiente $\beta$ mede a inércia temporal da volatilidade condicional, cumprindo o pressuposto de estacionariedade com $|\beta| < 1$.

#### Travas Numéricas de Convergência Estocástica:
Para neutralizar quebras de cálculo em debêntures de baixa liquidez secundária, aplicam-se duas travas determinísticas:
1. **Ancoragem de Curtose Finita:** Restringe os graus de liberdade a $\nu = \max(2.05, \nu_{\text{est}})$, garantindo a integridade assintótica do segundo momento central da distribuição t-Student ($\text{Var}(z_t) = \frac{\nu}{\nu - 2} < \infty$);
2. **Teto Prudencial de Dispersão:** Limita picos artificiais de variância através de:
   $$\sigma_{\text{est}}(t) = \sigma_{\text{est}}(t-1) \quad \text{se} \quad \sigma_{\text{est}}(t) > 20 \times P_{99}(\sigma_{\text{IS}})$$
   sendo $P_{99}(\sigma_{\text{IS}})$ o percentil 99 da volatilidade condicional estimada na janela de treino (*In-Sample*).

#### Dedução Analítica de VaR e Expected Shortfall (ES):
A partir dos parâmetros estimados, deriva-se parametricamente o Valor em Risco ($VaR_{\alpha}$) para o nível de significância $\alpha = 0,01$ (confiança de 99%):

$$VaR_{\alpha}(t) = \mu_t + \sigma_t \cdot t^{-1}_{\nu}(1 - \alpha)$$

onde $t^{-1}_{\nu}(\cdot)$ é a função quantil da distribuição t-Student padronizada. 

Diferentemente do VaR, que viola o axioma da subaditividade quando aplicado a distribuições com caudas pesadas ou discretas (Artzner et al., 1999), o *Expected Shortfall* ($ES_\alpha$, ou *Conditional Value-at-Risk* - CVaR) quantifica a expectativa condicional das perdas que ultrapassam o limiar do VaR:

$$ES_{\alpha}(t) = \mathbb{E}\left[ \Delta S_t \mid \Delta S_t > VaR_{\alpha}(t) \right]$$

Sob inovação t-Student padronizada, a solução analítica em forma fechada implementada no motor matemático assume a formulação (Acerbi & Tasche, 2002):

$$ES_{\alpha}(t) = \mu_t + \sigma_t \cdot \left[ \frac{f_\nu(q_\alpha)}{\alpha} \left( \frac{\nu + q_\alpha^2}{\nu - 1} \right) \right] \cdot \sqrt{\frac{\nu - 2}{\nu}}$$

sendo $q_\alpha = t^{-1}_{\nu}(1 - \alpha)$ e $f_\nu(\cdot)$ a função densidade da t-Student padronizada. O termo $\sqrt{\frac{\nu - 2}{\nu}}$ efetua o reescalonamento exato para a variância unitária. O $ES$ cumpre rigorosamente os 4 axiomas de uma **medida coerente de risco**:
1. *Monotonicidade:* $X \le Y \implies \rho(X) \ge \rho(Y)$
2. *Subaditividade:* $\rho(X + Y) \le \rho(X) + \rho(Y)$ (estímulo à diversificação prudencial)
3. *Homogeneidade Positiva:* $\rho(\lambda X) = \lambda \rho(X), \; \forall \lambda \ge 0$
4. *Invariância por Translação:* $\rho(X + c) = \rho(X) - c, \; \forall c \in \mathbb{R}$

---

### 2.2 Engenharia de Recursos Causal e Seleção Multivariada por Consenso de Borda

#### Saneamento Temporal e Padronização Causal:
- **Filtro de Iliquidez:** Expurgo das debêntures classificadas na Faixa 3 (sem cotação ou sem negociação) em $\ge 95\%$ das observações da janela *In-Sample* (2018-2022).
- **Winsorização Causal:** Tratamento de valores espúrios com corte nos quantis $1\%$ e $99\%$ calibrados estritamente na base *In-Sample*, eliminando integralmente qualquer viés de antecipação temporal (*look-ahead bias*):
  $$x_{\text{winsor}}(t) = \min(\max(x_t, Q_{0.01}^{\text{IS}}), Q_{0.99}^{\text{IS}})$$
- **Escalonamento Robusto:** Normalização via mediana e intervalo interquartil resistente a eventos de estresse:
  $$x_{\text{scaled}}(t) = \frac{x_t - \text{Mediana}(x_{\text{IS}})}{Q_{75}^{\text{IS}} - Q_{25}^{\text{IS}}}$$

#### Função de Consenso Ordinal de Borda:
Para selecionar o subconjunto ideal de variáveis sem introduzir ponderações arbitrárias, implementa-se o Método de Contagem de Borda (Borda, 1781; Ho et al., 1994; Kittler et al., 1998) avaliando 120 combinações candidatas:

$$R_{\text{Borda}}(C_k) = \sum_{m \in \mathcal{M}} \left( N_{\text{comb}} + 1 - \text{Rank}_m(C_k) \right)$$

onde $\mathcal{M} = \{\text{Silhouette}, \text{Davies-Bouldin}, \ln(1 + \text{Calinski-Harabasz})\}$. As formulações das métricas avaliadas compreendem:

1. **Índice Silhouette ($s_i$):**
   $$s(i) = \frac{b(i) - a(i)}{\max(a(i), b(i))}, \quad S = \frac{1}{N}\sum_{i=1}^N s(i)$$
   medindo a coesão intra-cluster $a(i)$ contra a menor separação inter-cluster $b(i)$ no intervalo $[-1, 1]$.
2. **Índice Davies-Bouldin ($DB$):**
   $$DB = \frac{1}{k} \sum_{i=1}^k \max_{j \neq i} \left( \frac{\sigma_i + \sigma_j}{d(c_i, c_j)} \right)$$
   avaliando a razão de dispersão interna pela distância euclidiana entre os centroides (menor é melhor).
3. **Índice Calinski-Harabasz ($CH$):**
   $$CH = \frac{\text{Tr}(\mathbf{B}_k) / (k - 1)}{\text{Tr}(\mathbf{W}_k) / (N - k)}$$
   contrastando a matriz de dispersão entre grupos $\mathbf{B}_k$ com a dispersão intra-grupos $\mathbf{W}_k$.

O trio ótimo eleito pelo Borda Count com pontuação máxima foi composto por:
- `Taxa_ZScore`: Spread normalizado causal em relação ao histórico do título;
- `Volatilidade_EGARCH`: Volatilidade condicional diária do modelo assimétrico;
- `Expected_Shortfall_99`: Medida coerente de cauda condicional a 99%.

---

### 2.3 Inferência de Regimes Latentes: Linha de Base Geométrica vs. Inferência Markoviana

O sistema opera com $k=3$ regimes fundamentais de mercado:
- **Regime 1 (Verde - Baixo Risco):** Spreads estáveis, baixa volatilidade condicional e prêmio de liquidez comprimido;
- **Regime 2 (Amarelo - Alerta de Liquidez):** Incerteza crescente, dispersão de cotações, elevação de volatilidade de curto prazo;
- **Regime 3 (Vermelho - Estresse Estrutural):** Alargamento substancial de spread, quebras de covenants, risco manifesto de recuperação judicial ou inadimplência.

#### Linha de Base Geométrica (K-Means com Polaridade Determinística):
Minimiza a inércia intra-cluster pelo algoritmo de Lloyd:

$$\arg\min_{\mathcal{S}} \sum_{k=1}^3 \sum_{\mathbf{x} \in S_k} \|\mathbf{x} - \boldsymbol{\mu}_k\|^2$$

- **Eliminação do *Label Switching*:** Para assegurar que o rótulo de crise corresponda ao regime de maior periculosidade em todas as reestimações, projeta-se os centroides no vetor determinístico de polaridade de risco:
  $$\mathbf{w}_{\text{risco}} = [0.30, 0.30, 0.40]^T \quad \Longrightarrow \quad \rho_k = \mathbf{c}_k \cdot \mathbf{w}_{\text{risco}}$$
  Os centroides são ordenados monotonicamente: $\rho_{\text{Verde}} < \rho_{\text{Amarelo}} < \rho_{\text{Vermelho}}$.
- **Probabilidade Pontual de Crise:**
  $$P_{\text{Crise, KM}}(t) = \frac{\|\mathbf{x}_t - \mathbf{c}_{\text{Vermelho}}\|^{-1}}{\sum_{j=1}^3 \|\mathbf{x}_t - \mathbf{c}_j\|^{-1}}$$

#### Cadeia Oculta de Markov (Gaussian HMM):
Modela o vetor tridimensional de atributos observados $\mathbf{y}_t \in \mathbb{R}^3$ condicionado a uma sequência latente de estados $S_t \in \{1, 2, 3\}$ com dinâmica de Markov de primeira ordem (Rabiner, 1989):

$$P(S_t = j \mid S_{t-1} = i) = A_{ij}, \quad \mathbf{y}_t \mid (S_t = j) \sim \mathcal{N}_3(\boldsymbol{\mu}_j, \boldsymbol{\Sigma}_j)$$

- **Regularização com Prior de Laplace e Piso de Ergodicidade:**
  Para impedir que regimes de estresse com poucas observações se tornem estados absorventes estocasticamente intransponíveis ($A_{33} = 1.0$), aplica-se a suavização aditiva com piso de 1%:
  $$A'_{ij} = \frac{C_{ij} + \alpha}{\sum_{k=1}^3 C_{ik} + 3\alpha}, \quad A''_{ij} = \max(A'_{ij}, 0.01) \quad \Longrightarrow \quad A_{ij} = \frac{A''_{ij}}{\sum_{k=1}^3 A''_{ik}}$$
  adotando-se hiperparâmetro de Laplace $\alpha = 1.0$.
- **Inferência Causal das Probabilidades a Posteriori (Forward-Backward):**
  $$\gamma_t(j) = P(S_t = j \mid \mathbf{Y}_{1:t}) = \frac{\alpha_t(j)}{\sum_{k=1}^3 \alpha_t(k)}$$
- **Decodificação Global de Trajetória (Algoritmo de Viterbi):**
  $$\hat{S}_{1:T} = \arg\max_{S_{1:T}} P(S_{1:T}, \mathbf{Y}_{1:T})$$

#### Arquitetura Ensemble Convexa e Filtragem Exponencial:
A conciliação dos modelos opera via combinação linear convexa calibrada por *Grid Search* na base *In-Sample* visando a maximização do *Calmar Ratio*:

$$\text{Probabilidade Sintética}_t = 0.70 \times P_{\text{Crise, HMM}}(t) + 0.30 \times P_{\text{Crise, KM}}(t)$$

O sinal gerado recebe amortecimento temporal via média móvel exponencial de três dias ($EMA_3$, com $\alpha = 0.5$):

$$\bar{P}_t = 0.5 \times P_t + 0.5 \times \bar{P}_{t-1}$$

---

### 2.4 Validação Estatística de Cauda: Testes de Kupiec e Christoffersen

A validação regulatória fora da amostra (*Out-of-Sample*, 2023 a 2026) sobre 663 séries temporais adota testes de razão de verossimilhança (*Likelihood Ratio*):

1. **Teste de Proporção de Falhas de Kupiec (POF - Cobertura Incondicional):**
   Testa se a proporção observada de violações de cauda $\hat{p} = x/T$ coincide estatisticamente com a taxa teórica $p = 0.01$:
   $$LR_{\text{POF}} = -2 \ln \left[ \frac{(1 - p)^{T - x} p^x}{(1 - \hat{p})^{T - x} \hat{p}^x} \right] \sim \chi^2(1)$$
2. **Teste de Independência de Christoffersen:**
   Verifica a ausência de agrupamento de violações (*clustering* de perdas extremas) via matriz de transição de indicadores $I_t \in \{0, 1\}$:
   $$LR_{\text{ind}} = -2 \ln \left[ \frac{(1 - \pi_0)^{n_{00}} \pi_0^{n_{01}} (1 - \pi_1)^{n_{10}} \pi_1^{n_{11}}}{(1 - \pi_{01})^{n_{00} + n_{10}} \pi_{01}^{n_{01} + n_{11}}} \right] \sim \chi^2(1)$$
3. **Teste de Cobertura Condicional Conjunto:**
   $$LR_{\text{CC}} = LR_{\text{POF}} + LR_{\text{ind}} \sim \chi^2(2)$$

---

### 2.5 O Paradoxo da Acurácia-Rentabilidade no Backtest Financeiro

A simulação computacional de carteiras com liquidação defensiva contra o estresse expôs uma relevante dicotomia empírica:

$$\text{Superioridade Preditiva (HMM)} \quad \centernot\implies \quad \text{Superioridade Econômica Líquida}$$

#### Premissas Operacionais do Backtest:
- **Custo Transacional de Fricção:** 50 bps (0,50%) por perna de negociação (alienação e posterior recompra), espelhando o *spread bid-ask* e o impacto de mercado em debêntures de liquidez restrita;
- **Quarentena Mínima de Bloqueio:** 180 dias úteis de proibição de recompra após a liquidação de um ativo sinalizado em alerta/crise;
- **Remuneração de Caixa Ocioso:** Rendimento a 100% da taxa CDI diária livre de risco.

#### Mecanismos Econômicos Identificados:
1. **Sensibilidade Hiper-Reativa do HMM e Turnover Destrutivo:** O modelo markoviano detecta prontamente oscilações estocásticas de volatilidade. Contudo, em ambientes ilíquidos, flutuações transitórias de cotação disparam saídas prematuras, acumulando custos de atrito de 50 bps e provocando perda de carrego (*carry loss*);
2. **Inércia Protetiva do K-Means (Filtro Passa-Baixa Natural):** Ao ignorar a dependência temporal de curto prazo, o K-Means atua como um filtro purificador de ruído. Ele sustenta a posição durante reprecificações temporárias e liquida a carteira exclusivamente mediante deterioração estrutural persistente dos centroides multivariados, alcançando rentabilidade superior com menor *drawdown*;
3. **Efeito Chicote (*Whipsaw*) no Ensemble:** A combinação linear entre a velocidade markoviana e a inércia estática gerou sinais ambíguos na zona de fronteira decisória, fazendo a carteira desinvestir tardiamente e recomprar sob condições desfavoráveis, depreciando o retorno acumulado líquido.

---

### 2.6 Auditoria Não Paramétrica por Block Bootstrap Estacionário

Para testar a significância estatística do retorno excedente do K-Means contra o referencial passivo *Buy and Hold*, implementa-se o **Block Bootstrap Estacionário** (Politis & Romano, 1994):
- **Iterações:** 10.000 repetições de reamostragem com reposição;
- **Tamanho dos Blocos:** Blocos aleatórios com comprimento médio $L = 20$ dias úteis (1 mês comercial), preservando a dependência serial e a heterocedasticidade condicional das séries;
- **Teste de Hipótese Bicaudal:** $H_0: \mathbb{E}[\Delta R] \le 0$ versus $H_1: \mathbb{E}[\Delta R] > 0$, obtendo-se $p\text{-valor} = 0,0416 < 0,05$, atestando que o alfa gerado pelo K-Means Vende Amarelo é estatisticamente significante.

---

## 3. Síntese do Canvas Analítico de Ciência de Dados

Conforme formalizado na Seção 3 do Trabalho de Conclusão de Curso, o Canvas Analítico consolida a visão estratégica e arquitetural do projeto:

| Bloco | Especificação Técnica do Projeto |
| :--- | :--- |
| **1. Problema de Negócio** | Deterioração de solvência e choques de liquidez em debêntures corporativas brasileiras gerando perdas patrimoniais severas e deságios de marcação a mercado. |
| **2. Objetivo Analítico** | Desenvolver um sistema ponta a ponta que estime volatilidade e medidas coerentes de cauda (VaR/ES 99%) e classifique regimes latentes de crédito. |
| **3. Justificativa** | Ratings de crédito tradicionais são defasados; spreads brutos sofrem distorções de prazo/juros; modelos puramente gaussianos subestimam caudas pesadas. |
| **4. Stakeholders** | Gestores de crédito privado, comitês de risco de mercado, mesas de renda fixa, alocadores institucionais e reguladores de mercado de capitais. |
| **5. Variável-alvo** | Variância condicional do spread $\sigma_t^2$ e regimes latentes de solvência $S_t \in \{\text{Verde, Amarelo, Vermelho}\}$. |
| **6. Variáveis de Entrada** | Spread de crédito, PU médio, volume financeiro, Z-Score temporal de spread, volatilidade condicional EGARCH-t e Expected Shortfall (99%). |
| **7. Fontes de Dados** | ANBIMA (Sistemas REUNE e Prévia Diária), Debentures.com.br (Cadastros) e Banco Central do Brasil (SGS: CDI, Selic, IPCA). |
| **8. Modelagem Estatística** | AR(1)-EGARCH(1,1)-t, Seleção Combinatória por Borda Count, K-Means com Ordenação Polarizada e Gaussian HMM com Regularização de Laplace. |
| **9. Métricas de Avaliação** | Não-rejeição de Kupiec POF / Christoffersen (VaR 99%), Calmar Ratio, Drawdown Máximo, Retorno Líquido (50 bps) e Block Bootstrap ($p < 0,05$). |
| **10. Entregáveis** | Pacote Python modular (`credit_tail_analytics`), CLI de pipeline, base analítica estruturada e Relatório Técnico ABNT compilado em Typst. |
| **11. Impacto Esperado** | Proteção de capital em eventos extremos de crédito, mitigação de custos de turnover e compliance com normas de governança e auditoria. |
| **12. Restrições e Riscos** | Iliquidez severa no mercado secundário (Faixa 3), quebras estruturais em períodos de estresse sistêmico e fricção operacional de saída. |

---

## 4. Estrutura do Pacote e Arquitetura Computacional

A distribuição modular do pacote `credit_tail_analytics` segue os padrões da engenharia de software científica:

```text
src/credit_tail_analytics/
├── data/                            # Camada de Ingestão e Engenharia Cadastral
│   ├── anbima_scraper.py            # Coletor automatizado do sistema REUNE (Selenium)
│   ├── download_macro.py            # Extração de séries temporais SGS/BACEN (python-bcb)
│   ├── build_cadastro.py            # Harmonização cadastral (Debentures.com.br / ANBIMA Data)
│   ├── unify_csvs.py                # Integração transacional de spreads, preços e volumes
│   └── run_scraper_full.py          # Orquestrador CLI central de coleta e saneamento
│
├── models/                          # Camada Quantitativa e Algoritmos de Risco
│   ├── credit_risk/
│   │   ├── preprocessor.py          # Saneamento de iliquidez, winsorização causal e RobustScaler
│   │   ├── volatility.py            # Calibração AR(1)-EGARCH-t, estimação de VaR/ES e travas numéricas
│   │   ├── feature_selection.py     # Otimização combinatória com Função de Consenso de Borda
│   │   ├── regime.py                # Classificadores (K-Means Polarizado e Gaussian HMM Laplace)
│   │   ├── risk_pipeline.py         # Fachada orquestradora central (CreditRiskEngine)
│   │   └── run_frequentist_engine.py# Ponto de entrada CLI para modelagem e inferência
│   └── clustering/                  # Abstrações base para métodos não supervisionados
│
├── analysis/                        # Camada de Validação Estatística e Backtest
│   ├── selecao_modelos.py           # Avaliação comparativa de 32 classes GARCH por AIC
│   ├── kupiec_validation.py         # Testes de Kupiec POF e Cobertura Condicional de Christoffersen
│   ├── backtest_financeiro.py       # Simulador contábil de carteira com fricção de 50 bps e quarentena
│   ├── run_cluster_validation.py    # Diagnóstico do Elbow Method e Silhouette Score (k=3)
│   ├── run_ensemble_sensitivity.py  # Grid Search de pesos do Ensemble via Calmar Ratio
│   ├── run_bootstrap.py             # Auditoria não paramétrica via Block Bootstrap (10.000 iterações)
│   ├── gerar_resumo_kupiec.py       # Extração tabular de métricas regulatórias de cauda
│   └── check_anomalies.py           # Diagnósticos de curtose, assimetria e raiz unitária (ADF/PP)
│
├── visualization/                   # Camada de Apresentação Gráfica e Estudos de Caso
│   ├── frequentist_defense_visuals.py # Diagnóstico temporal em casos reais (GPA, Light, CVC Corp)
│   ├── kupiec_visuals.py            # Curvas de sensibilidade de não-rejeição regulatória
│   ├── plot_feature_selection.py    # Diagrama de Borda Count das variáveis avaliadas
│   ├── plot_borda_radar.py          # Radar de coesão multidimensional
│   └── plot_early_warning.py        # Comparações de Lead Time por modelo e evento corporativo
│
└── utils.py                         # Funções utilitárias de logging, caminhos e rotulagem
```

---

## 5. Instalação e Configuração do Ambiente

O gerenciamento de dependências utiliza o **Poetry**, assegurando o travamento determinístico de versões de pacotes matemáticos.

### 5.1 Pré-requisitos do Sistema
- Python >= 3.10 e < 3.12
- Google Chrome instalado localmente (necessário para o driver Selenium do raspador ANBIMA)
- Poetry instalado (`pip install poetry`)
- Compilador Typst (opcional, para compilação local do relatório técnico em PDF)

### 5.2 Procedimento de Configuração

```bash
# 1. Clonagem do repositório
git clone https://github.com/gtazevedo/credit-tail-analytic.git
cd credit-tail-analytic

# 2. Instalação determinística de dependências via Poetry
poetry install

# 3. Ativação do ambiente virtual
poetry shell
```

Caso prefira a instalação via ambiente virtual padrão `venv` e `pip`:

```bash
python -m venv .venv
# Linux/macOS:
source .venv/bin/activate
# Windows:
.venv\Scripts\activate

pip install -e .
```

---

## 6. Guia de Execução do Pipeline Ponta a Ponta (CLI)

O pipeline permite a reprodução integral dos experimentos científicos descritos no relatório técnico da PUC Minas.

### Etapa 1: Ingestão, Saneamento e Cruzamento Cadastral
Executa o web scraping das prévias diárias da ANBIMA (REUNE), extrai os metadados cadastrais via `debentures_dot_com` e baixa as séries de juros e inflação do SGS/BACEN (CDI, Selic, IPCA):

```bash
poetry run python src/credit_tail_analytics/data/run_scraper_full.py
```
> **Artefato Gerado:** Base histórica consolidada de debêntures corporativas e curvas de juros/inflação saneadas.

### Etapa 2: Seleção Comparativa de Modelos Heterocedásticos (GARCH)
Executa a varredura comparativa de 32 especificações GARCH sobre 529 debêntures no período *In-Sample* (2018-2022), determinando o menor Critério de Informação de Akaike (AIC):

```bash
poetry run python src/credit_tail_analytics/analysis/selecao_modelos.py
```
> **Artefatos Gerados:** Gráficos de ranking médio em `graficos/comparacao_modelos_ranking_n*.png`.

### Etapa 3: Execução do Motor de Risco Principal (Risk Engine)
Aplica o filtro de liquidez (expurgo Faixa 3 $\ge 95\%$), padronização causal `RobustScaler`, calibração do modelo AR(1)-EGARCH(1,1)-t, cálculo analítico de $VaR_{0.01}$ e $ES_{0.01}$, busca de variáveis por Borda Count e estimação dos modelos K-Means e Gaussian HMM com prior de Laplace:

```bash
poetry run python src/credit_tail_analytics/models/credit_risk/run_frequentist_engine.py
```
> **Artefato Gerado:** Base analítica processada contendo estimativas de volatilidade condicional, medidas de cauda ($VaR_{0.01}$ e $ES_{0.01}$) e probabilidades de regime de risco.

### Etapa 4: Validação Estatística de Cauda (Kupiec e Christoffersen)
Calcula as taxas de aprovação nos testes de Proporção de Falhas (POF) e Cobertura Condicional na base *Out-of-Sample* (2023-2026):

```bash
poetry run python src/credit_tail_analytics/analysis/kupiec_validation.py
poetry run python src/credit_tail_analytics/visualization/kupiec_visuals.py
```
> **Artefatos Gerados:** Tabelas regulatórias e curva de sensibilidade em `graficos/kupiec_approval_rate.png`.

### Etapa 5: Simulação de Backtest Financeiro Tático
Simula a alocação de carteiras defensivas ativas sob custo de 50 bps por operação, quarentena de 180 dias e remuneração de caixa a 100% do CDI:

```bash
poetry run python src/credit_tail_analytics/analysis/backtest_financeiro.py
```
> **Artefatos Gerados:** Curvas de patrimônio em `graficos/backtest_pnl_portfolio.png` e métricas estatísticas consolidadas de rentabilidade e risco.

### Etapa 6: Auditoria Estatística Não Paramétrica via Block Bootstrap
Executa 10.000 iterações de reamostragem em blocos de 20 dias úteis para testar a significância do alfa contra a estratégia passiva *Buy and Hold*:

```bash
poetry run python src/credit_tail_analytics/analysis/run_bootstrap.py
```
> **Artefatos Gerados:** Distribuição empírica em `graficos/bootstrap_significance.png` e cálculo de $p\text{-valor} = 0,0416$.

### Etapa 7: Visualizações Diagnósticas e Análise de Eventos Reais
Gera os painéis analíticos temporais detalhando trajetórias de probabilidade e métricas de antecipação (*Lead Time*) em casos reais de estresse corporativo (GPA, Light S.A., CVC Corp, Dasa, Unigel):

```bash
poetry run python src/credit_tail_analytics/visualization/frequentist_defense_visuals.py
poetry run python src/credit_tail_analytics/visualization/plot_early_warning.py
```
> **Artefatos Gerados:** Painéis de acompanhamento temporal em `graficos/`.

---

## 7. Resultados Empíricos e Diagnósticos Quantitativos

Os experimentos computacionais conduzidos sobre o universo empírico de 529 debêntures corporativas no período *In-Sample* (2018 a 2022) e 663 séries na janela *Out-of-Sample* (2023 a 2026) revelaram os seguintes resultados consolidados:

### 7.1 Métricas de Desempenho no Backtest Financeiro (2023 - 2026)

| Estratégia | Retorno Total Acumulado | Taxa Anualizada (CAGR) | Volatilidade Anualizada | Máximo Drawdown | Calmar Ratio | P-Valor (*Block Bootstrap*) |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **Buy-and-Hold (Referencial Passivo)** | 22,42% | 5,98% | 3,50% | -4,79% | 1,249 | Hipótese Nula ($H_0$) |
| **K-Means (Vende Amarelo - Alerta)** | **36,18%** | **9,27%** | 8,92% | -5,78% | **1,603** | **$p = 0,0416$ (Significante a 5%)** |
| **K-Means (Padrão - Vende Vermelho)** | 27,06% | 7,11% | 4,29% | **-4,16%** | **1,711** | $p = 0,1182$ (Não Significante) |
| **HMM (Vende Amarelo - Alerta)** | 32,62% | 8,44% | 12,56% | -9,74% | 0,866 | $p = 0,2140$ (Não Significante) |
| **HMM (Padrão - Vende Vermelho)** | 25,95% | 6,85% | 8,82% | -6,71% | 1,021 | $p = 0,3815$ (Não Significante) |
| **Ensemble (Vende Amarelo - Alerta)** | 17,58% | 4,76% | 4,70% | -4,12% | 1,156 | $p = 0,8450$ (Não Significante) |
| **Ensemble (Padrão - Vende Vermelho)**| 16,37% | 4,45% | 4,68% | -4,00% | 1,111 | $p = 0,8910$ (Não Significante) |

### 7.2 Diagnóstico de Antecipação Temporal (*Lead Time*) em Eventos Críticos

O comportamento comparativo entre os modelos foi auditado em episódios reais de estresse corporativo:

| Empresa Emissora | Tipo de Evento | Spread Máximo Atingido | Alerta Contínuo (HMM) | Alerta Contínuo (K-Means) | Quarentena 180d (K-Means) |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **Light S.A.** | Recuperação Judicial | 120,9% | 5 dias antes | 3 dias antes | **102 dias antes** |
| **CVC Brasil** | Reperfilamento de Dívida | 21,0% | 78 dias antes | 669 dias atrasado | **669 dias atrasado** |
| **Dasa** | Reperfilamento de Dívida | 163,8% | 1 dia atrasado | 19 dias atrasado | **106 dias antes** |
| **Multilaser** | Quebra de *Waiver* | 118,4% | 5 dias atrasado | 18 dias atrasado | **148 dias antes** |
| **Unigel** | Recuperação Extrajudicial | 87,5% | 357 dias antes | 253 dias antes | **169 dias antes** |
| **Grupo Pão de Açúcar (GPA)** | Reestruturação | 190,7% | 2 dias antes | 129 dias atrasado | **164 dias antes** |

*Conclusão Operacional:* Enquanto a dependência temporal do HMM se mostra superior para a emissão de alertas contínuos e tempestivos para monitoramento dinâmico de risco, o K-Means associado a uma diretriz de quarentena de 180 dias protege a carteira com eficácia superior contra o choque principal, evitando custos excessivos de giro em reprecificações passageiras.

---

## 8. Documentação Acadêmica e Citação Institucional

O Trabalho de Conclusão de Curso (Relatório Técnico) encontra-se redigido em [Typst](https://typst.app/), em estrita conformidade com as diretrizes do Núcleo de Educação a Distância da PUC Minas e com as normas técnicas da ABNT vigentes:

- **Código-Fonte do Relatório:** `academic/pos/main.typ`
- **Folha de Estilo ABNT PUC Minas:** `academic/pos/abnt.typ`
- **Relatório Técnico Compilado (PDF):** `academic/pos/TCC_Pos.pdf`
- **Extensão Rigorosa do Relatório:** 20 laudas (páginas), cumprindo a exigência institucional da PUC Minas.

### Como Citar Este Trabalho (ABNT / BibTeX):

```bibtex
@mastersthesis{azevedo2026credittail,
  author       = {Guilherme Tolotti Azevedo},
  title        = {Modelagem de Risco de Cauda no Mercado de Cr{\'e}dito Privado: Uma Abordagem H{\'i}brida via EGARCH-t e Modelos Ocultos de Markov},
  school       = {Pontif{\'i}cia Universidade Cat{\'o}lica de Minas Gerais, N{\'u}cleo de Educa{\c{c}}{\~a}o a Dist{\^a}ncia},
  year         = {2026},
  type         = {Monografia (Especializa{\c{c}}{\~a}o em Estat{\'i}stica para Ci{\^e}ncias de Dados)},
  address      = {Belo Horizonte},
  url          = {https://github.com/gtazevedo/credit-tail-analytic}
}
```

---

## 9. Licença e Isenção de Responsabilidade Legal (*Disclaimer*)

Este software e todos os artefatos analíticos correlatos são distribuídos sob a licença de código aberto **MIT** (consulte o arquivo `LICENSE` na raiz deste repositório para os termos integrais).

> **Aviso de Isenção Legal e Financeira:** O conteúdo deste repositório destina-se estritamente a propósitos científicos, acadêmicos e educacionais. As simulações de *backtest*, medidas de risco ($VaR$, $Expected Shortfall$), projeções econométricas e probabilidades de regime aqui apresentadas **não constituem, sob nenhuma hipótese, assessoria financeira, aconselhamento de investimentos, recomendação de compra ou venda de títulos mobiliários ou qualquer tipo de prestação de serviços de análise de valores mobiliários** regulados pela Comissão de Valores Mobiliários (CVM), pela ANBIMA ou por qualquer outro órgão regulador dos mercados de capitais. Rentabilidades simuladas ou passadas não representam garantia de retornos futuros.
