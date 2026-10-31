= Automatização do Pipeline de Dados <sec_pipeline_automacao>

Para assegurar que a coleta de dados, a estimação econométrica e as simulações de carteira sigam um fluxo padronizado, o projeto foi estruturado com práticas de DataOps e MLOps.

== Definição da Ferramenta de Orquestração de Pipeline do Fluxo de Trabalho <sec_ferramenta_pipeline>

A automação baseia-se no pacote modular `credit_tail_analytics`, gerenciado via `Poetry`. A estrutura garante a reprodutibilidade dos resultados por meio de versões fixas de pacotes e sementes pseudoaleatórias, 
viabilizando a execução local sem dependência de serviços em nuvem e permitindo acoplamento futuro com Airflow ou MLflow.

== Modelo do Fluxo de Trabalho <sec_modelo_fluxo>

O fluxo de atividades compreende etapas sequenciais integradas, desde a ingestão até a auditoria financeira (@fig_pipeline_fluxo).

#import "@preview/diagraph:0.3.2": raw-render

#figure(
  pad(bottom: 0.2em,
    raw-render(
```dot
digraph G {
    rankdir=TB;
    nodesep=0.20;
    ranksep=0.20;
    compound=true;
    newrank=true;
    
    // Configurações globais
    node [
        fontname="Arial",
        fontsize=7.5,
        shape=box,
        style="rounded,filled",
        color="#94a3b8",
        penwidth=0.7,
        margin="0.08,0.05"
    ];
    edge [
        fontname="Arial",
        fontsize=6.8,
        color="#475569",
        arrowsize=0.6,
        penwidth=0.7
    ];

    // Bloco 1: Ingestão e Pré-Processamento
    subgraph cluster_0 {
        label="1. Ingestão, Saneamento & Filtro de Volatilidade (DataOps)";
        fontsize=8;
        fontname="Arial";
        color="#cbd5e1";
        style="rounded,dashed";
        bgcolor="#f8fafc";
        
        {
            rank=same;
            anbima [label="ANBIMA REUNE\nNegócios secundários (PU, taxa, volume)\nFiltro de liquidez (exclusão Faixa 3)", fillcolor="#eef2ff"];
            bacen [label="BACEN (SGS)\nSéries macro diárias\nCDI, Selic e IPCA", fillcolor="#eef2ff"];
        }
        
        features [
            label="Engenharia de Atributos & Padronização\n• Spread equivalente e ajuste por prazo útil: S_t / ln(DU)\n• Z-Score causal móvel (60d) e Winsorização bilateral (1% / 99%)",
            fillcolor="#ffffff"
        ];
        
        egarch [
            label="Motor Econométrico AR(1)-EGARCH(1,1)-t\nVolatilidade condicional σ_t, resíduos z_t e cauda analítica (VaR/ES 99%)\nTrava de variância máxima e piso de graus de liberdade (ν ≥ 2,05)",
            fillcolor="#f1f5f9"
        ];

        anbima -> features;
        bacen -> features;
        features -> egarch [label=" Séries higienizadas"];
    }

    // Bloco 2: Modelagem de Regimes e Ensemble
    subgraph cluster_1 {
        label="2. Modelagem de Regimes & Ponderação Ensemble (MLOps)";
        fontsize=8;
        fontname="Arial";
        color="#cbd5e1";
        style="rounded,dashed";
        bgcolor="#fffbeb";
        
        {
            rank=same;
            kmeans [
                label="K-Means (k=3)\nLinha de base estática (atemporal)\nCentróides ordenados por risco\n(Verde, Amarelo, Vermelho)",
                fillcolor="#fef3c7"
            ];
            hmm [
                label="Gaussian HMM (k=3)\nDependência temporal estocástica\nMatriz 3x3 c/ regularização Laplace\nProbabilidade latente de crise",
                fillcolor="#fef3c7"
            ];
        }
        
        ensemble [
            label="Ensemble Ponderado & Suavização Temporal\nScore = 0,70 × Prob_Crise_HMM + 0,30 × Prob_Crise_KMeans\nSuavização exponencial móvel (EMA span=21d) contra ruído de mercado",
            fillcolor="#e0e7ff"
        ];

        kmeans -> ensemble [label=" Score KM"];
        hmm -> ensemble [label=" Prob HMM"];
    }

    // Conexão inter-clusters
    egarch -> kmeans [label=" Treino IS (2018-2022)"];
    egarch -> hmm [label=" Inferência OOS (2023-2026)"];

    // Bloco 3: Backtest e Validação
    subgraph cluster_2 {
        label="3. Simulação Tática, Backtest Financeiro & Auditoria Estatística";
        fontsize=8;
        fontname="Arial";
        color="#cbd5e1";
        style="rounded,dashed";
        bgcolor="#f0fdf4";
        
        backtest [
            label="Simulador Tático de Carteira (Backtest Out-of-Sample)\n• Regras operacionais de desinvestimento (Vende Amarelo / Vende Vermelho)\n• Fricção transacional realista de 50 bps e quarentena de 180 dias úteis",
            fillcolor="#dcfce7"
        ];
        
        auditoria [
            label="Auditoria & Validação de Significância Estatística\n• 10.000 iterações de Block Bootstrap estacionário (teste de alfa vs Buy-and-Hold)\n• Métricas de desempenho: Calmar Ratio, Drawdown e Lead Time de Alerta",
            fillcolor="#bbf7d0"
        ];

        ensemble -> backtest [label=" Sinais diários"];
        backtest -> auditoria [label=" Curvas de PnL"];
    }
}
```
    )
  ),
  caption: [Diagrama do Fluxo de Atividades do Pipeline de Risco e Backtest.]
) <fig_pipeline_fluxo>

O processamento divide-se em três módulos sequenciais: ingestão e estimação do EGARCH-t com dados ANBIMA e BACEN; calibração dos modelos K-Means e HMM com cômputo da pontuação do ensemble; e execução do backtest financeiro com validação por Block Bootstrap (10.000 iterações).

== Códigos/telas <sec_codigos_telas>

A estrutura é modularizada em `data/` (coleta e cadastro), `models/` (volatilidade e regimes), `analysis/` (backtest e bootstrap) e `visualization/` (relatórios diagnósticos). 
Toda a implementação se encontra em código aberto no link #link("https://github.com/gtazevedo/credit-tail-analytic")[https://github.com/gtazevedo/credit-tail-analytic].

A classe `CreditRiskEngine` (`risk_pipeline.py`) orquestra as etapas de modelagem e consolidação:

```python
df_vol = VolatilityEstimator().build_volatility_features(df_clean, split_date)
df_res = pd.merge(RegimeClassifier().run_kmeans_regimes(df_vol, split_date, features),
                  RegimeClassifier().run_hmm_regimes(df_vol, split_date, features), on=['Ticker', 'Data', 'Indexador_Grupo'])
score = (0.70 * df_res['Prob_Crise_HMM'].fillna(0) + 0.30 * df_res['Prob_Crise_KMeans'].fillna(0)) * 100
df_res['Credit_Tail_Risk_Score'] = score.groupby(df_res['Ticker']).transform(lambda x: x.ewm(span=21).mean())
```

A execução no terminal confirma a aderência das fases:

```text
[INFO] EGARCH(1,1)-t: 100% convergência (LB: 86.4%, ARCH: 94.9%) | Ensemble ótimo (w_HMM=0.70, Calmar=1.603)
[INFO] Out-of-Sample: KM Vende Amarelo Retorno=36.18% vs B&H=22.42% | Block Bootstrap p=0.0416 (p<0.05)
```
