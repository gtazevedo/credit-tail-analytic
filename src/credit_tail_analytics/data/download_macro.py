import os
import pandas as pd
import logging
from bcb import sgs
from credit_tail_analytics.utils import dados_dir

logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')
logger = logging.getLogger('MacroDownloader')

def download_macro_data(start_date='2018-01-01', end_date='2028-01-01'):
    """
    Baixa dados macroeconômicos do Sistema Gerenciador de Séries Temporais (SGS) do Banco Central.
    - 4389: Taxa de juros - CDI anualizada base 252
    - 1178: Taxa de juros - Selic anualizada base 252
    - 433: Índice nacional de preços ao consumidor-amplo (IPCA) - Variação mensal
    - 189: Índice geral de preços-mercado (IGP-M) - Variação mensal
    - 13522: IPCA - Acumulado 12 meses
    """
    logger.info("Conectando ao SGS do Banco Central para baixar dados macroeconômicos...")
    
    series_map = {
        'CDI_Anual': 4389,
        'Selic_Anual': 1178,
        'IPCA_Mensal': 433,
        'IPCA_12M': 13522,
        'IGPM_Mensal': 189
    }
    
    try:
        # Baixa todas as séries de uma vez
        df_macro = sgs.get(series_map, start=start_date, end=end_date)
        df_macro.reset_index(inplace=True)
        df_macro['Date'] = pd.to_datetime(df_macro['Date'])
        
        # Para garantir que todos os dias tenham dados (séries mensais vêm apenas no dia 1 ou último dia do mês)
        # Vamos criar um índice diário e preencher para frente (forward fill)
        min_date = df_macro['Date'].min()
        max_date = df_macro['Date'].max()
        all_dates = pd.date_range(start=min_date, end=max_date)
        
        df_macro.set_index('Date', inplace=True)
        df_macro = df_macro.reindex(all_dates)
        
        # O IPCA e IGPM são mensais, então fazemos ffill (repetir o último valor conhecido para todos os dias do mês seguinte)
        # O CDI e Selic são diários (em dias úteis), fazemos ffill para finais de semana e feriados
        df_macro = df_macro.ffill()
        df_macro.reset_index(inplace=True)
        df_macro.rename(columns={'index': 'Data'}, inplace=True)
        
        # Salva o arquivo em dados/
        dir_dados = dados_dir()
        if not dir_dados.exists():
            dir_dados.mkdir(parents=True, exist_ok=True)
            
        out_path = dir_dados / "macro_data.csv"
        df_macro.to_csv(out_path, index=False)
        logger.info(f"Dados macroeconômicos salvos com sucesso em: {out_path}")
        logger.info(f"Shape: {df_macro.shape} | Colunas: {list(df_macro.columns)}")
        
    except Exception as e:
        logger.error(f"Erro ao baixar dados do BCB: {e}")

if __name__ == "__main__":
    download_macro_data()
