"""
clustering_validation.py
------------------------
Funcoes para validacao e justificativa empirica do numero de clusters k.

Gera graficos de Elbow Method (inercia vs k) e Silhouette Score (media vs k),
alem de um grafico de Silhouette por amostra para o k escolhido.

Uso:
    from credit_tail_analytics.analysis.clustering_validation import plot_elbow_silhouette

    plot_elbow_silhouette(X_scaled, k_range=range(2, 7), output_dir='graficos/')
"""

import os
import logging
import warnings
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.cm as cm
from sklearn.cluster import KMeans
from sklearn.metrics import silhouette_score, silhouette_samples

warnings.filterwarnings('ignore')
logger = logging.getLogger('ClusteringValidation')


def plot_elbow_silhouette(
    X: np.ndarray,
    k_range: range = range(2, 8),
    k_chosen: int = 3,
    random_state: int = 42,
    output_dir: str = '.',
    filename_prefix: str = 'cluster_validation',
    title_suffix: str = '',
) -> pd.DataFrame:
    """
    Gera o Elbow Method e o Silhouette Score para validacao do numero de clusters k.

    Parametros
    ----------
    X : np.ndarray
        Matriz de features ja padronizada (RobustScaler aplicado previamente).
    k_range : range
        Faixa de valores de k a testar. Padrao: range(2, 8).
    k_chosen : int
        O k escolhido no trabalho (sera destacado nos graficos). Padrao: 3.
    random_state : int
        Semente para reproducibilidade. Padrao: 42.
    output_dir : str
        Diretorio para salvar as imagens geradas.
    filename_prefix : str
        Prefixo dos arquivos de saida.
    title_suffix : str
        Sufixo opcional para o titulo (ex: 'IPCA', 'CDI Spread').

    Retorna
    -------
    pd.DataFrame com colunas: k, Inertia, Silhouette_Score
    """
    os.makedirs(output_dir, exist_ok=True)
    ks = list(k_range)

    inertias = []
    silhouette_medias = []

    from sklearn.model_selection import train_test_split

    logger.info(f'Calculando metricas para k em {ks}...')
    for k in ks:
        km = KMeans(n_clusters=k, random_state=random_state, n_init='auto')
        labels = km.fit_predict(X)
        inertias.append(km.inertia_)
        if k >= 2:
            if len(X) > 10000:
                try:
                    _, X_sample, _, labels_sample = train_test_split(X, labels, test_size=10000, stratify=labels, random_state=random_state)
                except ValueError:
                    np.random.seed(random_state)
                    indices = np.random.choice(len(X), 10000, replace=False)
                    X_sample = X[indices]
                    labels_sample = labels[indices]
            else:
                X_sample = X
                labels_sample = labels
                
            try:
                sil = silhouette_score(X_sample, labels_sample)
            except ValueError:
                sil = float('nan')
        else:
            sil = float('nan')
        silhouette_medias.append(sil)
        logger.info(f'  k={k}: Inertia={km.inertia_:.2f}, Silhouette={sil:.4f}')

    df_val = pd.DataFrame({'k': ks, 'Inertia': inertias, 'Silhouette_Score': silhouette_medias})

    # ---------------------------------------------------------------
    # Figura 1: Elbow + Silhouette lado a lado
    # ---------------------------------------------------------------
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(12, 5))
    titulo_base = 'Validacao do Numero de Clusters (k)'
    if title_suffix:
        titulo_base += f' — {title_suffix}'
    fig.suptitle(titulo_base, fontsize=13, fontweight='bold')

    # Elbow
    ax1.plot(ks, inertias, 'o-', color='steelblue', linewidth=2, markersize=8)
    ax1.axvline(x=k_chosen, color='firebrick', linestyle='--', linewidth=1.5,
                label=f'k={k_chosen} (escolhido)')
    ax1.set_xlabel('Numero de Clusters (k)')
    ax1.set_ylabel('Inercia Total (Within-Cluster Sum of Squares)')
    ax1.set_title('Elbow Method')
    ax1.set_xticks(ks)
    ax1.legend()
    ax1.grid(alpha=0.3)

    # Curva de variacao percentual (taxa de reducao de inercia)
    if len(inertias) > 1:
        ax1_b = ax1.twinx()
        delta_pct = [
            abs((inertias[i] - inertias[i - 1]) / inertias[i - 1]) * 100
            for i in range(1, len(inertias))
        ]
        ax1_b.bar(ks[1:], delta_pct, alpha=0.2, color='steelblue', width=0.4, label='Reducao (%)')
        ax1_b.set_ylabel('Reducao de Inercia (%)', color='steelblue', alpha=0.7)
        ax1_b.tick_params(axis='y', labelcolor='steelblue')

    # Silhouette Score medio
    ax2.plot(ks, silhouette_medias, 's-', color='darkgreen', linewidth=2, markersize=8)
    ax2.axvline(x=k_chosen, color='firebrick', linestyle='--', linewidth=1.5,
                label=f'k={k_chosen} (escolhido)')
    idx_best_sil = int(np.nanargmax(silhouette_medias))
    ax2.scatter([ks[idx_best_sil]], [silhouette_medias[idx_best_sil]],
                color='gold', s=150, zorder=5, edgecolor='black', label=f'Melhor k={ks[idx_best_sil]}')
    ax2.set_xlabel('Numero de Clusters (k)')
    ax2.set_ylabel('Silhouette Score Medio')
    ax2.set_title('Silhouette Score por k')
    ax2.set_xticks(ks)
    ax2.legend()
    ax2.grid(alpha=0.3)

    plt.tight_layout()
    out1 = os.path.join(output_dir, f'{filename_prefix}_elbow_silhouette.png')
    plt.savefig(out1, dpi=180, bbox_inches='tight')
    plt.close()
    logger.info(f'Grafico Elbow + Silhouette salvo em {out1}')

    # ---------------------------------------------------------------
    # Figura 2: Silhouette por amostra para o k escolhido
    # ---------------------------------------------------------------
    km_chosen = KMeans(n_clusters=k_chosen, random_state=random_state, n_init='auto')
    labels_chosen = km_chosen.fit_predict(X)
    
    from sklearn.model_selection import train_test_split
    
    if len(X) > 10000:
        try:
            _, X_sample, _, labels_sample = train_test_split(X, labels_chosen, test_size=10000, stratify=labels_chosen, random_state=random_state)
        except ValueError:
            np.random.seed(random_state)
            indices = np.random.choice(len(X), 10000, replace=False)
            X_sample = X[indices]
            labels_sample = labels_chosen[indices]
    else:
        X_sample = X
        labels_sample = labels_chosen
        
    sil_values = silhouette_samples(X_sample, labels_sample)

    fig2, ax3 = plt.subplots(figsize=(8, 5))
    y_lower = 10
    colors = cm.nipy_spectral(np.linspace(0.2, 0.85, k_chosen))

    for i, (c_idx, cor) in enumerate(zip(range(k_chosen), colors)):
        cluster_sil = np.sort(sil_values[labels_sample == c_idx])
        size_cluster = len(cluster_sil)
        y_upper = y_lower + size_cluster

        ax3.fill_betweenx(
            np.arange(y_lower, y_upper),
            0, cluster_sil, facecolor=cor, edgecolor=cor, alpha=0.7
        )
        ax3.text(-0.05, y_lower + 0.5 * size_cluster, str(i), fontsize=10, color=cor)
        y_lower = y_upper + 10

    sil_media = np.nanmean(silhouette_medias)
    ax3.axvline(x=sil_media, color='firebrick', linestyle='--',
                label=f'Score Medio = {sil_media:.3f}')
    ax3.set_xlabel('Coeficiente de Silhouette')
    ax3.set_ylabel('Cluster')
    ax3.set_title(f'Silhouette por Amostra — k={k_chosen}' + (f' ({title_suffix})' if title_suffix else ''))
    ax3.set_xlim([-0.2, 1.0])
    ax3.legend()
    ax3.grid(axis='x', alpha=0.3)

    plt.tight_layout()
    out2 = os.path.join(output_dir, f'{filename_prefix}_silhouette_k{k_chosen}.png')
    plt.savefig(out2, dpi=180, bbox_inches='tight')
    plt.close()
    logger.info(f'Grafico Silhouette por amostra salvo em {out2}')

    logger.info(f'\nResumo da Validacao:\n{df_val.to_string(index=False)}')
    logger.info(f'k com melhor Silhouette: {ks[idx_best_sil]} (Score={silhouette_medias[idx_best_sil]:.4f})')

    return df_val


if __name__ == '__main__':
    print('clustering_validation: use plot_elbow_silhouette(X_scaled, k_range=range(2,7)).')
