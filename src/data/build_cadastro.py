import os
import time
import logging
import pandas as pd
from tqdm import tqdm
from debentures_dot_com.emissoes import EmissoesDebentures

logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')
logger = logging.getLogger('CadastroBuilder')

def build_cadastro_mestre():
    hist_path = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "dados", "debentures_historico_bruto.csv"))
    out_path = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "dados", "cadastro_debentures.csv"))
    
    if not os.path.exists(hist_path):
        logger.error(f"Arquivo histórico não encontrado: {hist_path}")
        return

    logger.info("Lendo tickers do arquivo histórico...")
    df_hist = pd.read_csv(hist_path, usecols=['Ticker'])
    tickers = df_hist['Ticker'].dropna().unique()
    logger.info(f"{len(tickers)} tickers únicos encontrados.")

    ed = EmissoesDebentures()
    
    resultados = []
    
    def process_ticker(ticker):
        try:
            zz = ed.lista_caracteristicas(ticker)
            if zz is None or zz.empty:
                return None
                
            dict_carac = {x.strip(): y for x, y in zip(zz.Descricao, zz.Valores)}
            
            data_vencimento = dict_carac.get('Data de Vencimento')
            indexador = dict_carac.get('indice')
            
            if not data_vencimento or pd.isna(data_vencimento) or data_vencimento == '--':
                return None
                
            try:
                data_venc_dt = pd.to_datetime(data_vencimento, format='%d/%m/%Y').strftime('%Y-%m-%d')
            except Exception:
                data_venc_dt = pd.to_datetime(data_vencimento).strftime('%Y-%m-%d')

            return {
                'Ticker': ticker,
                'Indexador': str(indexador).strip().upper() if indexador else 'PRE',
                'Data_Vencimento': data_venc_dt
            }
        except Exception:
            return None

    import concurrent.futures

    # Processa os tickers com barra de progresso
    with concurrent.futures.ThreadPoolExecutor(max_workers=20) as executor:
        futures = {executor.submit(process_ticker, t): t for t in tickers}
        for future in tqdm(concurrent.futures.as_completed(futures), total=len(tickers), desc="Consultando Cadastro API"):
            res = future.result()
            if res:
                resultados.append(res)

    if not resultados:
        logger.error("Nenhum cadastro pôde ser extraído.")
        return
        
    df_cad = pd.DataFrame(resultados)
    
    # Limpeza final nos Indexadores
    # Remapear casos exóticos (ex: "IPCA", "% DI", "IGP-M")
    def clean_indexador(idx):
        if 'DI' in idx or 'CDI' in idx:
            return 'DI'
        elif 'IPCA' in idx:
            return 'IPCA'
        elif 'IGP' in idx:
            return 'IGPM'
        else:
            return 'PRE'
            
    df_cad['Indexador'] = df_cad['Indexador'].apply(clean_indexador)
    
    # Salvando sobre o nosso mock
    df_cad.to_csv(out_path, index=False)
    logger.info(f"Cadastro mestre real construído com sucesso! Salvo em: {out_path}")
    logger.info(f"Total de debêntures consolidadas: {len(df_cad)}")

if __name__ == '__main__':
    build_cadastro_mestre()
