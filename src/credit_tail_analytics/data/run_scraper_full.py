from data.anbima_scraper import AnbimaScraper
from datetime import datetime

def rodar_extracao():
    print("Iniciando extração histórica de debêntures desde Janeiro de 2003...")
    scraper = AnbimaScraper()
    try:
        hoje = datetime.now().strftime("%Y-%m-%d")
        scraper.extrair_historico("2018-01-01", hoje)
    finally:
        scraper.fechar()

if __name__ == "__main__":
    rodar_extracao()
