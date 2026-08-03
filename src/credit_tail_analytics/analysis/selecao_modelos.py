import logging
import os
import warnings
import matplotlib.pyplot as plt
import pandas as pd
import numpy as np
from arch import arch_model
from statsmodels.stats.diagnostic import acorr_ljungbox, het_arch
from typing import Optional
from credit_tail_analytics.utils import dados_dir, graficos_dir

# Suprime avisos esperados do otimizador SLSQP (scipy code 4 = constraints incompatible)
# e de algebra linear. São capturados pelo check de optimization_result.status.
warnings.filterwarnings('ignore', message='.*optimizer returned code.*')
warnings.filterwarnings('ignore', category=RuntimeWarning)
try:
    from scipy.optimize import OptimizeWarning
    warnings.filterwarnings('ignore', category=OptimizeWarning)
except ImportError:
    pass

logger = logging.getLogger(__name__)


class ValidadorEconometrico:
    """
    Responsável pelo torneio de modelos GARCH e análise de diagnóstico dos resíduos.
    Testa múltiplas variantes de GARCH/EGARCH com distribuições Normal e t-Student,
    usando o critério AIC para rankear os modelos campeões.
    """

    def _estimar_modelo(self, dados: pd.Series, nome_modelo: str, **kwargs) -> dict:
        """
        Instancia, estima o modelo GARCH e captura exceções numéricas.

        Retorna um dicionário com as métricas de informação e o objeto de resultado.
        """
        resultado = {
            'Nome do Modelo':           nome_modelo,
            'Número de Parâmetros':     None,
            'AIC':                      None,
            'BIC':                      None,
            'Status de Convergência':   'Falha na Estimação',
            'modelo_obj':               None,
        }
        try:
            am  = arch_model(dados, **kwargs)
            res = am.fit(disp='off', options={'maxiter': 1000})

            resultado['Número de Parâmetros'] = res.num_params
            resultado['AIC']                  = res.aic
            resultado['BIC']                  = res.bic

            if hasattr(res, 'optimization_result') and res.optimization_result.status == 0:
                resultado['Status de Convergência'] = 'Sucesso'
            else:
                resultado['Status de Convergência'] = (
                    'Sucesso' if not hasattr(res, 'optimization_result')
                    else 'Alerta Numérico (Não-Ótimo)'
                )

            resultado['modelo_obj'] = res
            logger.info(f"✓ {nome_modelo} | AIC={res.aic:.2f} | BIC={res.bic:.2f}")

        except Exception as e:
            logger.error(f"✗ {nome_modelo}: {e}")
            resultado['Status de Convergência'] = f"Erro: {str(e)}"

        return resultado

    def comparar_modelos(self, spread_credito: pd.Series) -> pd.DataFrame:
        """
        Torneio econométrico: testa GARCH, EGARCH, GJR-GARCH e TARCH com
        distribuições Normal e t-Student (p, q de 1 a 2).

        Aplica Ljung-Box e ARCH-LM nos resíduos do modelo campeão (menor AIC).

        Parâmetros
        ----------
        spread_credito : pd.Series
            Série temporal diária de Delta_Spread ou retorno do ativo.

        Retorna
        -------
        pd.DataFrame
            Tabela de auditoria dos modelos testados (sem a coluna 'modelo_obj').
        """
        if spread_credito.empty:
            raise ValueError("A série temporal informada está vazia.")

        dados = spread_credito.dropna()
        if len(dados) < 50:
            logger.warning("Série curta (<50 obs). Estimação GARCH pode ser instável.")

        variantes = [
            {'vol': 'GARCH',  'o': 0, 'power': 2.0, 'nome_base': 'GARCH'},
            {'vol': 'EGARCH', 'o': 1,                'nome_base': 'EGARCH'},
            {'vol': 'GARCH',  'o': 1, 'power': 2.0, 'nome_base': 'GJR-GARCH'},
            {'vol': 'GARCH',  'o': 1, 'power': 1.0, 'nome_base': 'TARCH'},
        ]

        resultados = []
        logger.info("Iniciando Torneio de Modelos GARCH (Grid Search)...")

        for var in variantes:
            for dist in ['normal', 'studentst']:
                for p in range(1, 3):
                    for q in range(1, 3):
                        dist_name  = "Normal" if dist == 'normal' else "t-Student"
                        o_val      = var.get('o', 0)
                        nome       = f"{var['nome_base']}({p},{o_val},{q}) {dist_name}"

                        kwargs = {
                            'mean': 'AR', 'lags': 1,
                            'vol': var['vol'], 'p': p, 'o': o_val, 'q': q,
                            'dist': dist, 'rescale': True,
                        }
                        if var['vol'] != 'EGARCH' and 'power' in var:
                            kwargs['power'] = var['power']

                        resultados.append(self._estimar_modelo(dados, nome, **kwargs))

        df_torneio = pd.DataFrame(resultados)

        # --- Diagnóstico do campeão ---
        df_validos = df_torneio[df_torneio['Status de Convergência'] == 'Sucesso']
        campeao_obj   = None
        nome_campeao  = "Nenhum"

        if not df_validos.empty:
            idx_campeao  = df_validos['AIC'].idxmin()
            campeao      = df_validos.loc[idx_campeao]
            campeao_obj  = campeao['modelo_obj']
            nome_campeao = campeao['Nome do Modelo']
            logger.info(f"🏆 Campeão: {nome_campeao} | AIC={campeao['AIC']:.2f}")

        if campeao_obj is not None:
            try:
                residuos    = campeao_obj.std_resid.dropna()
                lb_test     = acorr_ljungbox(residuos, lags=[10], return_df=True)
                p_valor_lb  = lb_test['lb_pvalue'].iloc[0]
                _, p_valor_arch, _, _ = het_arch(residuos, nlags=10)

                logger.info("=== DIAGNÓSTICO DOS RESÍDUOS PADRONIZADOS ===")
                logger.info(
                    f"Ljung-Box (Lag 10) p={p_valor_lb:.4f} → "
                    f"{'PASS' if p_valor_lb > 0.05 else 'FAIL (autocorrelação)'}"
                )
                logger.info(
                    f"ARCH-LM   (Lag 10) p={p_valor_arch:.4f} → "
                    f"{'PASS' if p_valor_arch > 0.05 else 'FAIL (efeito ARCH residual)'}"
                )
                logger.info("=============================================")
            except Exception as e:
                logger.error(f"Falha nos testes de diagnóstico: {e}")

        return df_torneio.drop(columns=['modelo_obj']).copy()


def recommend_garch_spec(df_torneio: pd.DataFrame) -> dict:
    """
    Extrai o modelo campeão do torneio (maior Win Rate AIC ou menor Rank) e retorna
    os parâmetros recomendados como dicionário pronto para `arch_model`.

    Parâmetros
    ----------
    df_torneio : pd.DataFrame
        DataFrame retornado por `run_validador_econometrico()` (com a coluna 'Win_Rate_AIC_%', 
        'Rank_Medio_AIC' ou 'AIC').

    Retorna
    -------
    dict
        Ex.: {'vol': 'EGARCH', 'p': 1, 'o': 1, 'q': 1, 'dist': 'studentst'}
        Retorna o spec padrão (EGARCH(1,1,1) t-Student) se o parsing falhar.
    """
    DEFAULT_SPEC = {'vol': 'EGARCH', 'p': 1, 'o': 1, 'q': 1, 'dist': 'studentst'}

    if 'Win_Rate_AIC_%' in df_torneio.columns:
        rank_col = 'Win_Rate_AIC_%'
        ascending_order = False
    elif 'Rank_Medio_AIC' in df_torneio.columns:
        rank_col = 'Rank_Medio_AIC'
        ascending_order = True
    else:
        rank_col = 'AIC'
        ascending_order = True

    if 'Status de Convergência' in df_torneio.columns:
        df_validos = df_torneio[df_torneio['Status de Convergência'] == 'Sucesso'].copy()
    else:
        df_validos = df_torneio.copy()

    if df_validos.empty:
        logger.warning("[recommend_garch_spec] Nenhum modelo válido. Usando spec padrão.")
        return DEFAULT_SPEC

    best_name = df_validos.sort_values(rank_col, ascending=ascending_order).iloc[0]['Nome do Modelo']

    try:
        # Parsing do nome: "EGARCH(1,1,1) t-Student"
        vol_raw, rest = best_name.split('(', 1)
        vol_raw = vol_raw.strip()
        params_str, dist_str = rest.split(')', 1)
        p, o, q = [int(x.strip()) for x in params_str.split(',')]
        dist = 'studentst' if 't-Student' in dist_str else 'normal'

        vol_map = {
            'GARCH':     'GARCH',
            'EGARCH':    'EGARCH',
            'GJR-GARCH': 'GARCH',
            'TARCH':     'GARCH',
        }
        vol  = vol_map.get(vol_raw, 'EGARCH')
        spec = {'vol': vol, 'p': p, 'o': o, 'q': q, 'dist': dist}

        # GJR-GARCH e TARCH usam parâmetro power
        if vol_raw == 'GJR-GARCH':
            spec['power'] = 2.0
        elif vol_raw == 'TARCH':
            spec['power'] = 1.0

        logger.info(f"[recommend_garch_spec] Spec recomendado: {spec} (modelo: {best_name})")
        return spec

    except Exception as e:
        logger.warning(f"[recommend_garch_spec] Erro ao parsear '{best_name}': {e}. Usando padrão.")
        return DEFAULT_SPEC


def run_validador_econometrico(
    historico_path:       Optional[str] = None,
    cadastro_path:        Optional[str] = None,
    split_date:           str  = '2023-01-01',
    n_ativos:             int  = 30,
    filter_low_liquidity: bool = False,
) -> tuple:
    """
    Executa o torneio GARCH nos N ativos mais líquidos do período de teste.

    Parâmetros
    ----------
    historico_path : str, optional
        Caminho para o CSV histórico. Usa path padrão se None.
    cadastro_path : str, optional
        Caminho para o CSV de cadastro. Usa path padrão se None.
    split_date : str
        Data de corte; usa apenas dados < split_date para o torneio.
    n_ativos : int
        Número de ativos mais líquidos a avaliar.
    filter_low_liquidity : bool, default True
        Quando True, exclui ativos ou dias com volume "Até 1MM" (Faixa 3 ANBIMA)
        antes de calcular o Delta_Spread para o torneio.

    Retorna
    -------
    (df_agg, garch_spec) : (pd.DataFrame, dict)
        df_agg    — Tabela de ranking médio dos modelos por AIC/BIC.
        garch_spec — Dict com o spec do modelo campeão (pronto para arch_model).
    """
    if historico_path is None:
        historico_path = str(dados_dir() / 'debentures_historico_bruto.csv')
    if cadastro_path is None:
        cadastro_path = str(dados_dir() / 'cadastro_debentures.csv')

    logger.info(f"Carregando histórico: {historico_path}")
    if not os.path.exists(historico_path):
        logger.error(f"Arquivo não encontrado: {historico_path}")
        return pd.DataFrame(), {}

    df = pd.read_csv(historico_path)
    df['Data'] = pd.to_datetime(df['Data'])

    # Mapa de indexadores
    indexador_map = {}
    if os.path.exists(cadastro_path):
        df_cad = pd.read_csv(cadastro_path, usecols=lambda c: c in ['Ticker', 'Indexador'])
        indexador_map = df_cad.set_index('Ticker')['Indexador'].to_dict()
        logger.info(f"Cadastro: {len(indexador_map)} indexadores mapeados.")
    else:
        logger.warning("Cadastro não encontrado. Usando Taxa_Ativo bruta como proxy.")

    # Mapa de CDI para normalização
    cdi_map = {}
    try:
        base_dir  = os.path.dirname(__file__)
        macro_path = str(dados_dir() / 'macro_data.csv')
        df_macro  = pd.read_csv(macro_path)
        df_macro['Data'] = pd.to_datetime(df_macro['Data'])
        cdi_map   = df_macro.set_index('Data')['CDI_Anual'].to_dict()
    except Exception:
        logger.warning("macro_data.csv não encontrado. Usando CDI fixo 10.4%.")

    def get_spread_normalizado(df_ativo: pd.DataFrame, indexador_str: str) -> pd.Series:
        """Calcula Delta_Spread normalizado pelo indexador."""
        idx  = str(indexador_str).upper() if indexador_str else 'PRE'
        taxa = df_ativo['Taxa_Ativo'].copy()

        if 'DI' in idx and ('PERCENT' in idx or '%' in idx):
            datas      = df_ativo['Data']
            cdi_vals   = datas.map(lambda d: cdi_map.get(d, 10.4))
            fator_cdi  = (1 + cdi_vals / 100.0) ** (1 / 252)
            fator_tit  = (fator_cdi - 1) * (taxa / 100.0) + 1
            spread_eq  = (fator_tit ** 252 - 1) * 100.0 - cdi_vals
            return spread_eq.diff().dropna()
        else:
            return taxa.diff().dropna()

    # Filtra período de teste e aplica filtro de liquidez
    df_teste = df[df['Data'] < split_date].copy()
    if filter_low_liquidity and 'Faixa_Volume_ANBIMA' in df_teste.columns:
        n_antes = len(df_teste)
        df_teste = df_teste[df_teste['Faixa_Volume_ANBIMA'] != 'Até 1MM'].copy()
        logger.info(
            f"Filtro de liquidez (torneio GARCH): {n_antes - len(df_teste)} "
            "observações 'Até 1MM' removidas."
        )

    if df_teste.empty:
        logger.error(f"Sem dados após {split_date}.")
        return pd.DataFrame(), {}

    top_tickers = df_teste['Ticker'].value_counts().head(n_ativos).index.tolist()
    logger.info(f"Top {n_ativos} ativos selecionados para o torneio.")

    validador      = ValidadorEconometrico()
    todos_resultados = []

    for i, ticker in enumerate(top_tickers, 1):
        logger.info(f"  {i}/{n_ativos}: {ticker}")
        df_ativo   = df_teste[df_teste['Ticker'] == ticker].sort_values('Data')
        indexador  = indexador_map.get(ticker, 'PRE')
        delta_spread = get_spread_normalizado(df_ativo, indexador)

        if len(delta_spread) < 50:
            logger.warning(f"  {ticker}: <50 obs. Pulando.")
            continue

        try:
            df_modelos = validador.comparar_modelos(delta_spread)
            df_modelos['Ticker']    = ticker
            df_modelos['Indexador'] = indexador
            todos_resultados.append(df_modelos)
        except Exception as e:
            logger.error(f"  {ticker}: {e}")

    if not todos_resultados:
        logger.error("Nenhum modelo estimado com sucesso.")
        return pd.DataFrame(), {}

    df_all    = pd.concat(todos_resultados, ignore_index=True)
    df_validos = df_all[df_all['Status de Convergência'] == 'Sucesso'].copy()

    if df_validos.empty:
        logger.error("Nenhum modelo convergiu.")
        return pd.DataFrame(), {}

    df_validos['Rank_AIC'] = df_validos.groupby('Ticker')['AIC'].rank(method='min')
    df_validos['Rank_BIC'] = df_validos.groupby('Ticker')['BIC'].rank(method='min')

    df_agg = df_validos.groupby('Nome do Modelo').agg(
        Rank_Medio_AIC=('Rank_AIC', 'mean'),
        Rank_Medio_BIC=('Rank_BIC', 'mean'),
        Vitorias_AIC=('Rank_AIC', lambda x: (x == 1).sum()),
        Total_Convergencias=('Rank_AIC', 'count'),
    ).reset_index()

    df_agg['Win_Rate_AIC_%'] = (df_agg['Vitorias_AIC'] / len(top_tickers)) * 100
    #df_plot = df_agg.sort_values('Rank_Medio_AIC').set_index('Nome do Modelo')
    df_plot = df_agg.sort_values('Win_Rate_AIC_%', ascending=False).set_index('Nome do Modelo')

    logger.info(
        f"Torneio concluído. Top 5 modelos:\n"
        f"{df_plot[['Rank_Medio_AIC', 'Win_Rate_AIC_%', 'Total_Convergencias']].head().to_string()}"
    )

    # Extrai spec do campeão
    garch_spec = recommend_garch_spec(df_agg.rename(columns={'Nome do Modelo': 'Nome do Modelo'}))

    # Gráfico comparativo
    fig, ax = plt.subplots(figsize=(14, 7))
    x     = range(len(df_plot))
    width = 0.35

    ax.bar([p - width / 2 for p in x], df_plot['Rank_Medio_AIC'],
           width, label='Rank Médio AIC', color='#4a90d9')
    ax.bar([p + width / 2 for p in x], df_plot['Rank_Medio_BIC'],
           width, label='Rank Médio BIC', color='#e07b54')

    for i, v in enumerate(df_plot['Win_Rate_AIC_%']):
        ax.text(
            i - width / 2, df_plot['Rank_Medio_AIC'].iloc[i] + 0.1,
            f"{v:.1f}%\nWins",
            ha='center', va='bottom', fontsize=8, fontweight='bold', color='#1a3a5c'
        )

    ax.set_ylabel('Posição Média no Ranking (1 = Melhor)')
    ax.set_title(
        f'Torneio GARCH: Ranking Médio dos Modelos ({n_ativos} Ativos)\n'
        f'Período de Teste (< {split_date})'
        + (' — Faixa 3 ANBIMA Excluída' if filter_low_liquidity else '')
    )
    ax.set_xticks(x)
    ax.set_xticklabels(df_plot.index, rotation=45, ha='right')
    ax.legend()
    ax.grid(axis='y', linestyle='--', alpha=0.7)
    plt.tight_layout()

    grafico_path = str(graficos_dir() / f'comparacao_modelos_ranking_n{n_ativos}_{filter_low_liquidity}.png')
    plt.savefig(grafico_path, dpi=150)
    plt.close()
    logger.info(f"Gráfico salvo em: {grafico_path}")

    return df_agg, garch_spec


if __name__ == '__main__':
    logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')
    for n_ativos in [30, 50, 100, 500, 1000, 3000, 5000]:
        df_agg, spec = run_validador_econometrico(n_ativos=n_ativos, filter_low_liquidity=False)
        df_agg, spec = run_validador_econometrico(n_ativos=n_ativos, filter_low_liquidity=True)
        print("\nSpec GARCH recomendado:", spec)
