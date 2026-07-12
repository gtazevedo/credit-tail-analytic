import os
import time
import random
import logging
from datetime import datetime
import pandas as pd

from selenium import webdriver
from selenium.webdriver.chrome.service import Service
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from webdriver_manager.chrome import ChromeDriverManager

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class AnbimaScraper:
    def __init__(self, download_dir: str = None):
        self.url = "https://data.anbima.com.br/reune/previas/debentures"
        
        if download_dir is None:
            # Padrão para d:/projects/credit-tail-analytic/dados/debentures
            self.download_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "dados", "debentures"))
        else:
            self.download_dir = os.path.abspath(download_dir)
            
        os.makedirs(self.download_dir, exist_ok=True)
        
        self.driver = self._setup_driver()

    def _setup_driver(self):
        chrome_options = Options()
        # Não usaremos headless inicialmente para que o usuário possa ver a execução se desejar
        # chrome_options.add_argument("--headless") 
        chrome_options.add_argument("--window-size=1920,1080")
        
        prefs = {
            "download.default_directory": self.download_dir,
            "download.prompt_for_download": False,
            "download.directory_upgrade": True,
            "safebrowsing.enabled": True
        }
        chrome_options.add_experimental_option("prefs", prefs)
        
        # A linha abaixo irá baixar silenciosamente a versão correta do chromedriver
        service = Service(ChromeDriverManager().install())
        driver = webdriver.Chrome(service=service, options=chrome_options)
        return driver

    def extrair_data(self, data: datetime):
        data_str_input = data.strftime("%d/%m/%Y")
        data_str_output = data.strftime("%Y%m%d")
        logger.info(f"Iniciando extração para a data: {data_str_input}")
        
        # Garante a substituição caso o arquivo final já exista
        novo_nome = f"{data_str_output}_debentures_previa_anbima.csv"
        novo_caminho = os.path.join(self.download_dir, novo_nome)
        if os.path.exists(novo_caminho):
            try:
                os.remove(novo_caminho)
                logger.info(f"Arquivo antigo {novo_nome} removido para ser substituído pela nova extração.")
            except Exception as e:
                logger.warning(f"Não foi possível remover o arquivo antigo {novo_nome}: {e}")
        
        try:
            wait = WebDriverWait(self.driver, 5) # Diminuído timeout para 5s em vez de 20s para acelerar erros
            # Esperar a página carregar até que o input de data apareça
            date_input = wait.until(EC.element_to_be_clickable((By.XPATH, "//input[@type='text']")))
            
            # Clica no input para abrir o calendário
            date_input.click()
            time.sleep(1)
            
            meses_pt = {
                1: "Janeiro", 2: "Fevereiro", 3: "Março", 4: "Abril", 
                5: "Maio", 6: "Junho", 7: "Julho", 8: "Agosto", 
                9: "Setembro", 10: "Outubro", 11: "Novembro", 12: "Dezembro"
            }
            
            alvo_mes_ano = f"{meses_pt[data.month]} {data.year}"
            alvo_dia = str(data.day)
            
            # Navegar no calendário até o mês/ano correto
            while True:
                try:
                    current_month_elem = wait.until(EC.presence_of_element_located((By.CSS_SELECTOR, ".react-datepicker__current-month")))
                    current_month_text = current_month_elem.text.strip()
                except:
                    current_month_elem = self.driver.find_element(By.XPATH, "//div[contains(@class, 'current-month') or contains(@class, 'header')]")
                    current_month_text = current_month_elem.text.strip()
                
                if current_month_text.lower() == alvo_mes_ano.lower():
                    break
                    
                partes = current_month_text.split()
                if len(partes) == 2:
                    mes_atual_nome, ano_atual_str = partes
                    mes_atual_idx = next((k for k, v in meses_pt.items() if v.lower() == mes_atual_nome.lower()), 1)
                    ano_atual = int(ano_atual_str)
                    
                    if (data.year < ano_atual) or (data.year == ano_atual and data.month < mes_atual_idx):
                        btn_prev = self.driver.find_element(By.CSS_SELECTOR, ".react-datepicker__navigation--previous")
                        btn_prev.click()
                    else:
                        btn_next = self.driver.find_element(By.CSS_SELECTOR, ".react-datepicker__navigation--next")
                        btn_next.click()
                    time.sleep(0.1) # Rápido para não perder tempo
                else:
                    logger.warning(f"Não foi possível parsear o mês atual: {current_month_text}. Abortando navegação.")
                    break
                    
            time.sleep(0.3)
            xpath_dia = f"//div[contains(@class, 'react-datepicker__day') and not(contains(@class, 'react-datepicker__day--outside-month')) and text()='{alvo_dia}']"
            dia_elem = wait.until(EC.presence_of_element_located((By.XPATH, xpath_dia)))
            
            # Verifica se o dia é clicável
            classes_dia = dia_elem.get_attribute("class") or ""
            aria_disabled = dia_elem.get_attribute("aria-disabled")
            
            if "disabled" in classes_dia.lower() or aria_disabled == "true":
                logger.info(f"Data {data_str_input} desabilitada no calendário. Pulando...")
                self.driver.find_element(By.TAG_NAME, "body").click()
                return
                
            dia_elem.click()
            
            # Aguardar requisição/tabela atualizar
            logger.info(f"Filtro selecionado no calendário: {data_str_input}. Aguardando...")
            time.sleep(4) 
            
            # Tenta encontrar o botão CSV (se não houver dados, ele falha rápido pelo timeout menor)
            try:
                btn_csv = wait.until(EC.element_to_be_clickable((By.XPATH, "//button[@aria-label='Baixar CSV das prévias do REUNE']")))
                
                # Snapshot dos arquivos antes do click para evitar race condition
                arquivos_antes = set(f for f in os.listdir(self.download_dir) if f.endswith('.csv'))
                btn_csv.click()
            except Exception:
                logger.warning(f"Sem botão CSV para {data_str_input} (Sem dados no dia). Pulando...")
                return
            
            # Aguardar o download terminar de forma robusta
            timeout = 30
            novo_arquivo = None
            for _ in range(timeout):
                time.sleep(1)
                arquivos_agora = set(f for f in os.listdir(self.download_dir) if f.endswith('.csv'))
                novos_csvs = arquivos_agora - arquivos_antes
                
                if novos_csvs:
                    # Garantir que nenhum arquivo temporário do Chrome ainda está baixando
                    if not any(f.endswith(".crdownload") for f in os.listdir(self.download_dir)):
                        novo_arquivo = list(novos_csvs)[0]
                        break
                        
            if novo_arquivo:
                caminho_antigo = os.path.join(self.download_dir, novo_arquivo)
                novo_nome = f"{data_str_output}_debentures_previa_anbima.csv"
                novo_caminho = os.path.join(self.download_dir, novo_nome)
                try:
                    if os.path.exists(novo_caminho):
                        os.remove(novo_caminho)
                    os.rename(caminho_antigo, novo_caminho)
                except Exception as e:
                    logger.error(f"Erro ao renomear {caminho_antigo}: {e}")
            else:
                logger.warning(f"Download não detectado no tempo esperado para {data_str_input}.")
            
            delay = random.uniform(2.0, 5.0)
            logger.info(f"Extração de {data_str_input} concluída com sucesso. Aguardando {delay:.1f} segundos...")
            time.sleep(delay)
            
        except Exception as e:
            logger.error(f"Erro inesperado ao extrair {data_str_input}: {e}")

    def extrair_historico(self, data_inicio: str, data_fim: str):
        """
        Extrai histórico varrendo dias úteis no intervalo.
        """
        # Acessamos a url apenas UMA vez para otimização massiva de tempo no calendário
        self.driver.get(self.url)
        time.sleep(3)
        
        datas = pd.bdate_range(start=data_inicio, end=data_fim)
        logger.info(f"Iniciando loop para {len(datas)} dias úteis.")
        
        for dt in datas:
            self.extrair_data(dt)
            
        logger.info("Processo de extração finalizado!")
        
    def fechar(self):
        if self.driver:
            self.driver.quit()

if __name__ == "__main__":
    scraper = AnbimaScraper()
    try:
        # Exemplo: Puxar últimos 3 dias
        hoje = pd.Timestamp.now()
        inicio = (hoje - pd.Timedelta(days=5)).strftime("%Y-%m-%d")
        fim = hoje.strftime("%Y-%m-%d")
        scraper.extrair_historico(inicio, fim)
    finally:
        scraper.fechar()
