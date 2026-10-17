= Automatização do Pipeline de Dados <sec_pipeline_automacao>

A operacionalização de modelos preditivos no mercado de capitais requer processos automatizados, auditáveis e reproduzíveis. A arquitetura computacional do projeto foi desenhada sob os princípios de DataOps e MLOps, garantindo a rastreabilidade integral dos dados, o versionamento de modelos e a independência de execução em múltiplos ambientes operacionais.

== Definição da Ferramenta de Orquestração de Pipeline do Fluxo de Trabalho <sec_ferramenta_pipeline>

A automação do fluxo de trabalho baseia-se em uma arquitetura modular em Python, estruturada na forma de pacote instalável independente denominado `credit_tail_analytics`. O gerenciamento de dependências e ambientes virtuais utiliza o `Poetry`, que assegura o bloqueio determinístico das versões das bibliotecas matemáticas (`arch`, `scikit-learn`, `hmmlearn`, `pandas`, `scipy`).

A escolha por uma arquitetura nativa em Python orquestrada por scripts modulares justifica-se por três fatores:

1. *Autonomia Operacional:* Dispensa a dependência de servidores complexos de terceiros ou infraestruturas pagas em nuvem, permitindo a execução integral do pipeline em qualquer servidor local ou máquina de análise de risco;
2. *Reprodutibilidade Estrita:* Cada etapa do fluxo consome entradas versionadas e produz saídas determinísticas, controlando sementes pseudoaleatórias (*random seeds*);
3. *Flexibilidade de Integração:* A estrutura modular facilita o acoplamento futuro com ferramentas como Airflow ou MLflow, caso o volume diário de debêntures exija orquestração distribuída em tempo real.

== Modelo do Fluxo de Trabalho <sec_modelo_fluxo>

O fluxo de atividades compreende etapas sequenciais que cobrem desde a ingestão dos dados brutos até a emissão de relatórios de desempenho financeiro. A @fig_pipeline_fluxo ilustra o diagrama de blocos do processo ponta a ponta.

#import "@preview/diagraph:0.3.2": raw-render

#figure(
  pad(bottom: 1em,
    raw-render(
```dot
digraph G {
    rankdir=TB;
    node [shape=box, style=rounded, fontname="Arial", fontsize=10];
    edge [fontsize=9, fontname="Arial"];
    
    anbima [label="Dados ANBIMA\n(REUNE)", fillcolor="#eef2ff", style="rounded,filled"];
    macro [label="Dados Macro\n(BACEN SGS)", fillcolor="#eef2ff", style="rounded,filled"];
    pre [label="Pré-Processamento\n& Filtro de Liquidez", fillcolor="#f1f5f9", style="rounded,filled"];
    egarch [label="Motor EGARCH-t\n(Filtro de Volatilidade)", fillcolor="#f1f5f9", style="rounded,filled"];
    
    is [label="Amostra In-Sample\n(2018 - 2022)"];
    oos [label="Amostra Out-of-Sample\n(2023 - 2026)"];
    
    kmeans_train [label="Treino K-Means\n(Validação k=3)", fillcolor="#fef3c7", style="rounded,filled"];
    hmm_train [label="Treino HMM\n(Gaussiano com Laplace)", fillcolor="#fef3c7", style="rounded,filled"];
    grid [label="Grid-Search Ensemble\n(Otimização de Pesos)", fillcolor="#fef3c7", style="rounded,filled"];
    
    kmeans_pred [label="Predição K-Means"];
    hmm_pred [label="Predição HMM"];
    ensemble [label="Ensemble Misto\n(70% HMM / 30% KMeans)", fillcolor="#e0e7ff", style="rounded,filled"];
    
    backtest [label="Simulador de Backtest\n(Custos de 50 bps)", fillcolor="#dcfce7", style="rounded,filled"];
    resultado [label="Métricas & Block Bootstrap\n(Validação vs Buy and Hold)", shape=doubleoctagon, fillcolor="#bbf7d0", style="filled"];

    anbima -> pre;
    macro -> pre;
    pre -> egarch [label=" Séries Saneadas"];
    
    egarch -> is;
    egarch -> oos;
    
    is -> kmeans_train;
    is -> hmm_train;
    
    kmeans_train -> grid [label=" Scores IS"];
    hmm_train -> grid [label=" Probs IS"];
    
    oos -> kmeans_pred;
    oos -> hmm_pred;
    
    kmeans_train -> kmeans_pred [label=" Centróides", style=dashed];
    hmm_train -> hmm_pred [label=" Matrizes", style=dashed];
    
    grid -> ensemble [label=" Pesos Ótimos"];
    kmeans_pred -> ensemble;
    hmm_pred -> ensemble;
    
    ensemble -> backtest;
    backtest -> resultado;
}
```
    )
  ),
  caption: [Diagrama do Fluxo de Atividades do Pipeline de Risco e Backtest.]
) <fig_pipeline_fluxo>

As etapas do pipeline desempenham funções específicas dentro do ecossistema:

1. *Ingestão e Saneamento:* Coleta os arquivos brutos da ANBIMA e do BACEN, higieniza identificadores e remove registros com iliquidez severa;
2. *Estimação Econométrica:* O motor EGARCH-t processa as séries de retornos e extrai a volatilidade condicional, os resíduos padronizados e as métricas de VaR e Expected Shortfall;
3. *Calibração In-Sample:* Os dados de treinamento ajustam os centróides do K-Means e as matrizes de transição do HMM, definindo os pesos ideais do Ensemble;
4. *Inferência Out-of-Sample:* Gera probabilidades diárias causais de estresse financeiro sem vazamento de informação futura;
5. *Simulação Tática (Backtest):* Aplica regras operacionais de liquidação e recompra sobre os ativos, registrando as variações patrimoniais da carteira;
6. *Auditoria Estatística:* Executa 10.000 repetições de *Block Bootstrap* para atestar a significância estatística do retorno excedente frente ao mercado passivo.

== Códigos/telas <sec_codigos_telas>

A base de código está organizada em pacotes modulares no diretório `src/credit_tail_analytics/`, dividida nas seguintes pastas especializadas:

- `data/`: Rotinas de raspagem (`anbima_scraper.py`), tratamento cadastral (`build_cadastro.py`) e download macroeconômico (`download_macro.py`);
- `models/`: Módulos de volatilidade condicional (`credit_risk/`) e algoritmos de agrupamento (`clustering/`);
- `analysis/`: Rotinas do simulador de backtest e reamostragem estatística via Bootstrap em bloco;
- `visualization/`: Geração automatizada de gráficos diagnósticos e relatórios.

O repositório oficial do projeto encontra-se disponível no GitHub:
#align(center)[#link("https://github.com/gtazevedo/credit-tail-analytic")[https://github.com/gtazevedo/credit-tail-analytic]]

A classe `CreditRiskEngine`, implementada em `src/credit_tail_analytics/models/credit_risk/risk_pipeline.py`, atua como orquestradora central das etapas de modelagem econométrica, inferência de regimes e consolidação do Ensemble:

```python
class CreditRiskEngine:
    """Orquestrador central do pipeline de modelagem e inferência de regimes."""

    def __init__(self, df: pd.DataFrame, features: list = None, filter_low_liquidity: bool = True, split_date: str = '2023-01-01'):
        self.features = features or ['Taxa_ZScore', 'Volatilidade_EGARCH', 'Expected_Shortfall_99']
        self.split_date = split_date
        self.preprocessor = DataPreprocessor(filter_low_liquidity=filter_low_liquidity, split_date=split_date)
        self.volatility_estimator = VolatilityEstimator()
        self.regime_classifier = RegimeClassifier(individual_scaling=True)
        self.df = self.preprocessor.process(df)

    def execute_pipeline(self, model_type: str = 'both') -> tuple[pd.DataFrame, pd.DataFrame]:
        # 1. Estimação de volatilidade condicional e medidas de cauda
        self.df = self.volatility_estimator.build_volatility_features(self.df, self.split_date)

        # 2. Inferência de regimes por K-Means e Gaussian HMM
        df_k = self.regime_classifier.run_kmeans_regimes(self.df, self.split_date, self.features)
        df_h = self.regime_classifier.run_hmm_regimes(self.df, self.split_date, self.features)
        
        # 3. Consolidação e ponderação ótima do Ensemble (70% HMM e 30% K-Means)
        df_res = pd.merge(df_k, df_h, on=['Ticker', 'Data', 'Indexador_Grupo'], how='outer')
        w_hmm, w_km = 0.70, 0.30
        score_bruto = (w_hmm * df_res['Prob_Crise_HMM'].fillna(0) + w_km * df_res['Prob_Crise_KMeans'].fillna(0)) * 100

        # Suavização por média móvel exponencial de 21 dias para mitigação de ruído
        df_res['Credit_Tail_Risk_Score'] = (
            score_bruto.groupby(df_res['Ticker']).transform(lambda x: x.ewm(span=21, adjust=False).mean())
        )
        return self.df, df_res
```

A execução do pipeline completo opera via terminal, apresentando logs detalhados em cada fase do processamento:

```text
[INFO] Iniciando pipeline de risco de crédito: credit_tail_analytics v1.0.0
[INFO] Carregando dados transacionais ANBIMA REUNE (2018 - 2026)... 529 ativos elegíveis.
[INFO] Ajustando modelos EGARCH(1,1)-t: convergência em 529/529 ativos (100%).
[INFO] Ljung-Box (Lag 10): 86.4% aprovação | ARCH-LM (Lag 10): 94.9% aprovação.
[INFO] Treinando K-Means (k=3 regimes) e Gaussian HMM (Laplace alpha=1.0)...
[INFO] Grid-Search Ensemble concluído: peso ótimo w_HMM=0.70, w_KMeans=0.30 (Calmar=-0.017).
[INFO] Executando Backtest Out-of-Sample (50 bps custo, 180d quarentena, 15d inércia)...
[INFO] K-Means Vende Amarelo: Retorno=36.18% | Buy and Hold=32.84% | Delta=+3.34%
[INFO] Rodando Block Bootstrap (n=10.000 repetições, bloco=20 dias)... p-valor = 0.0416 (p < 0.05).
[INFO] Pipeline finalizado com sucesso. Artefatos gravados em anexos_digitais/ e graficos/.
```
