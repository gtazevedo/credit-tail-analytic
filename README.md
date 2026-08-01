# Credit Tail Analytics (Early Warning System)

> ⚠️ **Aviso:** Este projeto encontra-se em fase de desenvolvimento ativo. A arquitetura, as metodologias quantitativas e as APIs podem sofrer alterações.

**Um motor quantitativo End-to-End para modelagem de risco de cauda e identificação de regimes de crédito (Credit Regime Switching) no mercado secundário de debêntures brasileiro.**

Este projeto foi desenvolvido como um Trabalho de Conclusão de Curso (TCC) em finanças quantitativas/ciência de dados. A tese central é que modelos estocásticos de transição de estados com memória temporal (como **Hidden Markov Models - HMM**) combinados com extração de volatilidade assimétrica (**EGARCH-t**) oferecem uma proteção de capital superior e sinalização antecipada de crises (Tail Risk) quando comparados a algoritmos clássicos de clusterização atemporal (como K-Means).

---

## Estrutura do Pacote e Mini-Documentação do Código

O projeto é um pacote Python modular estruturado da seguinte forma:

```text
src/credit_tail_analytics/
│
├── data/                  # Ingestão e cruzamento de dados brutos
│   ├── anbima_scraper.py  # Web Scraping das debêntures (Selenium)
│   ├── download_macro.py  # Extração de dados macro (python-bcb)
│   ├── build_cadastro.py  # Dados mestres via debentures_dot_com
│   ├── unify_csvs.py      # Cruzamento diário de atributos
│   └── run_scraper_full.py# Orquestrador de toda a rotina de dados
│
├── models/
│   ├── credit_risk/       # Motor Central de Risco (Risk Pipeline)
│   │   ├── preprocessor.py        # Limpeza, Normalização, Filtro Transversal de Liquidez
│   │   ├── volatility.py          # Implementação do EGARCH-t e Kupiec Test
│   │   ├── feature_selection.py   # Otimização Combinatória Borda Count (Grid Search)
│   │   ├── regime.py              # Classificação Latente (K-Means e Gaussian HMM)
│   │   ├── risk_pipeline.py       # Fachada integrando preprocessor, volatility e regime
│   │   └── run_frequentist_engine.py # Entry-point e interface CLI principal
│   └── clustering/        # Algoritmos abstratos de aprendizado de máquina
│
├── analysis/              # Validação de Performance e Testes Estatísticos
│   ├── selecao_modelos.py       # Torneio de Critérios de Informação (AIC/BIC)
│   ├── kupiec_validation.py     # Validação de aderência da cauda
│   └── backtest_financeiro.py   # Motor de simulação de carteira e PnL tático
│
├── visualization/         # Geração dos Painéis de Defesa Acadêmica
│   ├── frequentist_defense_visuals.py # Gráficos de Casos Empíricos (GPA, Light)
│   └── kupiec_visuals.py              # Matrizes de Aceitação/Rejeição do VaR
│
└── utils.py               # Auxiliares e gerenciadores de Path
```

---

## Como Executar o Pipeline (Etapa por Etapa)

O pipeline do projeto foi desenhado para ser rodado em sequência, partindo da ingestão do dado bruto até a validação financeira e a geração de gráficos. Recomenda-se rodar em ambiente virtual (`venv`).

### Passo 0: Instalação
Na raiz do projeto, instale o pacote em modo editável:
```bash
pip install -e .
```
Isso instalará dependências complexas como `arch` (EGARCH), `hmmlearn`, `python-bcb` e `selenium`.

### Passo 1: Coleta e Ingestão de Dados
Baixa o histórico do mercado secundário, extrai dados macro (CDI, IPCA) e consolida a base de trabalho no arquivo `dados/debentures_historico_bruto.csv`.
```bash
python src/credit_tail_analytics/data/run_scraper_full.py
```
*Detalhe Técnico:* O orquestrador aciona o `AnbimaScraper` iterativamente. Requer o Google Chrome instalado localmente para emular as sessões de download da B3/ANBIMA.

### Passo 2: Torneio GARCH (Opcional - Validação Acadêmica)
Roda um *Grid Search* de modelos heterocedásticos para comprovar matematicamente que a distribuição t-Student com *leverage effect* (EGARCH-t) é o ajuste ideal para as debêntures ilíquidas.
```bash
python src/credit_tail_analytics/analysis/selecao_modelos.py
```

### Passo 3: Motor de Risco Principal (Risk Engine)
Esta é a etapa mais pesada (pode levar horas dependendo do hardware). O `risk_pipeline.py` orquestra:
1. **Preprocessor**: Extrai deltas de spread e bane transversalmente ativos que passaram >= 95% do In-Sample na Faixa 3 de liquidez (para evitar buracos e falsos fundos de marcação). Remove erros conhecidos (ex: RDVT11).
2. **Volatility**: Roda o modelo EGARCH-t iterativamente, capturando o $VaR_{99}$ e o *Expected Shortfall*.
3. **Regime Classifier**: Treina HMM e K-Means para agrupamentos por Indexador.

```bash
python src/credit_tail_analytics/models/credit_risk/run_frequentist_engine.py
```
> O arquivo consolidado será salvo em `dados/resultado_frequentist_engine.csv`.

### Passo 4: Validação do Value at Risk (Kupiec Test)
Avalia se os choques estimados pelo EGARCH superestimaram ou subestimaram a cauda empírica dos ativos por meio do teste de proporção de falhas (POF) de Kupiec.
```bash
python src/credit_tail_analytics/analysis/kupiec_validation.py
python src/credit_tail_analytics/visualization/kupiec_visuals.py
```

### Passo 5: Backtest Financeiro e Simulação de Carteira
Consome a saída do Passo 3 e executa um motor de simulação tática. O caixa ocioso é remunerado ao CDI histórico real (extraído via BCB). Sempre que um ativo cai para o regime "Vermelho", o modelo processa um *Stop Loss* (venda) e entra em período de quarentena.
```bash
python src/credit_tail_analytics/analysis/backtest_financeiro.py
```
*O que faz?* Exporta matrizes de transição probabilísticas (mostrando a estabilidade do HMM) e avalia o PnL entre o K-Means e o HMM.

### Passo 6: Visualizações e Estudo de Casos (GPA, Casas Bahia, Light)
Por fim, esta rotina consome as predições estocásticas e traça a "autópsia" de ativos que sofreram colapso de crédito, evidenciando como a inércia markoviana (*Laplace Smoothing*) antecipou a migração de regimes.
```bash
python src/credit_tail_analytics/visualization/frequentist_defense_visuals.py
```
*Nota:* A rotina apaga automaticamente gráficos antigos da pasta `graficos/` antes de salvar os novos estudos de caso.

---

## Notas Metodológicas Críticas
- **Banimento Transversal:** O `preprocessor.py` não apaga "dias" individuais com baixa liquidez, pois isso quebra a continuidade autoregressiva e destrói o VaR. Em vez disso, bane o **Ticker inteiro** se ele falha nas regras durante o período In-Sample.
- **Cross-Sectional Mapping:** A modelagem espacial do HMM e K-Means é segmentada rigorosamente **por indexador** (CDI+, %CDI, IPCA), eliminando o viés do nível base do papel e permitindo comparar prêmios de risco reais intra-grupo.
- **Laplace Prior:** A inclusão artificial de uma matriz mínima de transição no modelo Bayesiano destranca os estados (previne a matriz de transição de se tornar puramente diagonal durante a amostra de treinamento estressada).
