import pandas as pd
import numpy as np
import os
import itertools
from sklearn.preprocessing import RobustScaler
from sklearn.covariance import EllipticEnvelope
from sklearn.metrics import silhouette_score, davies_bouldin_score
from scipy.stats import chi2
import logging

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class FeatureSelector:
    """
    Motor quantitativo para selecionar o melhor subconjunto de variáveis para o modelo MCD.
    Métricas avaliadas:
    - Silhouette Score (Coesão vs Separação inter-cluster)
    - Davies-Bouldin Index (Razão de dispersão intra-cluster vs inter-cluster)
    - Contagion Variance (Estabilidade temporal da proporção de outliers no In-Sample)
    """
    
    def __init__(self, df: pd.DataFrame, candidate_features: list, split_date: str = '2023-01-01'):
        self.df = df
        self.candidate_features = candidate_features
        self.split_date = pd.to_datetime(split_date)
        
    def _run_mcd_for_subset(self, features_subset: list) -> pd.DataFrame:
        subset_cols = list(features_subset) + ['Classe_Ativo', 'Data', 'Ticker']
        df_sorted = self.df.sort_values('Data').dropna(subset=list(features_subset) + ['Classe_Ativo'])
        
        if df_sorted.empty:
            return pd.DataFrame()
            
        train_df = df_sorted[df_sorted['Data'] < self.split_date]
        if train_df.empty:
            return pd.DataFrame()
            
        # Agrega dados para o in-sample
        agg_dict = {f: 'mean' for f in features_subset}
        agg_dict['Classe_Ativo'] = 'first'
        
        cross_sec_train = train_df.groupby('Ticker').agg(agg_dict).dropna()
        
        models = {}
        for classe, df_classe in cross_sec_train.groupby('Classe_Ativo'):
            X = df_classe[list(features_subset)]
            if len(X) >= 3:
                scaler = RobustScaler()
                X_scaled = scaler.fit_transform(X)
                mcd = EllipticEnvelope(random_state=42, support_fraction=0.95)
                try:
                    mcd.fit(X_scaled)
                    models[classe] = {'scaler': scaler, 'mcd': mcd}
                except Exception:
                    pass
                    
        # Predição In-Sample (Janela Mensal) para medir Contágio Temporal
        results = []
        train_df_monthly = train_df.copy()
        train_df_monthly['Mes_Ano'] = train_df_monthly['Data'].dt.to_period('M')
        
        for mes, cohort_df in train_df_monthly.groupby('Mes_Ano'):
            cross_sec = cohort_df.groupby('Ticker').agg(agg_dict).dropna()
            if cross_sec.empty: continue
            
            for classe, df_classe in cross_sec.groupby('Classe_Ativo'):
                if classe not in models: continue
                
                X_val = df_classe[list(features_subset)]
                scaler = models[classe]['scaler']
                mcd = models[classe]['mcd']
                
                X_val_scaled = scaler.transform(X_val)
                dist_mahalanobis = mcd.mahalanobis(X_val_scaled)
                
                df_chi2 = len(features_subset)
                thresh_vermelho = chi2.ppf(0.99, df=df_chi2)
                
                centroide_is = mcd.location_
                sinal_direcao = X_val_scaled.sum(axis=1)
                sinal_referencia = centroide_is.sum()
                
                is_vermelho = (dist_mahalanobis > thresh_vermelho) & (sinal_direcao > sinal_referencia)
                
                res = df_classe.copy()
                res['Is_Vermelho'] = is_vermelho.astype(int)
                res['Data_Janela'] = mes.to_timestamp(how='end')
                results.append(res)
                
        if results:
            return pd.concat(results, ignore_index=False)
        return pd.DataFrame()

    def evaluate_subsets(self, min_features=2, max_features=None):
        if max_features is None:
            max_features = len(self.candidate_features)
            
        all_combinations = []
        for r in range(min_features, max_features + 1):
            all_combinations.extend(list(itertools.combinations(self.candidate_features, r)))
            
        results_list = []
        total = len(all_combinations)
        
        logger.info(f"Iniciando Feature Selection. Testando {total} combinações.")
        
        for i, subset in enumerate(all_combinations, 1):
            subset = list(subset)
            logger.info(f"Testando combinação {i}/{total}: {subset}")
            
            res_df = self._run_mcd_for_subset(subset)
            
            if res_df.empty:
                continue
                
            # Métricas de Cluster In-Sample Agregadas
            agg_dict = {f: 'mean' for f in subset}
            agg_dict['Is_Vermelho'] = 'max'
            
            # Vamos avaliar a qualidade geométrica no cross-section médio do in-sample
            cross_mean = res_df.groupby(res_df.index).agg(agg_dict).dropna()
            
            # Precisamos de pelo menos duas classes para Silhouette/DB
            n_clusters = cross_mean['Is_Vermelho'].nunique()
            if n_clusters < 2 or len(cross_mean) < 10:
                continue
                
            X = cross_mean[subset].values
            scaler = RobustScaler()
            X_scaled = scaler.fit_transform(X)
            labels = cross_mean['Is_Vermelho'].values
            
            sil_score = silhouette_score(X_scaled, labels)
            db_score = davies_bouldin_score(X_scaled, labels)
            
            # Estabilidade Sistêmica (Contágio no tempo)
            contagio_ts = res_df.groupby('Data_Janela')['Is_Vermelho'].mean()
            contagio_var = contagio_ts.var() if len(contagio_ts) > 2 else np.nan
            
            results_list.append({
                'Features': ", ".join(subset),
                'Num_Features': len(subset),
                'Silhouette_Score': sil_score,  # Maior melhor
                'Davies_Bouldin': db_score,     # Menor melhor
                'Contagion_Variance': contagio_var # Menor melhor
            })
            
        results_df = pd.DataFrame(results_list)
        # Cria um Score global para rankear (Normaliza as 3 métricas)
        if not results_df.empty:
            sil_norm = (results_df['Silhouette_Score'] - results_df['Silhouette_Score'].min()) / (results_df['Silhouette_Score'].max() - results_df['Silhouette_Score'].min() + 1e-9)
            db_norm = 1.0 - (results_df['Davies_Bouldin'] - results_df['Davies_Bouldin'].min()) / (results_df['Davies_Bouldin'].max() - results_df['Davies_Bouldin'].min() + 1e-9)
            var_norm = 1.0 - (results_df['Contagion_Variance'] - results_df['Contagion_Variance'].min()) / (results_df['Contagion_Variance'].max() - results_df['Contagion_Variance'].min() + 1e-9)
            
            results_df['Global_Score'] = (sil_norm * 0.4) + (db_norm * 0.4) + (var_norm * 0.2)
            results_df = results_df.sort_values('Global_Score', ascending=False).reset_index(drop=True)
            
        return results_df

if __name__ == '__main__':
    from src.models.credit_risk.risk_pipeline import CreditRiskEngine
    import warnings
    warnings.filterwarnings('ignore')
    
    logger.info("Carregando bases para Feature Selection...")
    base_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
    
    hist = pd.read_csv(os.path.join(base_dir, 'dados', 'dataset_credito_consolidado.csv'))
    cad = pd.read_csv(os.path.join(base_dir, 'dados', 'cadastro_debentures.csv'))
    
    # Merge
    df = pd.merge(hist, cad[['Ticker', 'Indexador', 'Data_Vencimento']], on='Ticker', how='left')
    
    df['Data'] = pd.to_datetime(df['Data'])
    df['Data_Vencimento'] = pd.to_datetime(df['Data_Vencimento'])
    df['DU_Vencimento'] = (df['Data_Vencimento'] - df['Data']).dt.days
    
    # Processa pipeline base
    engine = CreditRiskEngine(df.dropna(subset=['Data', 'Ticker', 'Indexador', 'PU', 'Taxa_Ativo', 'DU_Vencimento', 'Faixa_Volume_ANBIMA']))
    engine.build_volatility_features(split_date='2023-01-01')
    
    # Executa seleção
    candidate_features = [
        'Taxa_Idiosincratica',
        'ES_99',
        'Taxa_ZScore',
        'Volatilidade_GARCH',
        'Score_Liquidez',
        'Taxa_Ajustada_Prazo'
    ]
    
    selector = FeatureSelector(engine.df, candidate_features)
    ranking = selector.evaluate_subsets(min_features=2, max_features=5)
    
    out_path = os.path.join(base_dir, 'dados', 'feature_selection_ranking.csv')
    ranking.to_csv(out_path, index=False)
    
    logger.info(f"Ranking salvo em {out_path}.")
    print("\nTop 5 Conjuntos de Features:")
    print(ranking.head(5).to_string())
