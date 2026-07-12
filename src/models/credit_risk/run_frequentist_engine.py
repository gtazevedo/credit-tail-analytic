import os
import logging
import pandas as pd
import numpy as np
from datetime import datetime
from risk_pipeline import CreditRiskEngine

# Configuração de Logging para a Mesa/Terminal
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    datefmt='%H:%M:%S'
)
logger = logging.getLogger('FrequentistOrchestrator')

def run_frequentist_pipeline(
    historico_path: str = r"..\..\..\dados\debentures_historico_bruto.csv",
    cadastro_path: str = r"..\..\..\dados\cadastro_debentures.csv",
    output_path: str = r"..\..\..\dados\resultado_frequentist_engine.csv"
):
    """
    Orquestrador Frequentist: Ingestão, Merge com Cadastro e Execução do Motor de Risco.
    """
    base_dir = os.path.dirname(__file__)
    historico_abs = os.path.abspath(os.path.join(base_dir, historico_path))
    cadastro_abs = os.path.abspath(os.path.join(base_dir, cadastro_path))
    output_abs = os.path.abspath(os.path.join(base_dir, output_path))

    # 1. Carregar Histórico de Preços (REUNE)
    logger.info("Carregando base histórica de debêntures (REUNE)...")
    if not os.path.exists(historico_abs):
        logger.error(f"Arquivo não encontrado: {historico_abs}")
        return

    df_hist = pd.read_csv(historico_abs)
    df_hist['Data'] = pd.to_datetime(df_hist['Data'])
    logger.info(f"Base histórica carregada: {len(df_hist)} registros encontrados.")

    # 2. Carregar Cadastro (Para Indexador e Vencimento)
    logger.info("Carregando cadastro de debêntures (B3/ANBIMA)...")
    if not os.path.exists(cadastro_abs):
        logger.error(f"Arquivo de cadastro não encontrado: {cadastro_abs}")
        logger.warning(
            "Crie um arquivo CSV contendo as colunas: 'Ticker', 'Indexador', e 'Data_Vencimento' "
            "e salve-o em dados/cadastro_debentures.csv para prosseguir."
        )
        return

    df_cad = pd.read_csv(cadastro_abs)
    
    # Validação do Cadastro
    required_cad_cols = ['Ticker', 'Indexador', 'Data_Vencimento']
    if not all(col in df_cad.columns for col in required_cad_cols):
        logger.error(f"O arquivo de cadastro deve conter as colunas: {required_cad_cols}")
        return

    df_cad['Data_Vencimento'] = pd.to_datetime(df_cad['Data_Vencimento'])

    # 3. Merge Histórico + Cadastro
    logger.info("Realizando merge (Histórico + Cadastro)...")
    df_merged = pd.merge(df_hist, df_cad, on='Ticker', how='inner')
    
    if df_merged.empty:
        logger.error("Merge resultou em um DataFrame vazio. Verifique se os Tickers coincidem.")
        return

    # 4. Cálculo de Dias Úteis até o Vencimento (DU_Vencimento)
    logger.info("Calculando DU_Vencimento usando dias úteis (business days)...")
    # Vetorizando a contagem de dias úteis entre Data atual e Data de Vencimento
    # Usamos np.busday_count (exige datas no formato datetime64[D])
    datas_atuais = df_merged['Data'].values.astype('datetime64[D]')
    datas_venc = df_merged['Data_Vencimento'].values.astype('datetime64[D]')
    
    # Filtro: Ignorar dados onde a Data é maior ou igual ao Vencimento (papel vencido)
    mascara_validos = datas_venc > datas_atuais
    df_merged = df_merged[mascara_validos].copy()
    
    datas_atuais = df_merged['Data'].values.astype('datetime64[D]')
    datas_venc = df_merged['Data_Vencimento'].values.astype('datetime64[D]')
    
    df_merged['DU_Vencimento'] = np.busday_count(datas_atuais, datas_venc)
    
    logger.info(f"Dados consolidados para o motor: {len(df_merged)} registros úteis.")

    # 5. Injetar na CreditRiskEngine
    logger.info("\n" + "="*60)
    logger.info("INICIANDO MOTOR QUANTITATIVO (CREDIT RISK ENGINE)".center(60))
    logger.info("="*60)
    
    try:
        engine = CreditRiskEngine(df_merged)
        
        logger.info("Executando pipeline de Volatilidade e K-Means Transversal...")
        # Usando window_days = 60, step_days = 30 conforme documentação
        df_completo, df_clusters = engine.execute_pipeline(window_days=60, step_days=30)
        
        if df_clusters.empty:
            logger.warning("O K-Means não retornou resultados. Base insuficiente?")
            return
            
        logger.info("Motor executado com sucesso!")
        
        # 6. Salvar e Mostrar Resultados
        df_clusters.to_csv(output_abs, index=False)
        logger.info(f"Resultados transversais (Frequentist) salvos em: {output_path}")
        
        print("\n" + "="*80)
        print("AMOSTRA DO RESULTADO DE CLUSTERIZAÇÃO (CISNES NEGROS)".center(80))
        print("="*80)
        # Mostrar os ativos classificados como Vermelho na janela mais recente
        ultima_janela = df_clusters['Data_Janela'].max()
        df_ult = df_clusters[df_clusters['Data_Janela'] == ultima_janela]
        df_vermelhos = df_ult[(df_ult['Cluster_Risco_KMeans'] == 'Vermelho') | (df_ult['Cluster_Risco_GMM'] == 'Vermelho')]
        
        cols_show = ['Ticker', 'Indexador', 'Taxa_Ajustada_Prazo', 'Taxa_ZScore', 'Volatilidade_EGARCH', 'Cluster_Risco_KMeans', 'Cluster_Risco_GMM']
        print(df_vermelhos[cols_show].head(15).to_markdown(floatfmt=".6f"))
        print("="*80 + "\n")

    except Exception as e:
        logger.error(f"Falha catastrófica no motor de risco: {e}")

if __name__ == "__main__":
    run_frequentist_pipeline()
