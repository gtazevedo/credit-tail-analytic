import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
from arch import arch_model
from statsmodels.stats.diagnostic import acorr_ljungbox, het_arch
import logging
from tqdm import tqdm
import os

from credit_tail_analytics.utils import dados_dir, graficos_dir

logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')
logger = logging.getLogger(__name__)

def run_diagnostico_campeao(n_ativos=500, filter_low_liquidity=True, split_date='2023-01-01'):
    historico_path = str(dados_dir() / 'debentures_historico_bruto.csv')
    cadastro_path = str(dados_dir() / 'cadastro_debentures.csv')
    macro_path = str(dados_dir() / 'macro_data.csv')

    logger.info("Carregando histórico...")
    df = pd.read_csv(historico_path)
    df['Data'] = pd.to_datetime(df['Data'])
    
    # Mapa de indexadores
    indexador_map = {}
    if os.path.exists(cadastro_path):
        df_cad = pd.read_csv(cadastro_path, usecols=lambda c: c in ['Ticker', 'Indexador'])
        indexador_map = df_cad.set_index('Ticker')['Indexador'].to_dict()

    # Mapa CDI
    cdi_map = {}
    try:
        df_macro = pd.read_csv(macro_path)
        df_macro['Data'] = pd.to_datetime(df_macro['Data'])
        cdi_map = df_macro.set_index('Data')['CDI_Anual'].to_dict()
    except:
        pass

    def get_spread_normalizado(df_ativo: pd.DataFrame, indexador_str: str) -> pd.Series:
        idx = str(indexador_str).upper() if indexador_str else 'PRE'
        taxa = df_ativo['Taxa_Ativo'].copy()
        if 'DI' in idx and ('PERCENT' in idx or '%' in idx):
            datas = df_ativo['Data']
            cdi_vals = datas.map(lambda d: cdi_map.get(d, 10.4))
            fator_cdi = (1 + cdi_vals / 100.0) ** (1 / 252)
            fator_tit = (fator_cdi - 1) * (taxa / 100.0) + 1
            spread_eq = (fator_tit ** 252 - 1) * 100.0 - cdi_vals
            return spread_eq.diff().dropna()
        else:
            return taxa.diff().dropna()

    df_teste = df[df['Data'] < split_date].copy()
    if filter_low_liquidity and 'Faixa_Volume_ANBIMA' in df_teste.columns:
        df_teste = df_teste[df_teste['Faixa_Volume_ANBIMA'] != 'Até 1MM'].copy()

    contagem = df_teste.groupby('Ticker').size()
    # Pega todos os tickers ordenados por volume de observações
    all_tickers = contagem.sort_values(ascending=False).index.tolist()
    
    logger.info(f"Iniciando diagnóstico, meta: {n_ativos} ativos com EGARCH(1,1,1) t-Student...")
    
    resultados = []
    
    # Usando tqdm_notebook ou tqdm clássico iterando, mas com break
    pbar = tqdm(total=n_ativos, desc="Ativos Processados")
    
    for ticker in all_tickers:
        if len(resultados) >= n_ativos:
            break
            
        if ticker == 'RDVT11': 
            continue
        
        df_ativo = df_teste[df_teste['Ticker'] == ticker].sort_values('Data').copy()
        idx_str = indexador_map.get(ticker, 'PRE')
        delta_spread = get_spread_normalizado(df_ativo, idx_str)
        
        dados_ativo = delta_spread.dropna() * 100
        
        if len(dados_ativo) < 50:
            continue
            
        try:
            model = arch_model(
                dados_ativo,
                mean='AR', lags=1,
                vol='EGARCH', p=1, o=1, q=1,
                dist='t', rescale=False
            )
            res = model.fit(disp='off', show_warning=False)
            residuos = res.std_resid.dropna()
            
            # Ljung-Box
            lb_test = acorr_ljungbox(residuos, lags=[10], return_df=True)
            p_valor_lb = lb_test['lb_pvalue'].iloc[0]
            
            # ARCH-LM
            _, p_valor_arch, _, _ = het_arch(residuos, nlags=10)
            
            resultados.append({
                'Ticker': ticker,
                'p_valor_LB': p_valor_lb,
                'p_valor_ARCH': p_valor_arch,
                'Pass_LB': p_valor_lb > 0.05,
                'Pass_ARCH': p_valor_arch > 0.05
            })
            pbar.update(1)
        except Exception as e:
            continue
            
    pbar.close()
            
    df_res = pd.DataFrame(resultados)
    
    taxa_lb = df_res['Pass_LB'].mean() * 100
    taxa_arch = df_res['Pass_ARCH'].mean() * 100
    
    logger.info(f"Taxa de Aprovação Ljung-Box: {taxa_lb:.1f}%")
    logger.info(f"Taxa de Aprovação ARCH-LM: {taxa_arch:.1f}%")
    
    # Gerar Gráfico
    plt.style.use('ggplot')
    fig, ax = plt.subplots(figsize=(8, 6))
    
    bars = ax.bar(['Ljung-Box\n(Ausência de Autocorrelação)', 'ARCH-LM\n(Ausência de Efeito ARCH)'], 
                  [taxa_lb, taxa_arch], color=['#4a90d9', '#e07b54'], width=0.5)
    
    ax.set_ylim(0, 110)
    ax.set_ylabel('Proporção de Ativos Aprovados (%)', fontweight='bold')
    ax.set_title(f'Diagnóstico de Resíduos: EGARCH(1,1,1) t-Student\n(Amostra: {len(df_res)} debêntures)', fontweight='bold')
    
    for bar in bars:
        yval = bar.get_height()
        ax.text(bar.get_x() + bar.get_width()/2, yval + 2, f"{yval:.1f}%", ha='center', va='bottom', fontweight='bold', fontsize=12)
        
    plt.tight_layout()
    out_path = graficos_dir() / f'diagnostico_residuos_egarch_n{len(df_res)}.png'
    plt.savefig(out_path, dpi=300, bbox_inches='tight')
    logger.info(f"Gráfico salvo em: {out_path}")
    
if __name__ == '__main__':
    run_diagnostico_campeao(n_ativos=1000, filter_low_liquidity=True)
