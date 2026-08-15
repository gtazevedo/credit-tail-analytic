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

    @staticmethod
    def _winsorize_group(
        X_train: np.ndarray,
        X_val: np.ndarray,
        lower_pct: float = 1.0,
        upper_pct: float = 99.0,
    ):
        """
        Winsoriza as features de treino e validação com os limites calculados
        exclusivamente nos dados IS (X_train). Aplicação ao OOS não introduz
        look-ahead bias pois os limites foram determinados no passado.

        Motivação: outliers extremos de volatilidade (ex: HAPV12 com Volatilidade_EGARCH
        = 64, quando a mediana do mercado é ~0.3) sequestram o centroide 'Vermelho' do
        K-Means e do HMM. Sem winsorizção, QUALQUER ativo com volatilidade menor que o
        outlier passa a ser classificado como Verde por comparação, mesmo que seja
        genuinamente estressado (ex: Light S.A. com Taxa_ZScore = 7.6 antes da RJ).

        Parâmetros
        ----------
        X_train    : np.ndarray — dados IS (N_train × F)
        X_val      : np.ndarray — dados OOS (N_val × F)
        lower_pct  : float      — percentil inferior (padrão P1)
        upper_pct  : float      — percentil superior (padrão P99)

        Retorna
        -------
        (X_train_w, X_val_w, lower_bounds, upper_bounds)
        """
        lower_bounds = np.percentile(X_train, lower_pct, axis=0)
        upper_bounds = np.percentile(X_train, upper_pct, axis=0)
        X_train_w = np.clip(X_train, lower_bounds, upper_bounds)
        X_val_w   = np.clip(X_val,   lower_bounds, upper_bounds)
        return X_train_w, X_val_w, lower_bounds, upper_bounds


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
        val_df   = df_clean  # Modificado: Mantém histórico In-Sample para otimização do Ensemble

        all_results: List[pd.DataFrame] = []

        for grupo, train_grupo in train_df.groupby('Indexador_Grupo'):
            val_grupo_df = val_df[val_df['Indexador_Grupo'] == grupo]

            X_train_raw = train_grupo[features].values
            X_val_raw   = val_grupo_df[features].values if not val_grupo_df.empty else np.empty((0, len(features)))

            if len(X_train_raw) < 3:
                logger.warning(f"[K-Means] Grupo '{grupo}': dados insuficientes no IS. Pulando.")
                continue

            # Winsorização P1/P99 com limites calculados IS — evita que outliers extremos
            # de volatilidade (ex: HAPV12, Vol=64) sequestrem o centroide Vermelho
            if len(X_val_raw) > 0:
                X_train_w, X_val_w, lo, hi = self._winsorize_group(X_train_raw, X_val_raw)
            else:
                lo = np.percentile(X_train_raw, 1, axis=0)
                hi = np.percentile(X_train_raw, 99, axis=0)
                X_train_w = np.clip(X_train_raw, lo, hi)
                X_val_w   = X_val_raw

            # Reconstri o DataFrame de treino winsorizado
            train_grupo_w = train_grupo.copy()
            train_grupo_w[features] = X_train_w
            
            # Treina o global_scaler primeiro para servir de referência (piso de variância)
            global_scaler = RobustScaler()
            global_scaler.fit(X_train_w)
            global_scale = global_scaler.scale_

            if self.individual_scaling:
                scalers_k     = {}
                X_train_list  = []
                for ticker, df_t in train_grupo_w.groupby('Ticker'):
                    X_t = df_t[features].values
                    if len(X_t) > 0:
                        scaler_t = RobustScaler()
                        scaler_t.fit(X_t)
                        # Aplica o piso de variância: IQR individual não pode ser < 10% do IQR global
                        scaler_t.scale_ = np.maximum(scaler_t.scale_, global_scale * 0.10)
                        
                        X_t_sc = scaler_t.transform(X_t)
                        # Previne explosões residuais extremas
                        X_t_sc = np.clip(X_t_sc, -10.0, 10.0)
                        scalers_k[ticker] = scaler_t
                        X_train_list.append(X_t_sc)
                if not X_train_list:
                    logger.warning(f"[K-Means] Grupo '{grupo}': sem dados IS. Pulando.")
                    continue
                X_train_sc    = np.vstack(X_train_list)
            else:
                X_train_sc    = global_scaler.transform(X_train_w)
                X_train_sc    = np.clip(X_train_sc, -10.0, 10.0)
                scalers_k     = None

            kmeans = KMeans(n_clusters=3, random_state=42, n_init=10)
            kmeans.fit(X_train_sc)

            cluster_map = self._label_switching_correction(kmeans.cluster_centers_, features)

            # Log dos percentis winsorisados para inspecção
            logger.info(
                f"[K-Means] Grupo '{grupo}': winsorização P1/P99 IS | "
                f"Vol_EGARCH max pós-wins: {X_train_w[:, features.index('Volatilidade_EGARCH')].max():.4f}"
                if 'Volatilidade_EGARCH' in features else
                f"[K-Means] Grupo '{grupo}': winsorização aplicada"
            )

            self.clustering_models.setdefault(grupo, {}).update({
                'kmeans':            kmeans,
                'scaler_k':          global_scaler,
                'scalers_indiv_k':   scalers_k,
                'feat_k':            features,
                'label_map_k':       cluster_map,
                'wins_lo_k':         lo,
                'wins_hi_k':         hi,
            })

            if val_grupo_df.empty:
                logger.warning(f"[K-Means] Grupo '{grupo}': sem dados OOS.")
                continue

            all_results_group = []
            for ticker, df_t in val_grupo_df.groupby('Ticker'):
                # Aplica os mesmos limites IS ao OOS (sem look-ahead)
                X_t_raw = df_t[features].values
                X_t_w   = np.clip(X_t_raw, lo, hi)

                if self.individual_scaling:
                    scaler_t = scalers_k.get(ticker, global_scaler)
                    X_val_sc = scaler_t.transform(X_t_w)
                else:
                    X_val_sc = global_scaler.transform(X_t_w)

                X_val_sc = np.clip(X_val_sc, -10.0, 10.0)

                raw_labels = kmeans.predict(X_val_sc)
                distances  = kmeans.transform(X_val_sc)

                try:
                    red_idx = next(k for k, v in cluster_map.items() if v == 'Vermelho')
                    sum_dists = distances.sum(axis=1)
                    prob_kmeans = 1.0 - (distances[:, red_idx] / np.maximum(sum_dists, 1e-9))
                except StopIteration:
                    prob_kmeans = np.nan

                resultado = df_t[['Ticker', 'Data', 'Indexador_Grupo']].copy()
                resultado['Cluster_KMeans']     = [cluster_map[c] for c in raw_labels]
                resultado['Prob_Crise_KMeans']  = prob_kmeans
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

        train_df = df_clean[df_clean['Data'] <  split_dt]
        val_df   = df_clean  # Modificado: Mantém histórico In-Sample para otimização do Ensemble

        all_results: List[pd.DataFrame] = []

        for grupo, train_grupo in train_df.groupby('Indexador_Grupo'):
            val_grupo_df = val_df[val_df['Indexador_Grupo'] == grupo]

            X_train_raw = train_grupo.sort_values(['Ticker', 'Data'])[features].values
            X_val_raw   = val_grupo_df[features].values if not val_grupo_df.empty else np.empty((0, len(features)))

            if len(X_train_raw) < 3:
                logger.warning(f"[HMM] Grupo '{grupo}': dados insuficientes no IS. Pulando.")
                continue

            # Winsorização P1/P99 com limites IS — mesma razão do KMeans
            if len(X_val_raw) > 0:
                X_train_w_full, _, lo, hi = self._winsorize_group(X_train_raw, X_val_raw)
            else:
                lo = np.percentile(X_train_raw, 1, axis=0)
                hi = np.percentile(X_train_raw, 99, axis=0)
                X_train_w_full = np.clip(X_train_raw, lo, hi)

            # Reconstrói o DataFrame winsorizado para iteração por ticker
            train_grupo_sorted = train_grupo.sort_values(['Ticker', 'Data']).copy()
            train_grupo_sorted[features] = X_train_w_full
            
            # Treina o global_scaler primeiro para servir de referência (piso de variância)
            global_scaler = RobustScaler()
            global_scaler.fit(X_train_w_full)
            global_scale = global_scaler.scale_

            X_train_list = []
            lengths      = []

            if self.individual_scaling:
                scalers_h = {}
                for ticker, df_t in train_grupo_sorted.groupby('Ticker'):
                    X_t = df_t[features].values
                    if len(X_t) > 0:
                        scaler_t = RobustScaler()
                        scaler_t.fit(X_t)
                        # Imposição de piso geométrico: O IQR individual deve corresponder a no mínimo 10% do IQR global.
                        # Isso previne a degeneração de variância (divisão por zero) em ativos estruturalmente ilíquidos.
                        scaler_t.scale_ = np.maximum(scaler_t.scale_, global_scale * 0.10)
                        
                        X_t_sc   = scaler_t.transform(X_t)
                        X_t_sc   = np.clip(X_t_sc, -10.0, 10.0)
                        scalers_h[ticker] = scaler_t
                        X_train_list.append(X_t_sc)
                        lengths.append(len(X_t))
            else:
                for ticker, df_t in train_grupo_sorted.groupby('Ticker'):
                    X_t = df_t[features].values
                    if len(X_t) > 0:
                        X_train_list.append(X_t)
                        lengths.append(len(X_t))
                scalers_h = None

            if not X_train_list:
                logger.warning(f"[HMM] Grupo '{grupo}': sem dados IS. Pulando.")
                continue

            if self.individual_scaling:
                X_train_sc = np.vstack(X_train_list)
            else:
                X_train_arr = np.vstack(X_train_list)
                X_train_sc  = global_scaler.fit_transform(X_train_arr)
                X_train_sc  = np.clip(X_train_sc, -10.0, 10.0)

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

                # Suavização de Laplace (Prior) aplicada à matriz de transição empírica.
                # Mitiga o problema de estados absorventes causados por ausência de transições na amostra de treinamento.
                trans_counts += 1.0  
                hmm.transmat_ = trans_counts / trans_counts.sum(axis=1, keepdims=True)
                
                # Imposição de um limiar mínimo de probabilidade de transição (1%) para evitar dependência excessiva do estado anterior.
                hmm.transmat_ = np.maximum(hmm.transmat_, 0.01)
                hmm.transmat_ = hmm.transmat_ / hmm.transmat_.sum(axis=1, keepdims=True)

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
                'hmm':              hmm,
                'scaler_h':         global_scaler,
                'scalers_indiv_h':  scalers_h if self.individual_scaling else None,
                'feat_h':           features,
                'label_map_h':      cluster_map,
                'wins_lo_h':        lo,
                'wins_hi_h':        hi,
            })

            if val_grupo_df.empty:
                logger.warning(f"[HMM] Grupo '{grupo}': sem dados OOS.")
                continue

            n_oos_total = 0
            for ticker, df_t_oos in val_grupo_df.sort_values(['Ticker', 'Data']).groupby('Ticker'):
                result_base = df_t_oos[['Ticker', 'Data', 'Indexador_Grupo']].copy()

                df_t_is   = train_df[(train_df['Indexador_Grupo'] == grupo) & (train_df['Ticker'] == ticker)]
                df_t_full = pd.concat([df_t_is, df_t_oos]).sort_values('Data')

                # Aplica winsorização IS ao histórico completo do ticker
                X_full_raw = df_t_full[features].values
                X_full_w   = np.clip(X_full_raw, lo, hi)

                if len(df_t_oos) == 0:
                    continue

                try:
                    if self.individual_scaling:
                        scaler_t  = scalers_h.get(ticker, global_scaler)
                        X_full_sc = scaler_t.transform(X_full_w)
                    else:
                        X_full_sc = global_scaler.transform(X_full_w)
                        
                    X_full_sc = np.clip(X_full_sc, -10.0, 10.0)

                    n_oos = len(df_t_oos)
                    n_is  = len(df_t_is)

                    # ----------------------------------------------------------
                    # Expanding Window Viterbi — Causal (sem look-ahead)
                    # Roda Viterbi em X_1:t para descobrir o estado em t.
                    # Mantém o poder preditivo do Viterbi sem ver o futuro.
                    # ----------------------------------------------------------
                    raw_states = []
                    proba_mat  = []

                    for t_oos in range(n_oos):
                        x_hist = X_full_sc[: n_is + t_oos + 1]
                        
                        # predict() usa Viterbi internamente
                        state_seq = hmm.predict(x_hist)
                        # predict_proba usa Forward-Backward
                        probas = hmm.predict_proba(x_hist)
                        
                        raw_states.append(state_seq[-1])
                        proba_mat.append(probas[-1])

                    raw_states = np.array(raw_states)
                    proba_mat  = np.array(proba_mat)

                    result_base['Cluster_HMM']    = [cluster_map[s] for s in raw_states]
                    result_base['Prob_Crise_HMM'] = proba_mat[:, vermelho_id]
                except Exception as exc:
                    result_base['Cluster_HMM']    = 'Inconclusivo'
                    result_base['Prob_Crise_HMM'] = np.nan

                all_results.append(result_base)
                n_oos_total += len(df_t_oos)

            logger.info(
                f"[HMM] Grupo '{grupo}': Treinado com {len(X_train_sc)} obs IS. "
                f"Predito {n_oos_total} obs OOS."
            )

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
