"""
frequentist_defense_visuals.py
================================
Módulo de Visualização Analítica e Diagnóstico de Modelos de Regime de Crédito.

Gera as evidências empíricas necessárias para a defesa acadêmica e validação executiva 
da tese de que modelos markovianos (HMM) oferecem superioridade na identificação 
de regimes de risco de cauda quando comparados a baselines atemporais (K-Means).

As visualizações cobrem quatro dimensões de validação:
1. Mapeamento Cross-Sectional (Dispersão Risco vs Retorno).
2. Estabilidade Temporal Longitudinal (Séries Temporais de Spread).
3. Dinâmica de Contágio Sistêmico (Proporção agregada de High Risk).
4. Ground Truth de Eventos de Crédito (Estudo de Caso de defaults e fraudes contábeis).

Nota: Todas as projeções são estritamente condicionadas ao Indexador_Grupo para evitar 
viés de nível nominal (Nominal Rate Bias) na mensuração do prêmio de risco.
"""
import os
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.dates as mdates
import matplotlib.patches as mpatches
import seaborn as sns
import logging
from typing import List, Dict, Optional, Tuple

logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')
logger = logging.getLogger('FrequentistDefense')

# ---------------------------------------------------------------------------
# Paletas e mapeamentos
# ---------------------------------------------------------------------------
CLUSTER_PALETTE = {
    'Verde':         '#2ecc71',
    'Amarelo':       '#f1c40f',
    'Vermelho':      '#e74c3c',
    'Inconclusivo':  '#95a5a6',
}
CLUSTER_ORDER   = ['Verde', 'Amarelo', 'Vermelho']
CLUSTER_NUMERIC = {'Verde': 1, 'Amarelo': 2, 'Vermelho': 3, 'Inconclusivo': 0}

MODEL_COLORS = {
    'K-Means': '#3498db',
    'HMM':     '#9b59b6',
}

# ---------------------------------------------------------------------------
# Eventos de crédito conhecidos (ground truth narrativo)
# ---------------------------------------------------------------------------
EVENTOS_CREDITO: Dict[str, List] = {}

def _load_eventos():
    from credit_tail_analytics.utils import dados_dir
    csv_path = dados_dir() / 'estudos_caso.csv'
    if os.path.exists(csv_path):
        estudos = pd.read_csv(csv_path)
        for _, row in estudos.iterrows():
            empresa = row['Empresa']
            data_ev = row['Data do Evento']
            # Converter data 'jan./2023' para '2023-01-01' se possível, senao deixa o texto
            # Mas _add_event_lines tenta fazer pd.to_datetime(data_str).
            # Vamos tratar 'jan./2023' manualmente:
            meses = {'jan.': '01', 'fev.': '02', 'mar.': '03', 'abr.': '04', 'mai.': '05', 'jun.': '06', 
                     'jul.': '07', 'ago.': '08', 'set.': '09', 'out.': '10', 'nov.': '11', 'dez.': '12'}
            dt_str = str(data_ev).lower()
            for m, num in meses.items():
                if dt_str.startswith(m):
                    parts = dt_str.replace(' ', '').split('/')
                    if len(parts) == 2:
                        dt_str = f"{parts[1]}-{num}-01"
                        break
            if '202' not in dt_str:
                dt_str = '2023-06-01' # fallback
            else:
                if '/' in dt_str and len(dt_str) > 10:
                    dt_str = dt_str.split('/')[0].strip()
                    if len(dt_str) == 4:
                        dt_str = f"{dt_str}-06-01"
            
            try:
                pd.to_datetime(dt_str)
            except:
                dt_str = '2023-06-01'
            
            label = str(row['Tipo de Evento']).replace(' ', '\n')
            if empresa not in EVENTOS_CREDITO:
                EVENTOS_CREDITO[empresa] = []
            EVENTOS_CREDITO[empresa].append((dt_str, label))

_load_eventos()


# ---------------------------------------------------------------------------
# Helpers internos
# ---------------------------------------------------------------------------

def _add_split_line(ax, split_date: str, label: bool = True):
    """Adiciona linha vertical de início Out-of-Sample."""
    split_dt = pd.to_datetime(split_date)
    ax.axvline(split_dt, color='black', linestyle='--', linewidth=1.8, alpha=0.8,
               label='Início Out-of-Sample' if label else None)


def _add_event_lines(axes_list, eventos: Optional[List], colors=None):
    """Adiciona linhas verticais de eventos de crédito em todos os eixos."""
    if not eventos:
        return
    EVENT_COLORS = colors or ['#8e44ad', '#d35400', '#16a085', '#2980b9', '#c0392b']
    for i, (data_str, label) in enumerate(eventos):
        ev_dt    = pd.to_datetime(data_str)
        ev_color = EVENT_COLORS[i % len(EVENT_COLORS)]
        for ax in axes_list:
            ax.axvline(ev_dt, color=ev_color, linestyle=':', linewidth=1.5, alpha=0.9)
        if axes_list:
            axes_list[0].axvline(
                ev_dt, color=ev_color, linestyle=':', linewidth=1.5,
                label=f"{label.replace(chr(10), ' ')} ({data_str[:7]})"
            )


def _get_grupos(df: pd.DataFrame) -> List[str]:
    """Retorna a lista de Indexador_Grupo presentes no DataFrame."""
    if 'Indexador_Grupo' in df.columns:
        return sorted(df['Indexador_Grupo'].dropna().unique().tolist())
    return ['_all']


def _safe_cluster_col(df: pd.DataFrame, preferred: str = 'Cluster_KMeans') -> str:
    """Retorna a coluna de cluster disponível no DataFrame."""
    for col in [preferred, 'Cluster_KMeans', 'Cluster_HMM', 'Cluster_Risco_KMeans',
                'Cluster_Risco_Mahalanobis']:
        if col in df.columns:
            return col
    return preferred   # deixa falhar com mensagem clara


# ===========================================================================
# 1. CROSS-SECTION — Scatter por Indexador_Grupo (última data OOS)
# ===========================================================================

def plot_cross_section(
    df: pd.DataFrame,
    out_dir: str,
    cluster_col: str = 'Cluster_KMeans',
    filename_prefix: str = '01',
):
    """
    Scatter plot (Taxa_ZScore × Volatilidade_EGARCH) da última data Out-of-Sample,
    um gráfico por Indexador_Grupo, colorido pelos clusters.
    """
    logger.info("Gerando Cross-Section por Indexador_Grupo...")
    cluster_col = _safe_cluster_col(df, cluster_col)

    ultima_data = df['Data'].max()
    df_ult = df[df['Data'] == ultima_data].copy()
    if df_ult.empty:
        return

    grupos = _get_grupos(df_ult)

    for grupo in grupos:
        g_df = df_ult[df_ult['Indexador_Grupo'] == grupo] if 'Indexador_Grupo' in df_ult.columns else df_ult
        if g_df.empty or len(g_df) < 3:
            continue

        fig, ax = plt.subplots(figsize=(10, 6))
        for cluster in CLUSTER_ORDER + ['Inconclusivo']:
            sub = g_df[g_df[cluster_col] == cluster]
            if sub.empty:
                continue
            ax.scatter(
                sub['Taxa_ZScore'], sub['Volatilidade_EGARCH'],
                c=CLUSTER_PALETTE.get(cluster, '#95a5a6'),
                label=cluster, s=70, edgecolors='k', linewidths=0.5, alpha=0.8
            )
            for _, row in sub[sub[cluster_col] == 'Vermelho'].iterrows():
                ax.annotate(
                    row.get('Ticker', ''),
                    (row['Taxa_ZScore'], row['Volatilidade_EGARCH']),
                    xytext=(5, 5), textcoords='offset points',
                    fontsize=8, color='darkred', fontweight='bold'
                )

        ax.set_title(
            f"Cross-Section de Risco — {grupo}\n"
            f"Última observação OOS: {ultima_data.date()}"
        )
        ax.set_xlabel("Z-Score do Spread (janela 60d)")
        ax.set_ylabel("Volatilidade EGARCH (%)")
        ax.legend(title='Cluster')
        ax.grid(True, linestyle='--', alpha=0.4)
        plt.tight_layout()

        fname = f"{filename_prefix}_cross_section_{grupo.lower().replace(' ', '_')}.png"
        plt.savefig(os.path.join(out_dir, fname), dpi=300)
        plt.close()
        logger.info(f"  → {fname}")


# ===========================================================================
# 2. CONTAGION — Evolução sistêmica dos regimes ao longo do tempo
# ===========================================================================

def plot_contagion(
    df: pd.DataFrame,
    out_dir: str,
    split_date: str,
    cluster_col: str = 'Cluster_KMeans',
    filename_prefix: str = '02',
):
    """
    Área empilhada da proporção de ativos em cada regime ao longo do tempo,
    segmentada por Indexador_Grupo.

    Parâmetros
    ----------
    cluster_col : str
        Coluna de cluster a usar ('Cluster_KMeans' ou 'Cluster_HMM').
    """
    logger.info(f"Gerando Contagion ({cluster_col}) por Indexador_Grupo...")
    cluster_col = _safe_cluster_col(df, cluster_col)
    grupos = _get_grupos(df)

    for grupo in grupos:
        g_df = df[df['Indexador_Grupo'] == grupo].copy() if 'Indexador_Grupo' in df.columns else df.copy()
        g_df = g_df.dropna(subset=[cluster_col, 'Data'])
        if g_df.empty:
            continue

        df_dist = (
            g_df.groupby(['Data', cluster_col])
            .size()
            .unstack(fill_value=0)
        )
        # Garante colunas na ordem certa
        for col in CLUSTER_ORDER:
            if col not in df_dist.columns:
                df_dist[col] = 0
        df_dist_pct = df_dist[CLUSTER_ORDER].div(df_dist[CLUSTER_ORDER].sum(axis=1), axis=0) * 100

        fig, ax = plt.subplots(figsize=(14, 5))
        ax.fill_between(df_dist_pct.index, 0,
                        df_dist_pct['Verde'],
                        color=CLUSTER_PALETTE['Verde'], alpha=0.7, label='Verde (Normal)')
        ax.fill_between(df_dist_pct.index,
                        df_dist_pct['Verde'],
                        df_dist_pct['Verde'] + df_dist_pct['Amarelo'],
                        color=CLUSTER_PALETTE['Amarelo'], alpha=0.7, label='Amarelo (Alerta)')
        ax.fill_between(df_dist_pct.index,
                        df_dist_pct['Verde'] + df_dist_pct['Amarelo'],
                        100,
                        color=CLUSTER_PALETTE['Vermelho'], alpha=0.7, label='Vermelho (Crise)')

        _add_split_line(ax, split_date, label=True)
        ax.set_title(
            f"Evolução Sistêmica dos Regimes — {grupo}\n"
            f"Modelo: {cluster_col.replace('Cluster_', '')}"
        )
        ax.set_xlabel("Data")
        ax.set_ylabel("% de Ativos no Mercado")
        ax.set_ylim(0, 100)
        ax.legend(loc='lower right')
        ax.margins(x=0)
        ax.grid(True, linestyle='--', alpha=0.3)
        plt.tight_layout()

        fname = (
            f"{filename_prefix}_contagion_{cluster_col.lower()}_"
            f"{grupo.lower().replace(' ', '_')}.png"
        )
        plt.savefig(os.path.join(out_dir, fname), dpi=300)
        plt.close()
        logger.info(f"  → {fname}")


# ===========================================================================
# 3. MODEL COMPARISON — K-Means vs HMM (proporção de Vermelho)
# ===========================================================================

def plot_model_comparison(
    df: pd.DataFrame,
    out_dir: str,
    split_date: str,
    filename_prefix: str = '03',
):
    """
    Painel duplo (K-Means vs HMM) da proporção de ativos "Vermelho" ao longo do
    tempo OOS, por Indexador_Grupo.

    Destaca em fundo laranja os momentos em que os modelos divergem, evidenciando
    a incapacidade do K-Means de capturar persistência temporal.
    """
    logger.info("Gerando comparação K-Means vs HMM por Indexador_Grupo...")

    has_kmeans = 'Cluster_KMeans' in df.columns
    has_hmm    = 'Cluster_HMM'    in df.columns

    if not has_kmeans and not has_hmm:
        logger.warning("[plot_model_comparison] Nenhuma coluna de cluster encontrada.")
        return

    split_dt = pd.to_datetime(split_date)
    df_oos   = df[df['Data'] >= split_dt].copy()
    grupos   = _get_grupos(df_oos)

    for grupo in grupos:
        g_df = df_oos[df_oos['Indexador_Grupo'] == grupo].copy() \
            if 'Indexador_Grupo' in df_oos.columns else df_oos.copy()
        if g_df.empty:
            continue

        fig, axes = plt.subplots(1, 2, figsize=(16, 5), sharey=True)
        fig.suptitle(
            f"K-Means vs HMM — Proporção de Ativos em Crise (Vermelho)\n"
            f"Grupo: {grupo} | Out-of-Sample",
            fontsize=13
        )

        for ax, (col, model_name) in zip(
            axes,
            [('Cluster_KMeans', 'K-Means (Baseline)'), ('Cluster_HMM', 'HMM (Proposto)')]
        ):
            if col not in g_df.columns:
                ax.set_title(f"{model_name}\n(não disponível)")
                ax.axis('off')
                continue

            ts = (
                g_df.groupby('Data')[col]
                .apply(lambda x: (x == 'Vermelho').mean() * 100)
            )
            ax.fill_between(ts.index, ts.values,
                            color=MODEL_COLORS.get(model_name.split()[0], '#555'),
                            alpha=0.4)
            ax.plot(ts.index, ts.values,
                    color=MODEL_COLORS.get(model_name.split()[0], '#555'), linewidth=1.8)
            ax.set_title(model_name, fontsize=11)
            ax.set_xlabel("Data")
            ax.set_ylabel("% Ativos em Vermelho")
            ax.set_ylim(0, 100)
            ax.grid(True, linestyle='--', alpha=0.4)
            ax.xaxis.set_major_formatter(mdates.DateFormatter('%Y-%m'))
            plt.setp(ax.xaxis.get_majorticklabels(), rotation=30, ha='right')

        # Região de divergência (apenas se ambos disponíveis)
        if has_kmeans and has_hmm:
            ts_k = (
                g_df.groupby('Data')['Cluster_KMeans']
                .apply(lambda x: (x == 'Vermelho').mean() * 100)
            )
            ts_h = (
                g_df.groupby('Data')['Cluster_HMM']
                .apply(lambda x: (x == 'Vermelho').mean() * 100)
            )
            common_idx = ts_k.index.intersection(ts_h.index)
            if len(common_idx) > 0:
                diverge = (ts_k.loc[common_idx] - ts_h.loc[common_idx]).abs() > 10
                for ax in axes:
                    ax.fill_between(
                        common_idx, 0, 100,
                        where=diverge.values,
                        color='orange', alpha=0.15, label='Divergência >10pp'
                    )
                    ax.legend(fontsize=8)

        plt.tight_layout()
        fname = f"{filename_prefix}_model_comparison_{grupo.lower().replace(' ', '_')}.png"
        plt.savefig(os.path.join(out_dir, fname), dpi=300)
        plt.close()
        logger.info(f"  → {fname}")


# ===========================================================================
# 4. HMM PROBABILITY — Probabilidade contínua de crise (Prob_Crise_HMM)
# ===========================================================================

def plot_hmm_probability(
    df: pd.DataFrame,
    tickers: List[str],
    title: str,
    filename: str,
    out_dir: str,
    split_date: str,
    eventos: Optional[List] = None,
):
    """
    Plota a probabilidade contínua de crise (Prob_Crise_HMM) junto ao regime
    discreto (Cluster_HMM) para um grupo de Tickers.

    Demonstra a principal vantagem do HMM: probabilidade suave (0-1)
    versus o label binário do K-Means.
    """
    logger.info(f"Gerando HMM Probability Plot ({title})...")

    if 'Prob_Crise_HMM' not in df.columns or 'Cluster_HMM' not in df.columns:
        logger.warning("[plot_hmm_probability] Colunas de HMM não encontradas. Pulando.")
        return

    case_df = df[df['Ticker'].isin(tickers)].copy()
    if case_df.empty:
        logger.warning(f"[plot_hmm_probability] {title}: nenhum dado.")
        return

    tickers_present = [t for t in tickers if t in case_df['Ticker'].unique()]
    n_tickers = len(tickers_present)
    if n_tickers == 0:
        return

    fig, axes = plt.subplots(n_tickers, 1, figsize=(14, 4 * n_tickers), sharex=True)
    if n_tickers == 1:
        axes = [axes]

    split_dt = pd.to_datetime(split_date)

    for ax, ticker in zip(axes, tickers_present):
        df_t = case_df[case_df['Ticker'] == ticker].sort_values('Data')
        df_t = df_t[df_t['Data'] >= split_dt]   # apenas OOS
        if df_t.empty:
            ax.set_title(f"{ticker} — sem dados OOS")
            continue

        # Background colorido por cluster discreto
        prev_date = df_t['Data'].iloc[0]
        prev_cl   = df_t['Cluster_HMM'].iloc[0]
        for _, row in df_t.iterrows():
            cl = row['Cluster_HMM']
            if cl != prev_cl:
                ax.axvspan(
                    prev_date, row['Data'],
                    facecolor=CLUSTER_PALETTE.get(prev_cl, '#fff'),
                    alpha=0.25
                )
                prev_date = row['Data']
                prev_cl   = cl
        # Último segmento
        ax.axvspan(
            prev_date, df_t['Data'].iloc[-1],
            facecolor=CLUSTER_PALETTE.get(prev_cl, '#fff'),
            alpha=0.25
        )

        # Linha de probabilidade contínua
        ax.plot(df_t['Data'], df_t['Prob_Crise_HMM'],
                color='#c0392b', linewidth=2, label='P(Crise) HMM')
        ax.fill_between(df_t['Data'], df_t['Prob_Crise_HMM'],
                        alpha=0.3, color='#e74c3c')
        ax.axhline(0.5, color='black', linestyle=':', linewidth=1, alpha=0.6)

        ax.set_ylabel(f"{ticker}\nP(Vermelho)")
        ax.set_ylim(0, 1)
        ax.grid(True, linestyle='--', alpha=0.3)

        # Eventos
        _add_event_lines([ax], eventos)
        handles, labels = ax.get_legend_handles_labels()

        # Patches de legenda
        patches = [
            mpatches.Patch(color=CLUSTER_PALETTE[c], alpha=0.4, label=c)
            for c in CLUSTER_ORDER
        ]
        ax.legend(handles=handles + patches,
                  loc='upper right', fontsize=8, ncol=2)

    axes[0].set_title(f"Probabilidade Contínua de Crise (HMM)\n{title}", fontsize=12)
    axes[-1].set_xlabel("Data")
    axes[-1].xaxis.set_major_formatter(mdates.DateFormatter('%Y-%m'))
    plt.setp(axes[-1].xaxis.get_majorticklabels(), rotation=30, ha='right')

    plt.tight_layout()
    plt.savefig(os.path.join(out_dir, filename), dpi=300, bbox_inches='tight')
    plt.close()
    logger.info(f"  → {filename}")


# ===========================================================================
# 4.6 ENSEMBLE PROBABILITY — P(Crise) Ensemble (Contínua)
# ===========================================================================

def plot_ensemble_probability(
    df: pd.DataFrame,
    tickers: List[str],
    title: str,
    filename: str,
    out_dir: str,
    split_date: str,
    eventos: Optional[List] = None,
):
    """
    Plota a evolução da probabilidade contínua de crise (Credit_Tail_Risk_Score) do Ensemble
    com background do cluster discreto do Ensemble.
    """
    logger.info(f"Gerando Ensemble Probability Plot ({title})...")

    if 'Credit_Tail_Risk_Score' not in df.columns:
        logger.warning("[plot_ensemble_probability] Credit_Tail_Risk_Score não encontrada. Pulando.")
        return

    # Se não tiver a categoria discreta (Cluster_Ensemble), criamos on-the-fly para o plot
    if 'Cluster_Ensemble' not in df.columns:
        def categorize(score):
            if pd.isna(score): return 'Inconclusivo'
            if score >= 60: return 'Vermelho'
            elif score >= 35: return 'Amarelo'
            else: return 'Verde'
        df['Cluster_Ensemble'] = df['Credit_Tail_Risk_Score'].apply(categorize)

    case_df = df[df['Ticker'].isin(tickers)].copy()
    if case_df.empty:
        return

    tickers_present = [t for t in tickers if t in case_df['Ticker'].unique()]
    n_tickers = len(tickers_present)
    if n_tickers == 0:
        return

    fig, axes = plt.subplots(n_tickers, 1, figsize=(14, 4 * n_tickers), sharex=True)
    if n_tickers == 1:
        axes = [axes]

    split_dt = pd.to_datetime(split_date)

    for ax, ticker in zip(axes, tickers_present):
        df_t = case_df[case_df['Ticker'] == ticker].sort_values('Data')
        df_t = df_t[df_t['Data'] >= split_dt]   # apenas OOS
        if df_t.empty:
            ax.set_title(f"{ticker} — sem dados OOS")
            continue

        # Background colorido por cluster discreto
        prev_date = df_t['Data'].iloc[0]
        prev_cl   = df_t['Cluster_Ensemble'].iloc[0]
        for _, row in df_t.iterrows():
            cl = row['Cluster_Ensemble']
            if cl != prev_cl:
                ax.axvspan(
                    prev_date, row['Data'],
                    facecolor=CLUSTER_PALETTE.get(prev_cl, '#fff'),
                    alpha=0.25
                )
                prev_date = row['Data']
                prev_cl   = cl
        # Último segmento
        ax.axvspan(
            prev_date, df_t['Data'].iloc[-1],
            facecolor=CLUSTER_PALETTE.get(prev_cl, '#fff'),
            alpha=0.25
        )

        # Linha de probabilidade contínua (Score Ensemble) convertido para probabilidade (0-1)
        prob_ensemble = df_t['Credit_Tail_Risk_Score'] / 100.0
        
        ax.plot(df_t['Data'], prob_ensemble,
                color='#8e44ad', linewidth=2, label='Score Ensemble')
        ax.fill_between(df_t['Data'], prob_ensemble,
                        alpha=0.3, color='#9b59b6')
        ax.axhline(0.60, color='black', linestyle=':', linewidth=1, alpha=0.6) # Threshold Vermelho
        ax.axhline(0.35, color='gray', linestyle=':', linewidth=1, alpha=0.6)  # Threshold Amarelo

        ax.set_ylabel(f"{ticker}\nEnsemble Score")
        ax.set_ylim(0, 1)
        ax.grid(True, linestyle='--', alpha=0.3)

        # Eventos
        _add_event_lines([ax], eventos)
        handles, labels = ax.get_legend_handles_labels()

        # Patches de legenda
        patches = [
            mpatches.Patch(color=CLUSTER_PALETTE[c], alpha=0.4, label=c)
            for c in CLUSTER_ORDER
        ]
        ax.legend(handles=handles + patches,
                  loc='upper right', fontsize=8, ncol=2)

    axes[0].set_title(f"Score Contínuo de Risco de Cauda (Ensemble)\n{title}", fontsize=12)
    axes[-1].set_xlabel("Data")
    axes[-1].xaxis.set_major_formatter(mdates.DateFormatter('%Y-%m'))
    plt.setp(axes[-1].xaxis.get_majorticklabels(), rotation=30, ha='right')

    plt.tight_layout()
    plt.savefig(os.path.join(out_dir, filename), dpi=300, bbox_inches='tight')
    plt.close()
    logger.info(f"  → {filename}")


# ===========================================================================
# 4.5 K-MEANS METRIC — Métrica K-Means no tempo
# ===========================================================================

def plot_kmeans_metric(
    df: pd.DataFrame,
    tickers: List[str],
    title: str,
    filename: str,
    out_dir: str,
    split_date: str,
    eventos: Optional[List] = None,
    metric_col: Optional[str] = None,
):
    """
    Plota a métrica de risco junto ao regime discreto (Cluster_KMeans)
    para evidênciar o mapeamento atemporal do K-Means comparado à transição do HMM.

    Parâmetros
    ----------
    metric_col : str, optional
        Feature a ser plotada no eixo Y. Se None, autodetecta a primeira feature
        disponível na ordem: Expected_Shortfall_99 > VaR_99 > Taxa_ZScore > Volatilidade_EGARCH.
        Isso garante que o gráfico sempre reflita a feature efetivamente usada pelo modelo.
    """
    logger.info(f"Gerando K-Means Metric Plot ({title})...")

    # Autodetecção da feature a plotar: usa ordem de prioridade econômica.
    # A feature escolhida é a mesma que o feature selector provavelmente selecionou,
    # tornando o gráfico coerente com a classificação exibida.
    METRIC_PRIORITY = [
        'Expected_Shortfall_99',
        'VaR_99',
        'Taxa_ZScore',
        'Volatilidade_EGARCH',
    ]
    if metric_col is None:
        for candidate in METRIC_PRIORITY:
            if candidate in df.columns:
                metric_col = candidate
                break

    if metric_col is None or metric_col not in df.columns:
        logger.warning(
            f"[plot_kmeans_metric] Nenhuma feature de métrica encontrada em {METRIC_PRIORITY}. "
            "Pulando."
        )
        return

    if 'Cluster_KMeans' not in df.columns:
        logger.warning("[plot_kmeans_metric] Coluna Cluster_KMeans não encontrada. Pulando.")
        return

    case_df = df[df['Ticker'].isin(tickers)].copy()
    if case_df.empty:
        return

    tickers_present = [t for t in tickers if t in case_df['Ticker'].unique()]
    n_tickers = len(tickers_present)
    if n_tickers == 0:
        return

    fig, axes = plt.subplots(n_tickers, 1, figsize=(14, 4 * n_tickers), sharex=True)
    if n_tickers == 1:
        axes = [axes]

    split_dt = pd.to_datetime(split_date)

    for ax, ticker in zip(axes, tickers_present):
        df_t = case_df[case_df['Ticker'] == ticker].sort_values('Data')
        df_t = df_t[df_t['Data'] >= split_dt]
        if df_t.empty:
            ax.set_title(f"{ticker} — sem dados OOS")
            continue

        prev_date = df_t['Data'].iloc[0]
        prev_cl   = df_t['Cluster_KMeans'].iloc[0]
        for _, row in df_t.iterrows():
            cl = row['Cluster_KMeans']
            if cl != prev_cl:
                ax.axvspan(
                    prev_date, row['Data'],
                    facecolor=CLUSTER_PALETTE.get(prev_cl, '#fff'),
                    alpha=0.25
                )
                prev_date = row['Data']
                prev_cl   = cl
        ax.axvspan(
            prev_date, df_t['Data'].iloc[-1],
            facecolor=CLUSTER_PALETTE.get(prev_cl, '#fff'),
            alpha=0.25
        )

        ax.plot(df_t['Data'], df_t[metric_col],
                color='#2980b9', linewidth=2, label=metric_col.replace('_', ' '))
        ax.axhline(0, color='black', linestyle=':', linewidth=1, alpha=0.6)

        ax.set_ylabel(f"{ticker}\n{metric_col.replace('_', ' ')}")
        ax.grid(True, linestyle='--', alpha=0.3)

        # Eventos
        _add_event_lines([ax], eventos)
        handles, labels = ax.get_legend_handles_labels()

        patches = [
            mpatches.Patch(color=CLUSTER_PALETTE[c], alpha=0.4, label=c)
            for c in CLUSTER_ORDER
        ]
        ax.legend(handles=handles + patches,
                  loc='upper right', fontsize=8, ncol=2)

    axes[0].set_title(f"Dinâmica de Spread (K-Means)\n{title}", fontsize=12)
    axes[-1].set_xlabel("Data")
    axes[-1].xaxis.set_major_formatter(mdates.DateFormatter('%Y-%m'))
    plt.setp(axes[-1].xaxis.get_majorticklabels(), rotation=30, ha='right')

    plt.tight_layout()
    plt.savefig(os.path.join(out_dir, filename), dpi=300, bbox_inches='tight')
    plt.close()
    logger.info(f"  → {filename}")


# ===========================================================================
# 5. BOXPLOT — Distribuição do prêmio por cluster (última data)
# ===========================================================================

def plot_boxplot(
    df: pd.DataFrame,
    out_dir: str,
    cluster_col: str = 'Cluster_KMeans',
    filename_prefix: str = '04',
):
    """Boxplot de Taxa_Ajustada_Prazo por cluster, por Indexador_Grupo."""
    logger.info(f"Gerando Boxplot ({cluster_col}) por Indexador_Grupo...")
    cluster_col = _safe_cluster_col(df, cluster_col)

    ultima_data = df['Data'].max()
    df_ult = df[df['Data'] == ultima_data].copy()
    if df_ult.empty:
        return

    grupos = _get_grupos(df_ult)

    for grupo in grupos:
        g_df = df_ult[df_ult['Indexador_Grupo'] == grupo].copy() \
            if 'Indexador_Grupo' in df_ult.columns else df_ult.copy()
        g_df = g_df.dropna(subset=[cluster_col, 'Taxa_Ajustada_Prazo'])
        if g_df.empty or g_df[cluster_col].nunique() < 2:
            continue

        g_df[cluster_col] = pd.Categorical(
            g_df[cluster_col], categories=CLUSTER_ORDER + ['Inconclusivo'], ordered=True
        )

        fig, ax = plt.subplots(figsize=(8, 5))
        sns.boxplot(
            data=g_df, x=cluster_col, y='Taxa_Ajustada_Prazo',
            hue=cluster_col,
            palette={**CLUSTER_PALETTE},
            order=[c for c in CLUSTER_ORDER if c in g_df[cluster_col].unique()],
            legend=False, ax=ax
        )
        ax.set_title(
            f"Prêmio de Risco por Cluster — {grupo}\n"
            f"Última observação OOS: {ultima_data.date()}"
        )
        ax.set_xlabel("Regime de Crédito")
        ax.set_ylabel("Taxa Ajustada pelo Prazo")
        ax.grid(True, linestyle='--', alpha=0.4)
        plt.tight_layout()

        fname = f"{filename_prefix}_boxplot_{cluster_col.lower()}_{grupo.lower().replace(' ', '_')}.png"
        plt.savefig(os.path.join(out_dir, fname), dpi=300)
        plt.close()
        logger.info(f"  → {fname}")


# ===========================================================================
# 6. CASE STUDY — Decomposição temporal por Ticker (K-Means + HMM)
# ===========================================================================

def plot_case_study(
    df: pd.DataFrame,
    tickers: List[str],
    title: str,
    filename: str,
    out_dir: str,
    split_date: str,
    eventos: Optional[List] = None,
):
    """
    Estudo de caso empírico com painéis dinâmicos:
    - Painel 0: Sinal discreto K-Means (Verde=1, Amarelo=2, Vermelho=3)
    - Painel 1: Sinal discreto HMM
    - Painel 2: Probabilidade contínua de crise (Prob_Crise_HMM)
    - Painéis 3+: Features de risco presentes no DataFrame, plotadas em ordem de
      prioridade econômica: Expected_Shortfall_99, VaR_99, Taxa_Ajustada_Prazo,
      Taxa_ZScore, Volatilidade_EGARCH.

    Inclui linhas verticais de eventos de crédito e de início OOS.
    """
    logger.info(f"Gerando Estudo de Caso ({title})...")

    case_df = df[df['Ticker'].isin(tickers)].copy()
    if case_df.empty:
        logger.warning(f"[plot_case_study] {title}: nenhum dado.")
        return

    has_kmeans = 'Cluster_KMeans' in case_df.columns
    has_hmm    = 'Cluster_HMM'    in case_df.columns
    has_prob   = 'Prob_Crise_HMM' in case_df.columns

    # Painéis de features exibidos em ordem de prioridade econômica.
    # Apenas features presentes no DataFrame são incluídas, garantindo que os gráficos
    # sempre reflitam as features efetivamente usadas pelo modelo naquela execução.
    FEATURE_PANEL_ORDER = [
        ('Expected_Shortfall_99', 'Expected\nShortfall 99'),
        ('VaR_99',                'VaR 99 (%)'),
        ('Taxa_Ajustada_Prazo',   'Taxa Ajustada\n(Yield)'),
        ('Taxa_ZScore',           'Z-Score\nSpread'),
        ('Volatilidade_EGARCH',   'Volatilidade\nEGARCH (%)'),
    ]
    feature_panels = [
        (col, lbl) for col, lbl in FEATURE_PANEL_ORDER
        if col in case_df.columns
    ]

    n_panels = 3 + len(feature_panels)  # K-Means + HMM + Prob_Crise + features dinâmicas
    fig, axes = plt.subplots(n_panels, 1, figsize=(14, 4 * n_panels), sharex=True)

    for ticker in tickers:
        df_t = case_df[case_df['Ticker'] == ticker].sort_values('Data')
        if df_t.empty:
            continue

        # Painel 0: K-Means discreto
        if has_kmeans:
            df_t['_km_num'] = df_t['Cluster_KMeans'].map(CLUSTER_NUMERIC).fillna(0)
            axes[0].step(df_t['Data'], df_t['_km_num'], where='post',
                         linewidth=2, label=ticker)

        # Painel 1: HMM discreto
        if has_hmm:
            df_t['_hmm_num'] = df_t['Cluster_HMM'].map(CLUSTER_NUMERIC).fillna(0)
            axes[1].step(df_t['Data'], df_t['_hmm_num'], where='post',
                         linewidth=2, label=ticker)

        # Painel 2: Probabilidade contínua de crise
        if has_prob:
            axes[2].plot(df_t['Data'], df_t['Prob_Crise_HMM'],
                         linewidth=1.8, label=ticker)
            axes[2].fill_between(df_t['Data'], df_t['Prob_Crise_HMM'], alpha=0.2)

        # Painéis 3+: features dinâmicas
        for ax_idx, (feat_col, _) in enumerate(feature_panels):
            ax = axes[3 + ax_idx]
            if feat_col in df_t.columns:
                ax.plot(df_t['Data'], df_t[feat_col], linewidth=1.5, label=ticker)

    # Linha de split + eventos
    split_dt = pd.to_datetime(split_date)
    for ax in axes:
        ax.axvline(split_dt, color='black', linestyle='--', linewidth=1.6, alpha=0.8)

    _add_event_lines(axes[:1], eventos)

    # Formatação dos eixos fixos
    fixed_labels = [
        'K-Means\n(regime)',
        'HMM\n(regime)',
        'P(Crise)\nHMM',
    ]
    for ax, ylabel in zip(axes[:3], fixed_labels):
        ax.set_ylabel(ylabel, fontsize=9)
        ax.grid(True, alpha=0.3)

    # Formatação dos painéis de features dinâmicos
    for ax_idx, (_, feat_lbl) in enumerate(feature_panels):
        ax = axes[3 + ax_idx]
        ax.set_ylabel(feat_lbl, fontsize=9)
        ax.grid(True, alpha=0.3)

    # Eixos de regime discreto (0–3)
    for ax in [axes[0], axes[1]]:
        ax.set_yticks([0, 1, 2, 3])
        ax.set_yticklabels(['Inc.', 'Verde', 'Amarelo', 'Vermelho'], fontsize=8)
        ax.set_ylim(-0.2, 3.5)

    # Probabilidade 0–1
    axes[2].set_ylim(0, 1)
    axes[2].axhline(0.5, color='gray', linestyle=':', linewidth=1)

    axes[0].set_title(
        f"Estudo de Caso Empírico: {title}\n"
        "Decomposição K-Means (baseline) vs HMM (proposto)",
        fontsize=12
    )
    axes[0].legend(loc='upper left', bbox_to_anchor=(1.01, 1), fontsize=8)
    if eventos:
        axes[0].legend(loc='upper left', bbox_to_anchor=(1.01, 1), fontsize=7, ncol=1)

    axes[-1].set_xlabel("Data")
    axes[-1].xaxis.set_major_formatter(mdates.DateFormatter('%Y-%m'))
    plt.setp(axes[-1].xaxis.get_majorticklabels(), rotation=30, ha='right')

    plt.tight_layout()
    plt.savefig(os.path.join(out_dir, filename), dpi=300, bbox_inches='tight')
    plt.close()
    logger.info(f"  → {filename}")


# ===========================================================================
# RUNNER PRINCIPAL
# ===========================================================================

def run_defense_visuals(
    results_path: Optional[str] = None,
    out_dir:      Optional[str] = None,
    split_date:   str = '2023-01-01',
):
    """
    Ponto de entrada para gerar todos os gráficos de defesa.

    Lê o CSV de resultados do motor (resultado_frequentist_engine.csv) e
    gera automaticamente todos os painéis comparativos K-Means vs HMM.
    """
    if results_path is None:
        from credit_tail_analytics.utils import dados_dir
        results_path = str(dados_dir() / 'resultado_frequentist_engine.csv')
    if out_dir is None:
        from credit_tail_analytics.utils import graficos_dir
        out_dir = str(graficos_dir())

    os.makedirs(out_dir, exist_ok=True)

    if not os.path.exists(results_path):
        logger.error(f"Arquivo de resultados não encontrado: {results_path}")
        return

    logger.info(f"Carregando resultados: {results_path}")
    df = pd.read_csv(results_path)
    df['Data'] = pd.to_datetime(df['Data'])

    # Compatibilidade com versões anteriores (coluna de fallback)
    if 'Cluster_KMeans' not in df.columns and 'Cluster_Risco_KMeans' in df.columns:
        df['Cluster_KMeans'] = df['Cluster_Risco_KMeans']
    if 'Cluster_KMeans' not in df.columns and 'Cluster_Risco_Mahalanobis' in df.columns:
        df['Cluster_KMeans'] = df['Cluster_Risco_Mahalanobis']
    if 'Indexador_Grupo' not in df.columns:
        df['Indexador_Grupo'] = '_all'

    has_hmm = 'Cluster_HMM' in df.columns
    logger.info(
        f"Colunas disponíveis: K-Means={'Cluster_KMeans' in df.columns}, "
        f"HMM={has_hmm}, Prob_Crise={'Prob_Crise_HMM' in df.columns}"
    )

    # ------------------------------------------------------------------
    # Visão geral
    # ------------------------------------------------------------------
    plot_cross_section(df, out_dir, cluster_col='Cluster_KMeans', filename_prefix='01')
    plot_contagion(df, out_dir, split_date, cluster_col='Cluster_KMeans', filename_prefix='02a')
    if has_hmm:
        plot_contagion(df, out_dir, split_date, cluster_col='Cluster_HMM', filename_prefix='02b')
        plot_model_comparison(df, out_dir, split_date, filename_prefix='03')

    plot_boxplot(df, out_dir, cluster_col='Cluster_KMeans', filename_prefix='04a')
    if has_hmm:
        plot_boxplot(df, out_dir, cluster_col='Cluster_HMM', filename_prefix='04b')

    # ------------------------------------------------------------------
    # Estudos de Caso
    # ------------------------------------------------------------------
    from credit_tail_analytics.utils import dados_dir
    cadastro_path = dados_dir() / 'cadastro_debentures.csv'
    df_cad = pd.read_csv(cadastro_path) if os.path.exists(cadastro_path) else pd.DataFrame()

    prefix_map = {
        'Lojas Americanas': ['LAME', 'AMER'],
        'Pão de Açúcar (GPA)': ['CBRD', 'PCAR'],
        'GPA / Pão de Açúcar': ['CBRD', 'PCAR'],
        'Light S.A.': ['LIGH', 'LSVE'],
        'Via Varejo (Casas Bahia)': ['VVAR', 'CBHA'],
        'Grupo Casas Bahia': ['VVAR', 'CBHA'],
        'Gol Linhas Aéreas': ['GOLL', 'VRGL'],
        "Rede D'Or": ['RDOR'],
        'Oi S.A.': ['OIBR', 'BFLE', 'SNGO', 'FRAG', 'RODT', 'PQCN', 'CLAG'],
        'CVC Corp': ['CVCB'],
        'Azul': ['AZUL', 'SAAS'],
        'Multi / Multilaser': ['MULP', 'VLIM', 'VLIO'],
        'Dasa': ['DASA'],
        'Unigel': ['UGEL'],
        'Sequoia Logística': ['SEQL'],
        'Madero': ['MDRO'],
    }

    casos = []
    idx = 5
    for empresa, eventos in EVENTOS_CREDITO.items():
        tickers_empresa = set()
        
        if empresa in prefix_map:
            for p in prefix_map[empresa]:
                tickers_empresa.update([t for t in df['Ticker'].unique() if str(t).startswith(p)])
                
        if not df_cad.empty:
            first_word = empresa.split()[0].upper()
            if first_word not in ['GRUPO', 'VIA', 'OI', 'GOL']:
                tkrs_cad = df_cad[df_cad['Empresa'].str.contains(first_word, na=False, case=False)]['Ticker'].unique()
                tickers_empresa.update([t for t in tkrs_cad if t in df['Ticker'].unique()])
                
        tickers_empresa = list(tickers_empresa)
        if tickers_empresa:
            filename_empresa = empresa.lower().replace(" ", "_").replace("/", "").replace("&", "")
            casos.append((tickers_empresa, empresa, f'{idx:02d}_estudo_caso_{filename_empresa}.png', empresa))
            idx += 1


    for tickers, title, filename, evento_key in casos:
        eventos = EVENTOS_CREDITO.get(evento_key) if evento_key else None
        plot_case_study(df, tickers, title, filename, out_dir, split_date, eventos=eventos)

        # Plot adicional de probabilidade HMM por estudo de caso
        if has_hmm and 'Prob_Crise_HMM' in df.columns:
            hmm_filename = filename.replace('.png', '_hmm_prob.png')
            plot_hmm_probability(df, tickers, title, hmm_filename, out_dir, split_date, eventos=eventos)

        # Plot adicional de métrica K-Means por estudo de caso.
        # metric_col=None ativa autodetecção: prioriza Expected_Shortfall_99 > VaR_99 > Taxa_ZScore.
        if 'Cluster_KMeans' in df.columns:
            kmeans_filename = filename.replace('.png', '_kmeans_metric.png')
            plot_kmeans_metric(
                df, tickers, title, kmeans_filename, out_dir, split_date,
                eventos=eventos, metric_col=None,
            )
            
        # Plot adicional de Ensemble Score por estudo de caso
        if 'Credit_Tail_Risk_Score' in df.columns:
            ens_filename = filename.replace('.png', '_ensemble_prob.png')
            plot_ensemble_probability(df, tickers, title, ens_filename, out_dir, split_date, eventos=eventos)

    logger.info(f"\n✓ Todos os gráficos salvos em: {out_dir}")


if __name__ == '__main__':
    run_defense_visuals()
