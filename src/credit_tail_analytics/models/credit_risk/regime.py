import numpy as np
import pandas as pd
from sklearn.preprocessing import RobustScaler
from sklearn.cluster import KMeans
from hmmlearn.hmm import GaussianHMM
from typing import Dict, List, Optional
import logging

logger = logging.getLogger(__name__)

class RegimeClassifier:
    def __init__(self, individual_scaling: bool = True):
        self.individual_scaling = individual_scaling
        # clustering_models: {indexador_grupo: {'kmeans': ..., 'scaler_k': ...,
        #                                        'hmm': ..., 'scaler_h': ...}}
        self.clustering_models: Dict[str, Dict] = {}

    @staticmethod
    def _label_switching_correction(
        centers: np.ndarray,
        feature_names: List[str],
    ) -> Dict[int, str]:
        FEATURE_POLARITY: Dict[str, float] = {
            'Taxa_ZScore':            +1.0,  
            'Volatilidade_EGARCH':    +1.0,  
            'VaR_99':                 +1.0,  
            'Expected_Shortfall_99':  +1.0,  
            'Spread_Equivalente':     +1.0,  
            'Taxa_Ajustada_Prazo':    +1.0,  
            'Score_Liquidez':         -1.0,  
        }

        n_clusters = centers.shape[0]
        risk_scores = np.zeros(n_clusters)
        matched = False

        for i, feat in enumerate(feature_names):
            polarity = FEATURE_POLARITY.get(feat)
            if polarity is not None:
                risk_scores += centers[:, i] * polarity
                matched = True

        if not matched:
            logger.warning(
                f"[_label_switching_correction] Nenhuma feature reconhecida no dicionário "
                f"de polaridade: {feature_names}. Usando fallback (soma de todos os centróides)."
            )
            risk_scores = centers.sum(axis=1)

        sorted_ids  = np.argsort(risk_scores)
        label_names = ['Verde', 'Amarelo', 'Vermelho']
        return {int(sorted_ids[i]): label_names[i] for i in range(n_clusters)}

    def run_kmeans_regimes(
        self,
        df: pd.DataFrame,
        split_date: str,
        features: List[str],
    ) -> pd.DataFrame:
        logger.info(f"[K-Means] Features: {features}")

        missing_feats = [f for f in features if f not in df.columns]
        if missing_feats:
            raise ValueError(
                f"[K-Means] Features ausentes no DataFrame: {missing_feats}. "
                "Garanta que build_volatility_features() foi chamado antes."
            )

        subset_cols = features + ['Ticker', 'Data', 'Indexador_Grupo']
        df_clean    = df[subset_cols].dropna(subset=features).sort_values('Data')
        split_dt    = pd.to_datetime(split_date)

        train_df = df_clean[df_clean['Data'] <  split_dt]
        val_df   = df_clean[df_clean['Data'] >= split_dt]

        all_results: List[pd.DataFrame] = []

        for grupo, train_grupo in train_df.groupby('Indexador_Grupo'):
            if self.individual_scaling:
                scalers_k = {}
                X_train_list = []
                for ticker, df_t in train_grupo.groupby('Ticker'):
                    X_t = df_t[features].values
                    if len(X_t) > 0:
                        scaler_t = RobustScaler()
                        X_t_sc = scaler_t.fit_transform(X_t)
                        scalers_k[ticker] = scaler_t
                        X_train_list.append(X_t_sc)
                if not X_train_list:
                    logger.warning(f"[K-Means] Grupo '{grupo}': sem dados IS. Pulando.")
                    continue
                X_train_sc = np.vstack(X_train_list)
                global_scaler = RobustScaler().fit(train_grupo[features].values)
            else:
                X_train = train_grupo[features].values
                if len(X_train) < 3:
                    logger.warning(f"[K-Means] Grupo '{grupo}': dados insuficientes no IS. Pulando.")
                    continue
                global_scaler = RobustScaler()
                X_train_sc = global_scaler.fit_transform(X_train)
                scalers_k = None

            kmeans = KMeans(n_clusters=3, random_state=42, n_init=10)
            kmeans.fit(X_train_sc)

            cluster_map = self._label_switching_correction(
                kmeans.cluster_centers_, features
            )

            self.clustering_models.setdefault(grupo, {}).update({
                'kmeans':   kmeans,
                'scaler_k': global_scaler,
                'scalers_indiv_k': scalers_k,
                'feat_k':   features,
                'label_map_k': cluster_map,
            })

            val_grupo = val_df[val_df['Indexador_Grupo'] == grupo]
            if val_grupo.empty:
                logger.warning(f"[K-Means] Grupo '{grupo}': sem dados OOS.")
                continue

            all_results_group = []
            for ticker, df_t in val_grupo.groupby('Ticker'):
                X_t = df_t[features].values
                if self.individual_scaling:
                    scaler_t = scalers_k.get(ticker, global_scaler)
                    X_val_sc = scaler_t.transform(X_t)
                else:
                    X_val_sc = global_scaler.transform(X_t)
                    
                raw_labels = kmeans.predict(X_val_sc)
                distances = kmeans.transform(X_val_sc)

                try:
                    red_idx = next(k for k, v in cluster_map.items() if v == 'Vermelho')
                    sum_dists = distances.sum(axis=1)
                    prob_kmeans = 1.0 - (distances[:, red_idx] / np.maximum(sum_dists, 1e-9))
                except StopIteration:
                    prob_kmeans = np.nan

                resultado = df_t[['Ticker', 'Data', 'Indexador_Grupo']].copy()
                resultado['Cluster_KMeans'] = [cluster_map[c] for c in raw_labels]
                resultado['Prob_Crise_KMeans'] = prob_kmeans
                all_results_group.append(resultado)

            if all_results_group:
                df_group_oos = pd.concat(all_results_group, ignore_index=True)
                all_results.append(df_group_oos)
                logger.info(
                    f"[K-Means] Grupo '{grupo}': {len(X_train_sc)} obs IS, "
                    f"{len(df_group_oos)} obs OOS classificadas."
                )

        if not all_results:
            logger.warning("[K-Means] Nenhum resultado produzido.")
            return pd.DataFrame(columns=['Ticker', 'Data', 'Indexador_Grupo', 'Cluster_KMeans'])

        return pd.concat(all_results, ignore_index=True)

    def run_hmm_regimes(
        self,
        df: pd.DataFrame,
        split_date: str,
        features: List[str],
    ) -> pd.DataFrame:
        logger.info(f"[HMM] Features: {features}")

        missing_feats = [f for f in features if f not in df.columns]
        if missing_feats:
            raise ValueError(
                f"[HMM] Features ausentes no DataFrame: {missing_feats}. "
                "Garanta que build_volatility_features() foi chamado antes."
            )

        subset_cols = features + ['Ticker', 'Data', 'Indexador_Grupo']
        df_clean    = df[subset_cols].dropna(subset=features).sort_values(['Ticker', 'Data'])
        split_dt    = pd.to_datetime(split_date)

        train_df = df_clean[df_clean['Data'] < split_dt]
        val_df   = df_clean[df_clean['Data'] >= split_dt]

        all_results: List[pd.DataFrame] = []

        for grupo, train_grupo in train_df.groupby('Indexador_Grupo'):
            
            X_train_list = []
            lengths = []
            
            if self.individual_scaling:
                scalers_h = {}
                for ticker, df_t in train_grupo.sort_values(['Ticker', 'Data']).groupby('Ticker'):
                    X_t = df_t[features].values
                    if len(X_t) > 0:
                        scaler_t = RobustScaler()
                        X_t_sc = scaler_t.fit_transform(X_t)
                        scalers_h[ticker] = scaler_t
                        X_train_list.append(X_t_sc)
                        lengths.append(len(X_t))
                global_scaler = RobustScaler().fit(train_grupo[features].values)
            else:
                for ticker, df_t in train_grupo.sort_values(['Ticker', 'Data']).groupby('Ticker'):
                    X_t = df_t[features].values
                    if len(X_t) > 0:
                        X_train_list.append(X_t)
                        lengths.append(len(X_t))
                global_scaler = RobustScaler()
                scalers_h = None
            
            if not X_train_list:
                logger.warning(f"[HMM] Grupo '{grupo}': sem dados IS. Pulando.")
                continue
                
            if self.individual_scaling:
                X_train_sc = np.vstack(X_train_list)
            else:
                X_train_arr = np.vstack(X_train_list)
                if len(X_train_arr) < 3:
                    logger.warning(f"[HMM] Grupo '{grupo}': dados insuficientes no IS. Pulando.")
                    continue
                X_train_sc = global_scaler.fit_transform(X_train_arr)
            
            try:
                hmm = GaussianHMM(
                    n_components=3,
                    covariance_type='diag',
                    n_iter=100,
                    random_state=42,
                )
                hmm.fit(X_train_sc, lengths)
                
                cluster_map = self._label_switching_correction(hmm.means_, features)
                vermelho_id = next((k for k, v in cluster_map.items() if v == 'Vermelho'), 2)
                
            except Exception as exc:
                logger.warning(f"[HMM] Grupo '{grupo}': falha na convergência global — {exc}")
                continue

            try:
                states_is = hmm.predict(X_train_sc, lengths)
                n_states   = hmm.n_components
                trans_counts = np.zeros((n_states, n_states))

                pos = 0
                for length in lengths:
                    seq = states_is[pos : pos + length]
                    for t in range(len(seq) - 1):
                        trans_counts[seq[t], seq[t + 1]] += 1
                    pos += length

                trans_counts += 1e-6
                hmm.transmat_ = trans_counts / trans_counts.sum(axis=1, keepdims=True)

                logger.debug(
                    f"[HMM] Grupo '{grupo}': transmat_ recalibrada sem bordas inter-ticker.\n"
                    f"{np.round(hmm.transmat_, 3)}"
                )
            except Exception as exc_tm:
                logger.warning(
                    f"[HMM] Grupo '{grupo}': falha na recalibração de transmat_ — "
                    f"{exc_tm}. Mantendo transmat_ original do fit()."
                )

            self.clustering_models.setdefault(grupo, {}).update({
                'hmm':   hmm,
                'scaler_h': global_scaler,
                'scalers_indiv_h': scalers_h if self.individual_scaling else None,
                'feat_h':   features,
                'label_map_h': cluster_map,
            })


            val_grupo = val_df[val_df['Indexador_Grupo'] == grupo]
            if val_grupo.empty:
                logger.warning(f"[HMM] Grupo '{grupo}': sem dados OOS.")
                continue
                
            for ticker, df_t_oos in val_grupo.sort_values(['Ticker', 'Data']).groupby('Ticker'):
                result_base = df_t_oos[['Ticker', 'Data', 'Indexador_Grupo']].copy()
                
                df_t_is = train_df[(train_df['Indexador_Grupo'] == grupo) & (train_df['Ticker'] == ticker)]
                
                df_t_full = pd.concat([df_t_is, df_t_oos]).sort_values('Data')
                X_full = df_t_full[features].values
                
                if len(df_t_oos) == 0:
                    continue
                    
                try:
                    if self.individual_scaling:
                        scaler_t = scalers_h.get(ticker, global_scaler)
                        X_full_sc = scaler_t.transform(X_full)
                    else:
                        X_full_sc = global_scaler.transform(X_full)
                        
                    raw_states_full = hmm.predict(X_full_sc)
                    proba_mat_full  = hmm.predict_proba(X_full_sc)
                    
                    n_oos = len(df_t_oos)
                    raw_states = raw_states_full[-n_oos:]
                    proba_mat  = proba_mat_full[-n_oos:]
                    
                    result_base['Cluster_HMM'] = [cluster_map[s] for s in raw_states]
                    result_base['Prob_Crise_HMM'] = proba_mat[:, vermelho_id]
                except Exception as exc:
                    result_base['Cluster_HMM']    = 'Inconclusivo'
                    result_base['Prob_Crise_HMM'] = np.nan
                    
                all_results.append(result_base)

            logger.info(f"[HMM] Grupo '{grupo}': Treinado com {len(X_train_sc)} obs. "
                        f"Predito {len(val_grupo)} obs OOS.")

        if not all_results:
            logger.warning("[HMM] Nenhum resultado produzido.")
            return pd.DataFrame(
                columns=['Ticker', 'Data', 'Indexador_Grupo', 'Cluster_HMM', 'Prob_Crise_HMM']
            )

        df_out = pd.concat(all_results, ignore_index=True)
        n_inc  = (df_out['Cluster_HMM'] == 'Inconclusivo').sum()
        logger.info(
            f"[HMM] Concluído: {len(df_out)} obs OOS classificadas "
            f"({n_inc} Inconclusivo)."
        )
        return df_out
