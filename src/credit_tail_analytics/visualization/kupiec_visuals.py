import os
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.dates as mdates
import seaborn as sns
import logging
from typing import List, Optional
from credit_tail_analytics.utils import graficos_dir

# Sem logging.basicConfig — configuração delegada ao caller
logger = logging.getLogger(__name__)

def plot_kupiec_validation(
    df: pd.DataFrame,
    df_kupiec_results: pd.DataFrame,
    tickers: List[str],
    out_dir: str,
    split_date: str = '2023-01-01',
    filename_prefix: str = '05'
):
    """
    Gera gráficos de dispersão/linha mostrando o Delta_Spread (retorno do spread)
    contra o VaR condicional 99%. Pontos onde Delta_Spread > VaR_99 são destacados
    como violações.
    """
    logger.info("Gerando gráficos de validação de Kupiec (VaR vs Delta Spread)...")
    
    split_dt = pd.to_datetime(split_date)
    
    if 'Data' in df.columns:
        df['Data'] = pd.to_datetime(df['Data'])
        
    df_oos = df[df['Data'] >= split_dt].copy()
    
    case_df = df_oos[df_oos['Ticker'].isin(tickers)].copy()
    if case_df.empty:
        logger.warning("Nenhum dado OOS encontrado para os tickers solicitados.")
        return
        
    tickers_present = [t for t in tickers if t in case_df['Ticker'].unique()]
    n_tickers = len(tickers_present)
    
    if n_tickers == 0:
        return
        
    fig, axes = plt.subplots(n_tickers, 1, figsize=(14, 4 * n_tickers), sharex=True)
    if n_tickers == 1:
        axes = [axes]
        
    for ax, ticker in zip(axes, tickers_present):
        df_t = case_df[case_df['Ticker'] == ticker].sort_values('Data')
        
        if df_t.empty or 'VaR_99' not in df_t.columns or 'Delta_Spread' not in df_t.columns:
            ax.set_title(f"{ticker} — sem dados OOS de VaR/Delta")
            continue
            
        # Pega estatísticas de Kupiec para este ticker
        stats = df_kupiec_results[df_kupiec_results['Ticker'] == ticker]
        if not stats.empty:
            s = stats.iloc[0]

            # Compatibilidade: suporta CSV gerado antes e depois da refatoração
            # Novo formato: P_Valor_POF / P_Valor_CC / P_Valor_Joint / Joint_Valido
            # Formato legado: P_Valor / Modelo_Valido
            if 'P_Valor_POF' in s.index:
                p_pof   = s['P_Valor_POF']
                p_cc    = s.get('P_Valor_CC',    float('nan'))
                p_joint = s.get('P_Valor_Joint', float('nan'))
                valido  = s.get('Joint_Valido', s.get('Modelo_Valido', 'N/A'))
            else:
                # Legado — arquivo gerado antes da refatoração do Kupiec
                p_pof   = s.get('P_Valor', float('nan'))
                p_cc    = float('nan')
                p_joint = float('nan')
                valido  = s.get('Modelo_Valido', 'N/A')

            f_real = s['Falhas_Reais']
            f_esp  = s['Falhas_Esperadas']

            def _fmt(v):
                return f"{v:.4f}" if v == v else "N/A"  # NaN-safe

            subtitle = (
                f"Joint: {valido} | "
                f"POF p={_fmt(p_pof)} | CC p={_fmt(p_cc)} | Joint p={_fmt(p_joint)} | "
                f"Falhas: {f_real} reais vs {f_esp:.2f} esp."
            )
        else:
            subtitle = "Kupiec Stats: N/A"

        # Identifica as violações
        mask_violation = df_t['Delta_Spread'] > df_t['VaR_99']
        df_vio = df_t[mask_violation]
        df_ok = df_t[~mask_violation]
        
        # Plota a linha de base (VaR)
        ax.plot(df_t['Data'], df_t['VaR_99'], color='#c0392b', linewidth=1.5, label='VaR 99% (EGARCH)', linestyle='-')
        
        # Plota os pontos normais
        ax.scatter(df_ok['Data'], df_ok['Delta_Spread'], color='#3498db', s=15, alpha=0.6, label='Delta Spread (Normal)')
        
        # Plota as violações
        if not df_vio.empty:
            ax.scatter(df_vio['Data'], df_vio['Delta_Spread'], color='#e74c3c', s=40, edgecolors='black', marker='X', label='Violação de VaR')
            
            # Adiciona linhas verticais para destaque das violações
            for _, row in df_vio.iterrows():
                ax.axvline(row['Data'], color='#e74c3c', linestyle=':', alpha=0.3)

        ax.set_title(f"{ticker}\n{subtitle}", fontsize=11)
        ax.set_ylabel("Variação (Spread)")
        ax.grid(True, linestyle='--', alpha=0.3)
        ax.legend(loc='upper left', fontsize=9)
        
    axes[0].set_title(f"Validação de VaR 99% (Kupiec POF) no Out-of-Sample\n{axes[0].get_title()}", fontsize=13)
    axes[-1].set_xlabel("Data")
    axes[-1].xaxis.set_major_formatter(mdates.DateFormatter('%Y-%m'))
    plt.setp(axes[-1].xaxis.get_majorticklabels(), rotation=30, ha='right')

    plt.tight_layout()
    
    out_path = str(graficos_dir() / f"{filename_prefix}_kupiec_validation.png")
    plt.savefig(out_path, dpi=300, bbox_inches='tight')
    plt.close()
    logger.info(f"Gráfico de validação salvo em: {out_path}")

if __name__ == "__main__":
    from credit_tail_analytics.utils import dados_dir
    
    res_path = dados_dir() / 'resultado_frequentist_engine.csv'
    kupiec_path = dados_dir() / 'kupiec_test_results.csv'
    
    if res_path.exists() and kupiec_path.exists():
        df_res = pd.read_csv(res_path)
        df_kupiec = pd.read_csv(kupiec_path)
        
        # Seleciona alguns tickers com violações para plotar, se houver
        if 'Falhas_Reais' in df_kupiec.columns:
            tickers_plot = df_kupiec.sort_values(by='Falhas_Reais', ascending=False)['Ticker'].head(3).tolist()
        else:
            tickers_plot = df_res['Ticker'].unique()[:3]
            
        plot_kupiec_validation(df_res, df_kupiec, tickers_plot, str(graficos_dir()))
    else:
        logger.error("Rode o pipeline e o script kupiec_validation.py antes de gerar os gráficos.")
