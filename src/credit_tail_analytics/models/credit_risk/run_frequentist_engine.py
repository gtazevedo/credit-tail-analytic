import os
import sys
import logging
import pandas as pd
import numpy as np
from credit_tail_analytics.models.credit_risk.risk_pipeline import CreditRiskEngine
from credit_tail_analytics.utils import dados_dir, graficos_dir

# ---------------------------------------------------------------------------
# Configuração de Logging
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    datefmt='%H:%M:%S'
)
logger = logging.getLogger('FrequentistOrchestrator')


def run_frequentist_pipeline(
    historico_path: str = None,
    cadastro_path:  str = None,
    output_path:    str = None,
    model_type:     str = 'both',
    features:       list = None,
    filter_low_liquidity: bool = True,
    split_date:     str = '2023-01-01',
):
    """
    Orquestrador Frequentist: Ingestão, Merge com Cadastro e Execução do Motor de Risco.

    Parâmetros
    ----------
    historico_path : str, optional
        Caminho absoluto ao CSV histórico. Se None, usa `dados/debentures_historico_bruto.csv`
        na raiz do projeto (detectada automaticamente).
    cadastro_path : str, optional
        Caminho absoluto ao CSV de cadastro. Se None, usa `dados/cadastro_debentures.csv`.
    output_path : str, optional
        Caminho onde o CSV de resultados será salvo. Se None, usa `dados/resultado_frequentist_engine.csv`.
    model_type : str
        'kmeans' | 'hmm' | 'both'. Define quais modelos serão executados.
    features : list, optional
        Lista de features para os modelos de clusterização. Se None, usa o padrão
        do engine: ['Taxa_ZScore', 'Volatilidade_EGARCH'].
    filter_low_liquidity : bool, default True
        Remove observações com Score_Liquidez == 1 (Faixa 3 ANBIMA) antes do EGARCH.
    split_date : str
        Data de corte Treino/Validação no formato 'YYYY-MM-DD'.
    """
    _dados = dados_dir()
    historico_abs = historico_path or str(_dados / 'debentures_historico_bruto.csv')
    cadastro_abs  = cadastro_path  or str(_dados / 'cadastro_debentures.csv')
    output_abs    = output_path    or str(_dados / 'resultado_frequentist_engine.csv')

    # ------------------------------------------------------------------
    # 1. Carregar Histórico de Preços (REUNE)
    # ------------------------------------------------------------------
    logger.info("Carregando base histórica de debêntures (REUNE)...")
    if not os.path.exists(historico_abs):
        logger.error(f"Arquivo não encontrado: {historico_abs}")
        return

    df_hist = pd.read_csv(historico_abs)
    df_hist['Data'] = pd.to_datetime(df_hist['Data'])
    logger.info(f"Base histórica carregada: {len(df_hist)} registros.")

    # ------------------------------------------------------------------
    # 2. Carregar Cadastro (Indexador + Vencimento)
    # ------------------------------------------------------------------
    logger.info("Carregando cadastro de debêntures (B3/ANBIMA)...")
    if not os.path.exists(cadastro_abs):
        logger.error(f"Cadastro não encontrado: {cadastro_abs}")
        logger.warning(
            "Crie um CSV com as colunas 'Ticker', 'Indexador', 'Data_Vencimento' "
            "e salve em dados/cadastro_debentures.csv."
        )
        return

    df_cad = pd.read_csv(cadastro_abs)
    required_cad_cols = ['Ticker', 'Indexador', 'Data_Vencimento']
    if not all(col in df_cad.columns for col in required_cad_cols):
        logger.error(f"Cadastro deve conter: {required_cad_cols}")
        return

    df_cad['Data_Vencimento'] = pd.to_datetime(df_cad['Data_Vencimento'])

    # ------------------------------------------------------------------
    # 3. Merge Histórico + Cadastro
    # ------------------------------------------------------------------
    logger.info("Realizando merge (Histórico + Cadastro)...")
    df_merged = pd.merge(df_hist, df_cad, on='Ticker', how='inner')

    if df_merged.empty:
        logger.error("Merge resultou em DataFrame vazio. Verifique se os Tickers coincidem.")
        return

    # ------------------------------------------------------------------
    # 4. Cálculo de DU_Vencimento (dias úteis)
    # ------------------------------------------------------------------
    logger.info("Calculando DU_Vencimento (dias úteis)...")
    datas_atuais = df_merged['Data'].values.astype('datetime64[D]')
    datas_venc   = df_merged['Data_Vencimento'].values.astype('datetime64[D]')

    mascara_validos = datas_venc > datas_atuais
    df_merged = df_merged[mascara_validos].copy()

    datas_atuais = df_merged['Data'].values.astype('datetime64[D]')
    datas_venc   = df_merged['Data_Vencimento'].values.astype('datetime64[D]')
    df_merged['DU_Vencimento'] = np.busday_count(datas_atuais, datas_venc)

    logger.info(f"Dados consolidados para o motor: {len(df_merged)} registros úteis.")

    # ------------------------------------------------------------------
    # 5. Executar Motor Quantitativo
    # ------------------------------------------------------------------
    logger.info("\n" + "=" * 60)
    logger.info("INICIANDO MOTOR QUANTITATIVO (CREDIT RISK ENGINE)".center(60))
    logger.info(f"  model_type            : {model_type}")
    logger.info(f"  features              : {features or 'padrão do engine'}")
    logger.info(f"  filter_low_liquidity  : {filter_low_liquidity}")
    logger.info(f"  split_date            : {split_date}")
    logger.info("=" * 60)

    try:
        engine = CreditRiskEngine(
            df_merged,
            features=features,
            filter_low_liquidity=filter_low_liquidity,
        )

        df_completo, df_clusters = engine.execute_pipeline(
            split_date=split_date,
            model_type=model_type,
            features=features,
        )

        if df_clusters.empty:
            logger.warning(
                "O pipeline não retornou resultados no período Out-of-Sample. "
                "Base insuficiente ou split_date muito recente?"
            )
            return

        logger.info("Motor executado com sucesso!")

        # ------------------------------------------------------------------
        # 6. Salvar resultados
        # ------------------------------------------------------------------
        df_clusters.to_csv(output_abs, index=False)
        logger.info(f"Resultados salvos em: {output_abs}")

        # ------------------------------------------------------------------
        # 7. Exibir resumo por Indexador_Grupo
        # ------------------------------------------------------------------
        print("\n" + "=" * 80)
        print("RESUMO DA ÚLTIMA DATA OUT-OF-SAMPLE (por Indexador_Grupo)".center(80))
        print("=" * 80)

        ultima_data = df_clusters['Data'].max()
        df_ult = df_clusters[df_clusters['Data'] == ultima_data]

        for grupo, df_g in df_ult.groupby('Indexador_Grupo'):
            print(f"\n>  Grupo: {grupo}  ({len(df_g)} ativos em {ultima_data.date()})")
            print("-" * 70)

            cols_show = ['Ticker', 'Taxa_ZScore', 'Volatilidade_EGARCH']
            if 'Cluster_KMeans' in df_g.columns:
                cols_show.append('Cluster_KMeans')
            if 'Cluster_HMM' in df_g.columns:
                cols_show.append('Cluster_HMM')
            if 'Prob_Crise_HMM' in df_g.columns:
                cols_show.append('Prob_Crise_HMM')

            cols_show = [c for c in cols_show if c in df_g.columns]
            df_vermelhos = df_g[
                (df_g.get('Cluster_KMeans', pd.Series(dtype=str)) == 'Vermelho') |
                (df_g.get('Cluster_HMM',    pd.Series(dtype=str)) == 'Vermelho')
            ]
            if not df_vermelhos.empty:
                print(f"⚠  Ativos em VERMELHO: {len(df_vermelhos)}")
                print(df_vermelhos[cols_show].head(10).to_markdown(floatfmt=".4f"))
            else:
                print("✓  Nenhum ativo em VERMELHO nesta janela.")

        print("\n" + "=" * 80 + "\n")

    except Exception as e:
        logger.error(f"Falha catastrófica no motor de risco: {e}", exc_info=True)


# ---------------------------------------------------------------------------
# Ponto de entrada CLI — registrado via pyproject.toml [project.scripts]
# ---------------------------------------------------------------------------
def _cli_main():
    """Entry point para o comando `credit-risk-engine` instalado pelo pip."""
    import argparse

    parser = argparse.ArgumentParser(
        description="Motor Frequentista de Risco de Crédito (K-Means vs HMM)"
    )
    parser.add_argument(
        '--model_type', type=str, default='both',
        choices=['kmeans', 'hmm', 'both'],
        help="Modelos a executar: 'kmeans', 'hmm' ou 'both' (default: both)"
    )
    parser.add_argument(
        '--features', type=str, nargs='+', default=None,
        help="Features para os modelos (ex: --features Taxa_ZScore Volatilidade_EGARCH)"
    )
    parser.add_argument(
        '--no_liquidity_filter', action='store_true',
        help="Desativa o filtro de baixa liquidez (Faixa 3 ANBIMA)"
    )
    parser.add_argument(
        '--split_date', type=str, default='2023-01-01',
        help="Data de corte Treino/Validação (default: 2023-01-01)"
    )
    parser.add_argument(
        '--historico',  type=str, default=None, help="Caminho para o CSV histórico")
    parser.add_argument(
        '--cadastro',   type=str, default=None, help="Caminho para o CSV de cadastro")
    parser.add_argument(
        '--output',     type=str, default=None, help="Caminho de saída do CSV de resultados")

    args = parser.parse_args()

    run_frequentist_pipeline(
        historico_path=args.historico,
        cadastro_path=args.cadastro,
        output_path=args.output,
        model_type=args.model_type,
        features=args.features,
        filter_low_liquidity=not args.no_liquidity_filter,
        split_date=args.split_date,
    )


if __name__ == "__main__":
    _cli_main()
