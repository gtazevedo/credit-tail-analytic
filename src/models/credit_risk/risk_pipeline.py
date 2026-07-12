import numpy as np
import pandas as pd
import os
import scipy.stats as stats
from arch import arch_model
from sklearn.preprocessing import RobustScaler
from sklearn.cluster import KMeans
from sklearn.mixture import GaussianMixture
from typing import Dict, List, Tuple, Union, Optional
import warnings
import logging

warnings.filterwarnings("ignore", category=FutureWarning)
logger = logging.getLogger(__name__)

class CreditRiskEngine:
    """   
    Responsável por realizar a ingestão e feature engineering de dados de debêntures,
    estimar a volatilidade via AR(1)-EGARCH(1,1)-t, calcular o VaR e classificar
    o risco de cauda utilizando K-Means/GMM, com separação estrita de Treino/Validação.
    """

    def __init__(self, df: pd.DataFrame):
        self.df = df.copy()
        self.volume_map: Dict[str, int] = {
            'Até 1MM': 1,
            'Entre 1MM e 5MM': 2,
            'Superior a 5MM': 3
        }
        self.clustering_models = {}
        
        self._validate_input()
        self._feature_engineering()

    def _validate_input(self) -> None:
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
        self.df['Score_Liquidez'] = self.df['Faixa_Volume_ANBIMA'].map(self.volume_map).fillna(1).astype(int)

        self.df['Log_Retorno'] = self.df.groupby('Ticker')['PU'].transform(
            lambda x: np.log(x / x.shift(1))
        )
        
        medias_taxa = self.df.groupby('Ticker')['Taxa_Ativo'].transform('mean')
        is_di = self.df['Indexador'] == 'DI'
        is_percent = medias_taxa > 30
        self.df.loc[is_di & is_percent, 'Indexador'] = 'DI_Percentual'
        self.df.loc[is_di & ~is_percent, 'Indexador'] = 'DI_Spread'

        logger.info("Carregando Dados Macroeconômicos (dados/macro_data.csv)...")
        try:
            base_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
            macro_path = os.path.join(base_dir, "dados", "macro_data.csv")
            
            df_macro = pd.read_csv(macro_path)
            df_macro['Data'] = pd.to_datetime(df_macro['Data'])
            
            self.df = pd.merge(self.df, df_macro, on='Data', how='left')
            # Preencher possíveis valores faltantes na ponta final
            self.df['CDI_Anual'] = self.df['CDI_Anual'].ffill()
            self.df['IPCA_Mensal'] = self.df['IPCA_Mensal'].ffill()
            self.df['IGPM_Mensal'] = self.df['IGPM_Mensal'].ffill()
        except Exception as e:
            logger.warning(f"Falha ao carregar dados macroeconômicos. Erro: {e}")
            self.df['CDI_Anual'] = 10.4
            self.df['IPCA_Mensal'] = 0.5
            self.df['IGPM_Mensal'] = 0.5

        def calc_spread(row):
            idx = str(row['Indexador']).upper()
            taxa = row['Taxa_Ativo']
            cdi = row['CDI_Anual']
            if pd.isna(taxa) or pd.isna(cdi): return np.nan
            
            if idx in ['DI_SPREAD', 'IPCA', 'IGPM']:
                return taxa
            elif idx == 'DI_PERCENTUAL':
                # Convenção de Juros Compostos (BACEN/B3) para % do DI
                fator_diario_cdi = (1 + cdi / 100.0)**(1/252)
                fator_diario_titulo = (fator_diario_cdi - 1) * (taxa / 100.0) + 1
                yield_anualizado = fator_diario_titulo**252 - 1
                return yield_anualizado * 100.0 - cdi
            else:
                return taxa - cdi
                
        self.df['Spread_Equivalente'] = self.df.apply(calc_spread, axis=1)

        du_seguro = np.maximum(self.df['DU_Vencimento'], 2)
        self.df['Taxa_Ajustada_Prazo'] = self.df['Spread_Equivalente'] / np.log(du_seguro)

        self.df['Spread_Ffill'] = self.df.groupby('Ticker')['Spread_Equivalente'].ffill()
        def calc_zscore(x):
            r = x.rolling(window=60, min_periods=10)
            return (x - r.mean()) / r.std().replace(0, np.nan)
            
        self.df['Taxa_ZScore'] = self.df.groupby('Ticker')['Spread_Ffill'].transform(calc_zscore).fillna(0)
        self.df['Delta_Spread'] = self.df.groupby('Ticker')['Spread_Ffill'].transform(lambda x: x.diff())
        
    def _egarch_var(self, group_df: pd.DataFrame, split_date: str, alpha: float = 0.01) -> Tuple[pd.Series, pd.Series]:
        returns = group_df['Delta_Spread']
        datas = group_df['Data']
        
        vol_series = pd.Series(np.nan, index=returns.index)
        var_series = pd.Series(np.nan, index=returns.index)
        
        valid_idx = returns.dropna().index
        if len(valid_idx) < 30:
            return vol_series, var_series
            
        returns_scaled = returns.loc[valid_idx] * 100
        datas_valid = datas.loc[valid_idx]
        
        split_dt = pd.to_datetime(split_date)
        train_mask = datas_valid < split_dt
        split_idx = train_mask.sum()
        
        if split_idx < 25:
            return vol_series, var_series
            
        try:
            model = arch_model(
                returns_scaled, 
                mean='AR', lags=1, 
                vol='EGARCH', p=1, o=1, q=1,
                dist='t',
                rescale=False
            )
            
            res_is = model.fit(last_obs=split_idx, disp='off', show_warning=False)
            res_oos = model.fix(res_is.params)
            
            cond_vol = res_oos.conditional_volatility
            cond_mean = res_oos.conditional_mean
            if isinstance(cond_mean, pd.DataFrame): 
                cond_mean = cond_mean.iloc[:, 0]
            
            nu = res_is.params.get('nu', 5.0)
            q_alpha = model.distribution.ppf(1 - alpha, nu)
            var_99 = cond_mean + cond_vol * q_alpha
            
            vol_series.loc[valid_idx] = cond_vol / 100
            var_series.loc[valid_idx] = var_99 / 100
            
        except Exception:
            pass
            
        return vol_series, var_series

    def _kupiec_pof_test(self, retornos: Union[pd.Series, np.ndarray], var_limits: Union[pd.Series, np.ndarray], nivel_confianca: float = 0.99) -> float:
        ret = np.asarray(retornos)
        var = np.asarray(var_limits)
        
        mask = ~np.isnan(ret) & ~np.isnan(var)
        ret = ret[mask]
        var = var[mask]
        
        n = len(ret)
        if n == 0: return np.nan
            
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
                if den <= 0 or num <= 0: return np.nan
                lr_stat = -2 * np.log(num / den)
                
        p_value = 1.0 - stats.chi2.cdf(lr_stat, df=1)
        return p_value

    def build_volatility_features(self, split_date: str) -> None:
        self.df['Volatilidade_EGARCH'] = np.nan
        self.df['VaR_99'] = np.nan
        
        for ticker, group in self.df.groupby('Ticker'):
            vol, var = self._egarch_var(group[['Data', 'Delta_Spread']], split_date)
            self.df.loc[group.index, 'Volatilidade_EGARCH'] = vol
            self.df.loc[group.index, 'VaR_99'] = var

    def run_clustering_split(self, split_date: str) -> pd.DataFrame:
        subset_cols = ['Taxa_Ajustada_Prazo', 'Volatilidade_EGARCH', 'Taxa_ZScore', 'Score_Liquidez']
        if 'Range_Taxa_Intraday' in self.df.columns:
            subset_cols.append('Range_Taxa_Intraday')
            
        df_sorted = self.df.sort_values('Data').dropna(subset=subset_cols)
        if df_sorted.empty: return pd.DataFrame()
        
        split_dt = pd.to_datetime(split_date)
        train_df = df_sorted[df_sorted['Data'] < split_dt]
        val_df = df_sorted[df_sorted['Data'] >= split_dt]
        
        # 1. TREINO: Fit nos dados In-Sample
        if not train_df.empty:
            agg_dict = {
                'Taxa_Ajustada_Prazo': 'mean',
                'Volatilidade_EGARCH': 'mean',
                'Taxa_ZScore': 'mean',
                'Score_Liquidez': lambda x: pd.Series(x).mode().iloc[0] if not pd.Series(x).mode().empty else np.nan
            }
            if 'Range_Taxa_Intraday' in train_df.columns:
                agg_dict['Range_Taxa_Intraday'] = 'mean'
                
            cross_sec_train = train_df.groupby('Ticker').agg(agg_dict).dropna()
            
            if len(cross_sec_train) >= 3:
                scaler = RobustScaler()
                X_train_scaled = scaler.fit_transform(cross_sec_train)
                
                kmeans = KMeans(n_clusters=3, random_state=42, n_init=10)
                kmeans.fit(X_train_scaled)
                
                gmm = GaussianMixture(n_components=3, random_state=42, n_init=10)
                gmm.fit(X_train_scaled)
                
                self.clustering_models['scaler'] = scaler
                self.clustering_models['kmeans'] = kmeans
                self.clustering_models['gmm'] = gmm
                
        # 2. VALIDAÇÃO: Predict Out-of-Sample mensalmente para Tracking Histórico
        results = []
        if val_df.empty or 'scaler' not in self.clustering_models:
            return pd.DataFrame()
            
        val_df = val_df.copy()
        val_df['Mes_Ano'] = val_df['Data'].dt.to_period('M')
        
        for mes, cohort_df in val_df.groupby('Mes_Ano'):
            agg_dict_val = {
                'Taxa_Ajustada_Prazo': 'mean',
                'Volatilidade_EGARCH': 'mean',
                'Taxa_ZScore': 'mean',
                'Score_Liquidez': lambda x: pd.Series(x).mode().iloc[0] if not pd.Series(x).mode().empty else np.nan
            }
            if 'Range_Taxa_Intraday' in cohort_df.columns:
                agg_dict_val['Range_Taxa_Intraday'] = 'mean'
                
            cross_sec = cohort_df.groupby('Ticker').agg(agg_dict_val).dropna()
            
            if len(cross_sec) > 0:
                scaler = self.clustering_models['scaler']
                kmeans = self.clustering_models['kmeans']
                gmm = self.clustering_models['gmm']
                
                X_val_scaled = scaler.transform(cross_sec)
                
                clusters_kmeans = kmeans.predict(X_val_scaled)
                clusters_gmm = gmm.predict(X_val_scaled)
                
                # Mapeamento dinâmico dos centróides (Verde/Amarelo/Vermelho)
                centers_kmeans = kmeans.cluster_centers_
                # Index 0: Taxa, 1: Volatilidade, 2: ZScore, 3: Liquidez, 4: Range Intraday (opcional)
                risk_scores_kmeans = centers_kmeans[:, 0] + centers_kmeans[:, 1] + centers_kmeans[:, 2] - centers_kmeans[:, 3]
                if centers_kmeans.shape[1] > 4:
                    risk_scores_kmeans += centers_kmeans[:, 4]
                sorted_clusters_kmeans = np.argsort(risk_scores_kmeans)
                cluster_map_kmeans = {
                    sorted_clusters_kmeans[0]: 'Verde',
                    sorted_clusters_kmeans[1]: 'Amarelo',
                    sorted_clusters_kmeans[2]: 'Vermelho'
                }
                
                centers_gmm = gmm.means_
                risk_scores_gmm = centers_gmm[:, 0] + centers_gmm[:, 1] + centers_gmm[:, 2] - centers_gmm[:, 3]
                if centers_gmm.shape[1] > 4:
                    risk_scores_gmm += centers_gmm[:, 4]
                sorted_clusters_gmm = np.argsort(risk_scores_gmm)
                cluster_map_gmm = {
                    sorted_clusters_gmm[0]: 'Verde',
                    sorted_clusters_gmm[1]: 'Amarelo',
                    sorted_clusters_gmm[2]: 'Vermelho'
                }
                
                cross_sec['Cluster_Risco_KMeans'] = [cluster_map_kmeans[c] for c in clusters_kmeans]
                cross_sec['Cluster_Risco_GMM'] = [cluster_map_gmm[c] for c in clusters_gmm]
                cross_sec['Data_Janela'] = mes.to_timestamp(how='end')
                
                results.append(cross_sec.reset_index())
                
        if results:
            return pd.concat(results, ignore_index=True)
            
        return pd.DataFrame()

    def execute_pipeline(self, split_date: str = '2023-01-01') -> Tuple[pd.DataFrame, pd.DataFrame]:
        self.build_volatility_features(split_date)
        clustering_results = self.run_clustering_split(split_date)
        return self.df, clustering_results

