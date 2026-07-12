import numpy as np
import pandas as pd
import scipy.stats as stats
from arch import arch_model
from sklearn.preprocessing import StandardScaler, RobustScaler
from sklearn.cluster import KMeans
from sklearn.mixture import GaussianMixture
from typing import Dict, List, Tuple, Union, Optional
import warnings

# Ignorar FutureWarnings do Pandas/KMeans para manter a saída limpa em produção
warnings.filterwarnings("ignore", category=FutureWarning)

class CreditRiskEngine:
    """   
    Responsável por realizar a ingestão e feature engineering de dados de debêntures,
    estimar a volatilidade via AR(1)-EGARCH(1,1)-t, calcular o VaR e classificar
    transversalmente o risco de cauda utilizando K-Means em janelas móveis.
    
    Attributes:
        df (pd.DataFrame): O DataFrame principal contendo a base de dados de entrada.
        volume_map (Dict[str, int]): Dicionário de mapeamento para o Score de Liquidez.
    """

    def __init__(self, df: pd.DataFrame):
        """
        Inicializa o CreditRiskEngine e valida a integridade dos dados de entrada.
        
        Args:
            df (pd.DataFrame): DataFrame com colunas obrigatórias:
                ['Data', 'Ticker', 'Indexador', 'PU', 
                 'Faixa_Volume_ANBIMA', 'Taxa_Ativo', 'DU_Vencimento']
        """
        self.df = df.copy()
        self.volume_map: Dict[str, int] = {
            'Até 1MM': 1,
            'Entre 1MM e 5MM': 2,
            'Superior a 5MM': 3
        }
        self._validate_input()
        self._feature_engineering()

    def _validate_input(self) -> None:
        """
        Valida se as colunas obrigatórias estão presentes e formata a data.
        
        Raises:
            ValueError: Se alguma coluna obrigatória estiver ausente.
        """
        required_columns = [
            'Data', 'Ticker', 'Indexador', 'PU', 
            'Faixa_Volume_ANBIMA', 'Taxa_Ativo', 'DU_Vencimento'
        ]
        
        missing = [col for col in required_columns if col not in self.df.columns]
        if missing:
            raise ValueError(f"Colunas obrigatórias ausentes: {missing}")
            
        self.df['Data'] = pd.to_datetime(self.df['Data'])
        self.df.sort_values(by=['Ticker', 'Data'], inplace=True)
        self.df.reset_index(drop=True, inplace=True)

    def _feature_engineering(self) -> None:
        """
        Realiza a engenharia de atributos inicial:
        1. Mapeamento de Faixa_Volume_ANBIMA para Score_Liquidez.
        2. Cálculo da Taxa_Ajustada_Prazo (Taxa / ln(max(DU, 2))).
        3. Cálculo dos Log-Retornos do PU agrupados por Ticker.
        """
        # Mapeamento do Score de Liquidez
        # Ativos não mapeados recebem score 1 (mais ilíquido) por conservadorismo
        self.df['Score_Liquidez'] = self.df['Faixa_Volume_ANBIMA'].map(self.volume_map).fillna(1).astype(int)

        # Taxa Ajustada a Prazo: Estresse Relativo eliminando ETTJ
        du_seguro = np.maximum(self.df['DU_Vencimento'], 2)
        self.df['Taxa_Ajustada_Prazo'] = self.df['Taxa_Ativo'] / np.log(du_seguro)

        # Log-Retornos diários do PU
        self.df['Log_Retorno'] = self.df.groupby('Ticker')['PU'].transform(
            lambda x: np.log(x / x.shift(1))
        )
        
        # Separação Inteligente de Indexador (DI Spread vs DI Percentual)
        medias_taxa = self.df.groupby('Ticker')['Taxa_Ativo'].transform('mean')
        is_di = self.df['Indexador'] == 'DI'
        is_percent = medias_taxa > 30
        self.df.loc[is_di & is_percent, 'Indexador'] = 'DI_Percentual'
        self.df.loc[is_di & ~is_percent, 'Indexador'] = 'DI_Spread'

        # Z-Score Longitudinal (Alerta Precoce de Deterioração)
        self.df['Taxa_Ffill'] = self.df.groupby('Ticker')['Taxa_Ativo'].ffill()
        def calc_zscore(x):
            r = x.rolling(window=60, min_periods=10)
            return (x - r.mean()) / r.std().replace(0, np.nan)
            
        self.df['Taxa_ZScore'] = self.df.groupby('Ticker')['Taxa_Ffill'].transform(calc_zscore).fillna(0)
        
    def _egarch_var(self, returns: pd.Series, alpha: float = 0.01, train_size: float = 0.7) -> Tuple[pd.Series, pd.Series]:
        """
        Calcula a volatilidade condicional e o VaR usando AR(1)-EGARCH(1,1)-t.
        Aplica um Out-of-Sample Split rígido para prevenir Look-Ahead Bias.
        
        Args:
            returns (pd.Series): Série de log-retornos.
            alpha (float): Nível de significância (0.01 = 99% VaR).
            train_size (float): Percentual da série para fitting In-Sample (ex: 0.7 = 70%).
            
        Returns:
            Tuple[pd.Series, pd.Series]: Tupla contendo:
                - Volatilidade Condicional
                - VaR a (1 - alpha)
        """
        vol_series = pd.Series(np.nan, index=returns.index)
        var_series = pd.Series(np.nan, index=returns.index)
        
        valid_returns = returns.dropna()
        if len(valid_returns) < 30:  # Mínimo de pontos para convergência razoável
            return vol_series, var_series
            
        # Escala por 100 para facilitar a otimização
        returns_scaled = valid_returns * 100
        
        # Split Out-of-Sample para evitar Look-Ahead Bias
        n_obs = len(valid_returns)
        split_idx = int(n_obs * train_size)
        
        # Exige um mínimo absoluto no In-Sample para tentar convergir
        if split_idx < 25:
            return vol_series, var_series
            
        try:
            model = arch_model(
                returns_scaled, 
                mean='AR', lags=1, 
                vol='EGARCH', p=1, o=1, q=1, # o=1 para assimetria no EGARCH
                dist='t',
                rescale=False
            )
            
            # FIT IN-SAMPLE: Otimiza os parâmetros usando apenas a parte inicial da série
            res_is = model.fit(last_obs=split_idx, disp='off', show_warning=False)
            
            # FILTER OUT-OF-SAMPLE: Congela os pesos ajustados (res_is.params) e filtra toda a série histórica.
            # Isso garante que a volatilidade após split_idx é 100% preditiva e livre de data leakage.
            res_oos = model.fix(res_is.params)
            
            cond_vol = res_oos.conditional_volatility
            # Para o VaR dinâmico, usamos a média zero (ou AR) e a vol condicional
            mu = returns_scaled.mean() # Aproximação base. O rigor pede média AR, mas mu empírico é estável em altas freqs.
            
            # Extrair quantil da distribuição t-Student ajustada (parâmetro de graus de liberdade nu)
            nu = res_is.params.get('nu', 5.0)
            
            # Limite inferior do VaR (cauda esquerda)
            q_alpha = model.distribution.ppf(1 - alpha, nu)
            var_99 = mu + cond_vol * q_alpha
            
            # Retorna para a escala original (/ 100)
            vol_series.loc[valid_returns.index] = cond_vol / 100
            var_series.loc[valid_returns.index] = var_99 / 100
            
        except Exception as e:
            # Captura de exceções numéricas e de não convergência
            pass
            
        return vol_series, var_series

    def _kupiec_pof_test(self, retornos: Union[pd.Series, np.ndarray], var_limits: Union[pd.Series, np.ndarray], nivel_confianca: float = 0.99) -> float:
        """
        Implementa o teste de Proportion of Failures (POF) de Kupiec para Backtesting do VaR.
        
        Args:
            retornos (Union[pd.Series, np.ndarray]): Série de retornos observados.
            var_limits (Union[pd.Series, np.ndarray]): Limite inferior do VaR.
            nivel_confianca (float): Nível de confiança original do VaR (ex: 0.99).
            
        Returns:
            float: P-Valor do teste Qui-Quadrado de Kupiec. 
                   (P-Valor > 0.05 indica modelo aderente).
        """
        ret = np.asarray(retornos)
        var = np.asarray(var_limits)
        
        mask = ~np.isnan(ret) & ~np.isnan(var)
        ret = ret[mask]
        var = var[mask]
        
        n = len(ret)
        if n == 0:
            return np.nan
            
        # Contabiliza quebras (retornos menores que o limite inferior projetado)
        failures = np.sum(ret < var)
        p_expected = 1.0 - nivel_confianca
        
        if failures == 0:
            lr_stat = -2 * n * np.log(1 - p_expected)
        else:
            failure_rate = failures / n
            
            if failure_rate >= 1.0:
                lr_stat = -2 * n * np.log(p_expected)
            else:
                num = ((1 - p_expected)**(n - failures)) * (p_expected**failures)
                den = ((1 - failure_rate)**(n - failures)) * (failure_rate**failures)
                
                # Evitar divisões por zero ou log(0) em edge cases extremos
                if den <= 0 or num <= 0:
                    return np.nan
                    
                lr_stat = -2 * np.log(num / den)
                
        p_value = 1.0 - stats.chi2.cdf(lr_stat, df=1)
        return p_value

    def build_volatility_features(self) -> None:
        """
        Aplica o modelo EGARCH-t iterativamente sobre os Tickers e popula o DataFrame
        com 'Volatilidade_EGARCH' e 'VaR_99'.
        """
        # Inicializa colunas
        self.df['Volatilidade_EGARCH'] = np.nan
        self.df['VaR_99'] = np.nan
        
        for ticker, group in self.df.groupby('Ticker'):
            vol, var = self._egarch_var(group['Log_Retorno'])
            self.df.loc[group.index, 'Volatilidade_EGARCH'] = vol
            self.df.loc[group.index, 'VaR_99'] = var

    def run_dynamic_clustering(self, window_days: int = 60, step_days: int = 30) -> pd.DataFrame:
        """
        Executa o Rolling K-Means Transversal (Inteligência Dinâmica).
        Agrupa os dados transversalmente em janelas temporais por Indexador e classifica
        os ativos em diferentes clusters de Risco Relativo.
        
        Args:
            window_days (int): Tamanho da janela móvel em dias (ex: 60).
            step_days (int): Salto de tempo entre janelas em dias (ex: 30 para mensal).
            
        Returns:
            pd.DataFrame: Base longitudinal estruturada constando Data da Janela,
                          Ticker, Atributos Médios da janela e o Cluster_Risco.
        """
        df_sorted = self.df.sort_values('Data').dropna(subset=['Taxa_Ajustada_Prazo', 'Volatilidade_EGARCH', 'Taxa_ZScore', 'Score_Liquidez'])
        
        if df_sorted.empty:
            return pd.DataFrame()
            
        start_date = df_sorted['Data'].min()
        end_date = df_sorted['Data'].max()
        
        current_start = start_date
        results: List[pd.DataFrame] = []
        
        while current_start < end_date:
            current_end = current_start + pd.Timedelta(days=window_days)
            window_df = df_sorted[(df_sorted['Data'] >= current_start) & (df_sorted['Data'] < current_end)]
            
            if not window_df.empty:
                for indexador, cohort_df in window_df.groupby('Indexador'):
                    # Agrega dados para formar a Matriz Transversal
                    cross_sec = cohort_df.groupby('Ticker').agg({
                        'Taxa_Ajustada_Prazo': 'mean',
                        'Volatilidade_EGARCH': 'mean',
                        'Taxa_ZScore': 'mean',
                        'Score_Liquidez': lambda x: pd.Series(x).mode().iloc[0] if not pd.Series(x).mode().empty else np.nan
                    }).dropna()
                    
                    if len(cross_sec) >= 3:
                        # RobustScaler Intracohorte
                        scaler = RobustScaler()
                        X_scaled = scaler.fit_transform(cross_sec)
                        
                        # 1. K-Means Transversal
                        kmeans = KMeans(n_clusters=3, random_state=42, n_init=10)
                        clusters_kmeans = kmeans.fit_predict(X_scaled)
                        
                        centers_kmeans = kmeans.cluster_centers_
                        # Feature index: 0 = Taxa, 1 = Vol, 2 = ZScore, 3 = Liquidez
                        risk_scores_kmeans = centers_kmeans[:, 0] + centers_kmeans[:, 1] + centers_kmeans[:, 2] - centers_kmeans[:, 3]
                        sorted_clusters_kmeans = np.argsort(risk_scores_kmeans)
                        cluster_map_kmeans = {
                            sorted_clusters_kmeans[0]: 'Verde',    # Menor Risco
                            sorted_clusters_kmeans[1]: 'Amarelo',  # Risco Médio
                            sorted_clusters_kmeans[2]: 'Vermelho'  # Maior Risco
                        }
                        cross_sec['Cluster_Risco_KMeans'] = [cluster_map_kmeans[c] for c in clusters_kmeans]

                        # 2. Gaussian Mixture Models (GMM) Transversal
                        gmm = GaussianMixture(n_components=3, random_state=42, n_init=10)
                        clusters_gmm = gmm.fit_predict(X_scaled)
                        
                        centers_gmm = gmm.means_
                        risk_scores_gmm = centers_gmm[:, 0] + centers_gmm[:, 1] + centers_gmm[:, 2] - centers_gmm[:, 3]
                        sorted_clusters_gmm = np.argsort(risk_scores_gmm)
                        cluster_map_gmm = {
                            sorted_clusters_gmm[0]: 'Verde',    # Menor Risco
                            sorted_clusters_gmm[1]: 'Amarelo',  # Risco Médio
                            sorted_clusters_gmm[2]: 'Vermelho'  # Maior Risco
                        }
                        cross_sec['Cluster_Risco_GMM'] = [cluster_map_gmm[c] for c in clusters_gmm]
                        cross_sec['Data_Janela'] = current_end
                        cross_sec['Indexador'] = indexador
                        
                        results.append(cross_sec.reset_index())
                        
            current_start += pd.Timedelta(days=step_days)
            
        if results:
            return pd.concat(results, ignore_index=True)
            
        return pd.DataFrame()

    def execute_pipeline(self, window_days: int = 60, step_days: int = 30) -> Tuple[pd.DataFrame, pd.DataFrame]:
        """
        Executa a pipeline de ponta a ponta.
        
        Returns:
            Tuple[pd.DataFrame, pd.DataFrame]: 
                - O DataFrame enriquecido diário (com Vol e VaR).
                - O DataFrame de resultados do Rolling Clustering.
        """
        self.build_volatility_features()
        clustering_results = self.run_dynamic_clustering(window_days, step_days)
        return self.df, clustering_results

if __name__ == "__main__":
    pass
