import pandas as pd
import glob
import os
import re
import logging
import datetime
from tqdm import tqdm
from credit_tail_analytics.utils import dados_dir

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def preencher_gaps(folder_path, date_pattern, all_files):
    import brazilian_holidays.datas as bh
    from data.anbima_scraper import AnbimaScraper

    logger.info("Verificando gaps no histórico (Self-Healing)...")
    
    # 1. Levantar datas existentes
    datas_existentes = set()
    for file in all_files:
        if 'datas_faltantes' in file: continue
        try:
            with open(file, 'r', encoding='latin1') as f:
                f.readline()
                linha_2 = f.readline()
            match = date_pattern.search(linha_2)
            if match:
                dt = pd.to_datetime(match.group(1), format="%d/%m/%Y").date()
                datas_existentes.add(dt)
        except Exception:
            continue
            
    if not datas_existentes:
        return
        
    min_date = min(datas_existentes)
    max_date = max(datas_existentes)
    
    # 2. Gerar feriados brasileiros
    calendario = bh.Calendario()
    for ano in range(min_date.year, max_date.year + 1):
        feriados = bh.Holidays(ano)
        feriados.add_all()
        calendario.add(feriados)
    
    # create_list retorna list of datetime.date (se tipo='date')
    feriados_br = set(d for d in calendario.create_list(tipo='date'))
    
    # 3. Calcular datas úteis esperadas
    expected_dates = set()
    current = min_date
    while current <= max_date:
        # Pula sábados (5) e domingos (6) e feriados nacionais
        if current.weekday() < 5 and current not in feriados_br:
            expected_dates.add(current)
        current += datetime.timedelta(days=1)
        
    gaps = expected_dates - datas_existentes
    
    # 4. Remover da lista as datas que sabidamente não existem (Blacklist)
    blacklist_path = folder_path / "datas_faltantes.csv"
    blacklist_dates = set()
    if os.path.exists(blacklist_path):
        try:
            blacklist_df = pd.read_csv(blacklist_path)
            blacklist_dates = set(pd.to_datetime(blacklist_df['Data']).dt.date)
        except Exception:
            pass
            
    gaps_to_fetch = sorted(list(gaps - blacklist_dates))
    
    if gaps_to_fetch:
        logger.info(f"Encontrados {len(gaps_to_fetch)} gaps após filtragem de feriados. Iniciando scraper...")
        scraper = AnbimaScraper()
        novas_faltantes = []
        try:
            for gap in tqdm(gaps_to_fetch, desc="Recuperando Gaps"):
                dt_gap = pd.to_datetime(gap)
                scraper.extrair_data(dt_gap)
                
                # Valida se o arquivo baixou mesmo
                expected_filename = folder_path / f"{dt_gap.strftime('%Y%m%d')}_debentures_previa_anbima.csv"
                if not expected_filename.exists():
                    novas_faltantes.append(gap)
        finally:
            scraper.fechar()
            
        if novas_faltantes:
            logger.info(f"{len(novas_faltantes)} gaps eram indisponíveis na fonte. Adicionando à blacklist.")
            new_df = pd.DataFrame({'Data': novas_faltantes})
            if blacklist_path.exists():
                new_df.to_csv(blacklist_path, mode='a', header=False, index=False)
            else:
                new_df.to_csv(blacklist_path, index=False)
    else:
        logger.info("Nenhum gap novo a ser recuperado. Histórico intacto!")


def unify_csvs():
    dir_dados = dados_dir()
    folder_path = dir_dados / "debentures"
    all_files = glob.glob(str(folder_path / "*.csv"))
    
    if not all_files:
        logger.error("Nenhum arquivo CSV encontrado na pasta dados/debentures/")
        return

    date_pattern = re.compile(r"(\d{2}/\d{2}/\d{4})")
    
    # Passo de Self-Healing (Recuperação de Gaps)
    preencher_gaps(folder_path, date_pattern, all_files)
    
    # Recarrega a lista de arquivos caso novos tenham sido baixados
    all_files = glob.glob(str(folder_path / "*.csv"))
    logger.info(f"Iniciando processamento de unificação em {len(all_files)} arquivos...")
    
    dataframes = []
    
    for file in tqdm(all_files, desc="Lendo arquivos CSV"):
        if 'datas_faltantes' in file:
            continue
            
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
        'Taxa Média': 'Taxa_Ativo',
        'Taxa Mínima': 'Taxa_Minima',
        'Taxa Máxima': 'Taxa_Maxima'
    }
    df_final.rename(columns=renames, inplace=True)
    
    # Criar Spread Intraday (Volatilidade de Liquidez diária)
    if 'Taxa_Maxima' in df_final.columns and 'Taxa_Minima' in df_final.columns:
        df_final['Range_Taxa_Intraday'] = df_final['Taxa_Maxima'] - df_final['Taxa_Minima']
        # Tratar zeros ou NaNs
        df_final['Range_Taxa_Intraday'] = df_final['Range_Taxa_Intraday'].fillna(0).clip(lower=0)
    else:
        df_final['Range_Taxa_Intraday'] = 0.0

    # Ordenar por data e por ativo
    df_final = df_final.sort_values(by=['Data', 'Ticker']).reset_index(drop=True)
    dir_dados = dados_dir()
    output_path = dir_dados / "debentures_historico_bruto.csv"
    logger.info(f"Salvando o dataframe consolidado em {output_path}...")
    
    # Salvar em CSV (formato padrão universal, decimal ponto e separador vírgula)
    df_final.to_csv(output_path, index=False, sep=',', encoding='utf-8')
    
    logger.info(f"Concluído com sucesso! O arquivo final possui {len(df_final)} linhas e {len(df_final.columns)} colunas.")

if __name__ == "__main__":
    unify_csvs()
