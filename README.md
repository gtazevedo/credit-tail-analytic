# Credit Tail Analytics

> ⚠️ **Aviso:** Este projeto encontra-se em fase de desenvolvimento ativo e contínuo (Work in Progress). A arquitetura, as metodologias quantitativas e as APIs podem sofrer alterações sem aviso prévio.

**Um motor quantitativo End-to-End para modelagem de risco de cauda e identificação de regimes de crédito (Credit Regime Switching) no mercado secundário de debêntures brasileiro.**

Este projeto foi desenvolvido como um Trabalho de Conclusão de Curso (TCC) em finanças quantitativas/ciência de dados. A tese central é que modelos estocásticos de transição de estados com memória temporal (como **Hidden Markov Models - HMM**) combinados com extração de volatilidade assimétrica (**EGARCH-t**) oferecem uma proteção de capital superior e sinalização antecipada de crises (Tail Risk) quando comparados a algoritmos clássicos de clusterização atemporal (como K-Means).

## Arquitetura do Pacote

O projeto foi refatorado em um pacote Python modular (`credit_tail_analytics`), estruturado da seguinte forma:

```text
src/credit_tail_analytics/
│
├── data/                  # Ingestão e cruzamento de dados (Web Scraping B3/ANBIMA, SGS BCB)
├── models/
│   ├── credit_risk/       # Engine central (Feature Engineering, EGARCH, K-Means, HMM)
│   └── clustering/        # Utilitários abstratos de aprendizado de máquina
├── analysis/              # Validação acadêmica (Torneio GARCH, Feature Selector, Backtest)
├── visualization/         # Geração de gráficos analíticos e painéis de defesa empírica
└── utils.py               # Gerenciamento robusto de caminhos (dados/, graficos/)
```

---

## Instalação

Recomenda-se o uso de um ambiente virtual (ex: `venv` ou `conda`). Para instalar o pacote e suas dependências em modo editável:

```bash
# Na raiz do projeto
pip install -e .
```

Isso instalará automaticamente bibliotecas como `arch` (para EGARCH), `hmmlearn` (para cadeias de Markov), `pandas`, `scikit-learn`, `selenium` (para web scraping da ANBIMA), entre outras, além de registrar o comando CLI `credit-risk-engine`.

---

## Como Executar o Projeto (Workflow Completo)

O pipeline do projeto foi desenhado para ser rodado em etapas lógicas, partindo do dado bruto até a validação financeira executiva.

### Passo 1: Coleta e Ingestão de Dados
Realiza o download do histórico de negociação secundária da ANBIMA, extrai dados macroeconômicos do SGS/BCB e unifica as bases cruzando-as com os cadastros das emissões.
```bash
python src/credit_tail_analytics/data/run_scraper_full.py
```
*(Requer a instalação do Google Chrome localmente para execução do processo automatizado via Selenium).*

### Passo 2: Seleção de Features (Opcional)
Executa um algoritmo de *Grid Search* combinatório projetado para identificar a combinação sub-ótima de features (maximizando Silhouette e minimizando Davies-Bouldin e Contagion Variance) a ser ingerida pelos modelos não-supervisionados.
```bash
python src/credit_tail_analytics/models/credit_risk/feature_selection.py
```

### Passo 3: Torneio GARCH (Validação Econométrica)
Avalia diversas especificações GARCH/EGARCH adotando distribuições Normais e t-Student. O algoritmo seleciona a especificação ótima baseada na minimização dos Critérios de Informação (AIC/BIC) intra-amostra, fundamentando empiricamente a utilização do modelo EGARCH-t.
```bash
python src/credit_tail_analytics/analysis/selecao_modelos.py
```

### Passo 4: Motor de Risco Principal (Interface CLI)
Executa o fluxo de modelagem ponta a ponta: carrega os dados em memória, realiza a extração condicional de VaR/Volatilidade, aplica os classificadores de regime intra-indexador (K-Means e HMM) e exporta a malha de resultados estruturada.

Você pode usar o comando CLI direto no terminal:
```bash
credit-risk-engine --model_type both
```
Opções disponíveis:
- `--features`: Ex: `--features Taxa_ZScore Volatilidade_EGARCH Spread_Equivalente`
- `--no_liquidity_filter`: Desliga o expurgo de dias ilíquidos (Faixa 3 ANBIMA).
- `--help`: Lista todos os comandos.

### Passo 5: Validação Executiva e Backtest Financeiro
Módulo analítico desenhado para a defesa da tese. Consome a matriz de resultados do modelo principal e gera as provas empíricas:
1. **Matrizes de Transição**: Evidenciação matemática da propriedade de inércia do HMM vis-à-vis o ruído inerente aos clusters do K-Means.
2. **Backtest de Portfólio (PnL)**: Simula curvas de patrimônio sob a premissa de desinvestimento (Stop Loss) orientado pelos alertas de regime.
3. **Early Warning Score**: Tabela de eficiência temporal avaliando a antecedência (Lead Time) dos alertas disparados antes de eventos de default conhecidos.
```bash
python src/credit_tail_analytics/analysis/backtest_financeiro.py
```

### Passo 6: Visualizações Analíticas e Estudo de Caso
Gera os relatórios visuais (Dispersão Cross-Sectional, Séries Temporais Estendidas e Dinâmica de Contágio) contendo anotações dos *Ground Truths* de crédito sistêmicos estudados no escopo.
```bash
python src/credit_tail_analytics/visualization/frequentist_defense_visuals.py
```

*(Todos os resultados, planilhas e gráficos serão salvos automaticamente nas pastas `dados/` e `graficos/` na raiz do projeto).*

---

## Notas sobre o Rigor Metodológico
- **Cross-Sectional Mapping**: A modelagem de regimes é feita **por indexador** (CDI+, %CDI, IPCA), eliminando o viés de nível nominal e mantendo a comparabilidade do prêmio de risco.
- **Fat Tails**: A premissa de normalidade para spreads de crédito em mercados emergentes foi relaxada através da distribuição condicional *t-Student* para capturar caudas grossas.
- **Markov Assumption**: O HMM resolve a deficiência de independência temporal (IID) inerente aos clusterizadores clássicos, fornecendo um *smoothing* das transições de risco.
