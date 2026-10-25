= Automatização do Pipeline de Dados <sec_pipeline_automacao>

A operacionalização de modelos preditivos no mercado de capitais requer processos automatizados, auditáveis e reproduzíveis. A arquitetura computacional do projeto foi desenhada sob os princípios de DataOps e MLOps, priorizando modularidade e rastreabilidade,
garantindo o controle de versões dos dados e código, além da execução em múltiplos ambientes operacionais.

== Definição da Ferramenta de Orquestração de Pipeline do Fluxo de Trabalho <sec_ferramenta_pipeline>

A automação do fluxo de trabalho baseia-se em uma arquitetura modular em Python, estruturada na forma de pacote instalável independente denominado `credit_tail_analytics`. O gerenciamento de dependências e ambientes virtuais utiliza o `Poetry`, 
atendendo a três requisitos práticos. Primeiramente, elimina a dependência de servidores proprietários ou serviços em nuvem, viabilizando a execução local. Em segundo lugar, garante reprodutibilidade estrita pelo controle
de versionamento de pacotes, sementes pseudoaleatórias e dependências matemáticas. Por fim, viabiliza o acoplamento futuro com ferramentas de orquestração distribuída (como Airflow ou MLflow), caso a escala demande processamento em tempo real
ou em tempo quase real (_near real-time_).


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

O fluxo delineado na @fig_pipeline_fluxo opera de forma integrada e sequencial ao longo de seis fases computacionais interligadas. Inicialmente, no estágio de ingestão e saneamento, realizam-se a extração e a harmonização dos arquivos transacionais brutos da ANBIMA e 
das séries macroeconômicas do BACEN, etapa em que os códigos identificadores são padronizados e os títulos sem liquidez de negociação são removidos da amostra. Em seguida, a camada de estimação econométrica processa as séries temporais de retornos por meio do modelo 
EGARCH-$t$, derivando a variância condicional instantânea, os resíduos padronizados e as métricas paramétricas de cauda — notadamente o _Value-at-Risk_ (VaR) e o _Expected Shortfall_ (ES).

A partir desses insumos, o pipeline avança para a calibração amostral (_in-sample_), na qual os dados de treino orientam a convergência dos centróides do K-Means e o aprendizado das probabilidades de transição do HMM, balizando a ponderação conjunta da arquitetura em 
ensemble. Durante a inferência fora da amostra (_out-of-sample_), o sistema computa de modo causal as probabilidades diárias de estresse financeiro, assegurando a ausência de vazamento de informações futuras. Por fim, o motor de simulação tática (_backtest_) traduz 
tais probabilidades em decisões de liquidação e recompra de ativos sob atrito de custos operacionais, submetendo o retorno patrimonial resultante a uma auditoria estatística rigorosa fundamentada em 10.000 repetições de _Block Bootstrap_ para averiguar a significância 
do alfa gerado perante o referencial passivo.

== Códigos/telas <sec_codigos_telas>

A estrutura do projeto adota uma arquitetura modularizada, encapsulada no diretório raiz do pacote `src/credit_tail_analytics/`. Os procedimentos de coleta e pré-processamento encontram-se centralizados no módulo `data/`, abrigando os scripts de raspagem dos 
informes da ANBIMA (`anbima_scraper.py`), a consolidação da base cadastral de debêntures (`build_cadastro.py`) e a extração automatizada de séries macroeconômicas via API do Banco Central (`download_macro.py`). A lógica quantitativa é distribuída entre o pacote 
`models/`, responsável pelo filtro de volatilidade condicional assimétrica (`credit_risk/`) e pela detecção não supervisionada de regimes (`clustering/`), e o módulo `analysis/`, que implementa o simulador contábil de _backtest_ e a rotina de reamostragem em blocos. 
O suporte visual e a geração dos relatórios diagnósticos do estudo são providos pelas rotinas do diretório `visualization/`.

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
[INFO] K-Means Vende Amarelo: Retorno=36.18% | Buy and Hold=22.42% | Delta=+13.76%
[INFO] Rodando Block Bootstrap (n=10.000 repetições, bloco=20 dias)... p-valor = 0.0416 (p < 0.05).
[INFO] Pipeline finalizado com sucesso. Artefatos gravados em anexos_digitais/ e graficos/.
```
