import pandas as pd
import glob
import os
import re
import logging
from tqdm import tqdm

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def unify_csvs():
    folder_path = os.path.join("dados", "debentures")
    all_files = glob.glob(os.path.join(folder_path, "*.csv"))
    
    if not all_files:
        logger.error("Nenhum arquivo CSV encontrado na pasta dados/debentures/")
        return

    logger.info(f"Encontrados {len(all_files)} arquivos. Iniciando processamento de unificação...")
    
    dataframes = []
    date_pattern = re.compile(r"(\d{2}/\d{2}/\d{4})")
    
    for file in tqdm(all_files, desc="Lendo arquivos CSV"):
        try:
            with open(file, 'r', encoding='latin1') as f:
                f.readline() # pula linha 1
                linha_2 = f.readline()
                
            match = date_pattern.search(linha_2)
            if not match:
                logger.warning(f"Data não encontrada no cabeçalho do arquivo {file}. Pulando.")
                continue
            
            data_ref = match.group(1)
            
            # Ler o CSV (pula as 3 primeiras linhas, a 4ª é o cabeçalho)
            df = pd.read_csv(file, skiprows=3, sep=';', encoding='latin1', 
                             na_values=['--', ''], decimal=',')
            
            # Se o df estiver vazio ou não for bem formatado, pular
            if df.empty or 'CETIP' not in df.columns:
                continue
                
            # Adiciona a coluna de data
            df['Data'] = pd.to_datetime(data_ref, format="%d/%m/%Y")
            
            # Para evitar duplicação, manteremos apenas as linhas de Agrupamento == 'Total'
            if 'Agrupamento' in df.columns:
                df = df[df['Agrupamento'] == 'Total']
                
            dataframes.append(df)
            
        except Exception as e:
            logger.error(f"Erro ao processar {file}: {e}")
            
    if not dataframes:
        logger.error("Nenhum dataframe válido pôde ser extraído.")
        return
        
    logger.info("Concatenando todos os dataframes em memória...")
    df_final = pd.concat(dataframes, ignore_index=True)
    
    # Padronização de nomes das colunas (Padrão CreditRiskEngine)
    renames = {
        'CETIP': 'Ticker',
        'Preço Médio': 'PU',
        'Faixa de Volume': 'Faixa_Volume_ANBIMA',
        'Taxa Média': 'Taxa_Ativo'
    }
    df_final.rename(columns=renames, inplace=True)

    # Ordenar por data e por ativo
    df_final = df_final.sort_values(by=['Data', 'Ticker']).reset_index(drop=True)
    
    output_path = os.path.join("dados", "debentures_historico_bruto.csv")
    logger.info(f"Salvando o dataframe consolidado em {output_path}...")
    
    # Salvar em CSV (formato padrão universal, decimal ponto e separador vírgula)
    df_final.to_csv(output_path, index=False, sep=',', encoding='utf-8')
    
    logger.info(f"Concluído com sucesso! O arquivo final possui {len(df_final)} linhas e {len(df_final.columns)} colunas.")
    logger.info("Amostra dos dados:")
    print(df_final.head())

if __name__ == "__main__":
    unify_csvs()
