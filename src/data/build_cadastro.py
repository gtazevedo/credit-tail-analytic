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
            carac_deb = ed.lista_caracteristicas(ticker)
            if carac_deb is None or carac_deb.empty:
                return None
                
            dict_carac = {str(x).strip(): (str(y).strip() if pd.notna(y) else '') for x, y in zip(carac_deb.Descricao, carac_deb.Valores)}
            
            data_vencimento = dict_carac.get('Data de Vencimento')
            indexador = dict_carac.get('indice')
            
            if not data_vencimento or pd.isna(data_vencimento) or data_vencimento == '--':
                return None
                
            try:
                data_venc_dt = pd.to_datetime(data_vencimento, format='%d/%m/%Y').strftime('%Y-%m-%d')
            except Exception:
                data_venc_dt = pd.to_datetime(data_vencimento).strftime('%Y-%m-%d')

            data_emissao = dict_carac.get('Data de Emissao', '')
            try:
                data_emissao_dt = pd.to_datetime(data_emissao, format='%d/%m/%Y').strftime('%Y-%m-%d') if data_emissao and data_emissao != '--' else ''
            except Exception:
                data_emissao_dt = ''

            return {
                'Ticker': ticker,
                'Indexador': str(indexador).upper() if indexador else 'PRE',
                'Data_Emissao': data_emissao_dt,
                'Data_Vencimento': data_venc_dt,
                'Empresa': dict_carac.get('Empresa', ''),
                'CNPJ': dict_carac.get('CNPJ', ''),
                'Emissao': dict_carac.get('Emissao', ''),
                'Situacao': dict_carac.get('Situacao', ''),
                'Classe': dict_carac.get('Classe', ''),
                'Garantia': dict_carac.get('Garantia/Especie', ''),
                'Deb_Incentivada': dict_carac.get('Deb. Incent. (Lei 12.431)', ''),
                'Resgate_Antecipado': dict_carac.get('Resgate Antecipado', ''),
                'Agente_Fiduciario': dict_carac.get('Agente Fiduciario', ''),
                'Coordenador_Lider': dict_carac.get('Coordenador Lider', '')
            }
        except Exception as e:
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
    
    # Salvando o cadastro ampliado
    df_cad.to_csv(out_path, index=False)
    logger.info(f"Cadastro mestre real construído com sucesso! Salvo em: {out_path}")
    logger.info(f"Total de debêntures consolidadas: {len(df_cad)}")

    # Unificação com o Histórico Bruto para criar o Dataset Integrado de Modelagem (Etapas 2 e 3)
    logger.info("Realizando unificação do Cadastro Enriquecido com o Histórico Bruto...")
    df_hist_full = pd.read_csv(hist_path)
    # Evita duplicação de colunas caso o histórico já tenha recebido merge antes
    cols_to_use = df_cad.columns.difference(df_hist_full.columns).tolist() + ['Ticker']
    df_merged = pd.merge(df_hist_full, df_cad[cols_to_use], on='Ticker', how='left')
    
    merged_path = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "dados", "dataset_credito_consolidado.csv"))
    df_merged.to_csv(merged_path, index=False)
    logger.info(f"Dataset consolidado (Histórico + Cadastro ampliado) salvo com sucesso em: {merged_path}")

if __name__ == '__main__':
    build_cadastro_mestre()
