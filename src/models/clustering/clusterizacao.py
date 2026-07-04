import logging
import numpy as np
import pandas as pd
from sklearn.cluster import KMeans
from sklearn.preprocessing import StandardScaler

logger = logging.getLogger(__name__)

class ClassificadorRisco:
    """
    Classificador não-supervisionado de risco de crédito baseado em agrupamento (Clustering).

    Aplica K-Means sobre dados transversalmente normalizados de risco 
    e liquidez para categorizar debêntures em três níveis lógicos de risco.

    Attributes:
        scaler (StandardScaler): Instância do normalizador estatístico (Z-score).
        kmeans (KMeans): Instância do modelo de clusterização K-Means (K=3).
    """

    def __init__(self, random_state: int = 42) -> None:
        """
        Inicializa o ClassificadorRisco com K=3 e semente de aleatoriedade fixa.

        Args:
            random_state (int): Semente para garantir a reprodutibilidade dos centróides.
        """
        self.scaler = StandardScaler()
        # n_init='auto' recomendado nas versões recentes do scikit-learn
        self.kmeans = KMeans(n_clusters=3, random_state=random_state, n_init='auto')

    def _ordenar_clusters(self, centroides: np.ndarray, colunas: list[str]) -> dict[int, int]:
        """
        Analisa a posição espacial dos centróides gerados e mapeia os rótulos originais 
        para uma ordenação lógica de risco (0: Verde, 1: Amarelo, 2: Vermelho).

        A ordenação baseia-se na média agregada da 'volatilidade_projetada' e 'amihud'. 
        Valores mais altos nestas features normalizadas indicam clusters de maior risco.

        Args:
            centroides (np.ndarray): Matriz espacial de centróides gerada pelo KMeans.
            colunas (list[str]): Lista com a ordem exata das colunas treinadas.

        Returns:
            dict[int, int]: Dicionário de mapeamento {id_cluster_original: id_risco_logico}.
        """
        idx_vol = colunas.index('volatilidade_projetada')
        idx_amihud = colunas.index('amihud')

        # O Score de Risco do centróide soma os valores de Volatilidade e Amihud
        # Quanto maior a volatilidade e maior o prêmio de iliquidez, maior o risco.
        scores_risco = centroides[:, idx_vol] + centroides[:, idx_amihud]

        # argsort ordena do menor (risco mais baixo) para o maior (risco mais alto)
        # Retorna a ordem dos índices originais (0, 1, 2) que gera a lista ordenada.
        ordem_crescente = np.argsort(scores_risco)

        # Mapeamos o ID original para o nível lógico de risco, onde:
        # 0 = Risco Verde (Menor score agregado)
        # 1 = Risco Amarelo (Score intermediário)
        # 2 = Risco Vermelho (Maior score agregado)
        mapeamento = {
            int(id_original): nivel_logico 
            for nivel_logico, id_original in enumerate(ordem_crescente)
        }
        
        return mapeamento

    def classificar_ativos(self, df_ativos: pd.DataFrame) -> pd.DataFrame:
        """
        Executa a esteira de classificação: normalização, clusterização e ordenação lógica.

        Args:
            df_ativos (pd.DataFrame): DataFrame contendo as características transversais das 
                debêntures. Obrigatoriamente deve conter as colunas exatas: 
                'volatilidade_projetada', 'amihud' e 'duration'.

        Returns:
            pd.DataFrame: Cópia do DataFrame original acrescida da coluna 'cluster_risco' 
                (0: Verde, 1: Amarelo, 2: Vermelho).

        Raises:
            ValueError: Se o DataFrame não possuir as colunas necessárias ou contiver NaNs.
        """
        colunas_necessarias = ['volatilidade_projetada', 'amihud', 'duration']
        
        if not all(col in df_ativos.columns for col in colunas_necessarias):
            raise ValueError(
                f"O DataFrame fornecido deve conter obrigatoriamente as colunas: "
                f"{colunas_necessarias}"
            )

        if df_ativos[colunas_necessarias].isnull().any().any():
            raise ValueError(
                "Foram detectados valores nulos nas features. O processo de clusterização "
                "exige dados completos. Trate os NaNs antes de chamar este método."
            )

        df_resultado = df_ativos.copy()
        
        # 1. Normalização (Z-score)
        # Essencial para garantir que a magnitude subjacente do volume financeiro ou 
        # as escalas numéricas não distorçam o cálculo da Distância Euclidiana.
        X_bruto = df_resultado[colunas_necessarias].values
        X_normalizado = self.scaler.fit_transform(X_bruto)

        # 2. Clusterização com K-Means
        labels_brutos = self.kmeans.fit_predict(X_normalizado)
        centroides = self.kmeans.cluster_centers_

        # 3. Ordenação Lógica de Risco (Reclassificação dos Clusters)
        mapa_logico = self._ordenar_clusters(centroides, colunas_necessarias)
        logger.info(f"Mapeamento de Centróides do K-Means (Original -> Lógico): {mapa_logico}")

        # 4. Output da classificação final
        # Aplicamos o mapeamento lógico à lista de clusters brutos gerados pelo modelo
        df_resultado['cluster_risco'] = [mapa_logico[label] for label in labels_brutos]
        
        return df_resultado
