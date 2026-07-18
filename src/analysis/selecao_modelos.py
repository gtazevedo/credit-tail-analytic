import logging
import os
import matplotlib.pyplot as plt
import pandas as pd
from arch import arch_model
from statsmodels.stats.diagnostic import acorr_ljungbox, het_arch

logger = logging.getLogger(__name__)

class ValidadorEconometrico:
    """
    Responsável pelo torneio de modelos e análise de diagnóstico dos resíduos.
    """

    def _estimar_modelo(self, dados: pd.Series, nome_modelo: str, **kwargs) -> dict:
        """
        Função auxiliar para instanciar, estimar o modelo GARCH e capturar exceções numéricas.
        """
        resultado = {
            'Nome do Modelo': nome_modelo,
            'Número de Parâmetros': None,
            'AIC': None,
            'BIC': None,
            'Status de Convergência': 'Falha na Estimação',
            'modelo_obj': None
        }

        try:
            am = arch_model(dados, **kwargs)
            res = am.fit(disp='off', options={'maxiter': 1000})

            resultado['Número de Parâmetros'] = res.num_params
            resultado['AIC'] = res.aic
            resultado['BIC'] = res.bic
            
            # Verificação do status de otimização interno do solver
            if hasattr(res, 'optimization_result'):
                # 0 indica sucesso total no scipy.optimize
                if res.optimization_result.status == 0:
                    resultado['Status de Convergência'] = 'Sucesso'
                else:
                    resultado['Status de Convergência'] = 'Alerta Numérico (Não-Ótimo)'
            else:
                resultado['Status de Convergência'] = 'Sucesso'

            resultado['modelo_obj'] = res
            logger.info(f"Sucesso na estimação do {nome_modelo}. AIC: {res.aic:.2f}")

        except Exception as e:
            logger.error(f"Erro fatal na convergência do {nome_modelo}: {e}")
            resultado['Status de Convergência'] = f"Erro: {str(e)}"

        return resultado

    def comparar_modelos(self, spread_credito: pd.Series) -> pd.DataFrame:
        """
        Executa um torneio econométrico para justificar a escolha metodológica.
        Testa GARCH e EGARCH, normal e t-Student, para p e q de 1 até 3.
        Aplica testes de Ljung-Box e ARCH-LM nos resíduos do modelo campeão (menor AIC).

        Args:
            spread_credito (pd.Series): Série temporal diária de spread do ativo.

        Returns:
            pd.DataFrame: Tabela de auditoria dos modelos testados formatada
                para exportação e citação no documento do TCC.
        """
        if spread_credito.empty:
            raise ValueError("A série temporal informada está vazia.")

        dados = spread_credito.dropna()
        if len(dados) < 50:
            logger.warning("Série muito curta. A estimação GARCH pode ser instável.")

        resultados = []

        logger.info("Iniciando Torneio de Modelos Econométricos (Grid Search)...")

        # Variantes a serem testadas:
        # - GARCH Padrão (Simétrico)
        # - EGARCH (Exponencial, Assimétrico)
        # - GJR-GARCH / TARCH (Assimétrico, power=2)
        # - TARCH (Assimétrico, Absoluto, power=1)
        variantes = [
            {'vol': 'GARCH', 'o': 0, 'power': 2.0, 'nome_base': 'GARCH'},
            {'vol': 'EGARCH', 'o': 1, 'power': 2.0, 'nome_base': 'EGARCH'},
            {'vol': 'GARCH', 'o': 1, 'power': 2.0, 'nome_base': 'GJR-GARCH'},
            {'vol': 'GARCH', 'o': 1, 'power': 1.0, 'nome_base': 'TARCH'}
        ]

        for var in variantes:
            for dist in ['normal', 'studentst']:
                # Limitamos p e q até 2 para manter a performance computacional
                for p in range(1, 3):
                    for q in range(1, 3):
                        dist_name = "Normal" if dist == 'normal' else "t-Student"
                        nome_modelo = f"{var['nome_base']}({p},{var['o']},{q}) {dist_name}"
                        
                        kwargs = {
                            'mean': 'AR', 'lags': 1, 
                            'vol': var['vol'], 'p': p, 'o': var['o'], 'q': q, 
                            'dist': dist, 'rescale': True
                        }
                        
                        # EGARCH não suporta o parâmetro power
                        if var['vol'] != 'EGARCH':
                            kwargs['power'] = var['power']

                        res = self._estimar_modelo(dados, nome_modelo, **kwargs)
                        resultados.append(res)

        df_torneio = pd.DataFrame(resultados)
        
        # Encontra o campeão baseado no menor AIC entre os que convergiram com sucesso
        df_validos = df_torneio[df_torneio['Status de Convergência'] == 'Sucesso']
        if not df_validos.empty:
            idx_campeao = df_validos['AIC'].idxmin()
            campeao = df_validos.loc[idx_campeao]
            campeao_obj = campeao['modelo_obj']
            nome_campeao = campeao['Nome do Modelo']
            logger.info(f"🏆 Modelo Campeão (Menor AIC): {nome_campeao} com AIC={campeao['AIC']:.2f}")
        else:
            campeao_obj = None
            nome_campeao = "Nenhum"

        # Isola os metadados brutos do dataframe final
        df_output = df_torneio.drop(columns=['modelo_obj']).copy()
        
        # -----------------------------------------------------------
        # VALIDAÇÃO DO CAMPEÃO: Teste de Resíduos
        # -----------------------------------------------------------
        if campeao_obj is not None:
            logger.info(f"Executando testes de diagnóstico no modelo {nome_campeao}...")
            try:
                # O arch_model já provê os resíduos padronizados
                residuos = campeao_obj.std_resid.dropna()

                # Teste 1: Autocorrelação Linear Residual (Ljung-Box)
                # H0: Não existe autocorrelação até o lag k. (Desejamos p > 0.05)
                lb_test = acorr_ljungbox(residuos, lags=[10], return_df=True)
                p_valor_lb = lb_test['lb_pvalue'].iloc[0]

                # Teste 2: Heterocedasticidade Condicional Residual (ARCH-LM)
                # H0: Não existe efeito ARCH residual. (Desejamos p > 0.05)
                # A função retorna: estatística LM, p-valor, F-stat, F-pvalor
                lm_stat, p_valor_arch, _, _ = het_arch(residuos, nlags=10)

                status_lb = "PASS" if p_valor_lb > 0.05 else "FAIL (Possui Autocorrelação)"
                status_arch = "PASS" if p_valor_arch > 0.05 else "FAIL (Efeito ARCH Residual)"

                logger.info("=== DIAGNÓSTICO DOS RESÍDUOS PADRONIZADOS ===")
                logger.info(f"Ljung-Box Test (Lag 10) - p-value: {p_valor_lb:.4f} -> {status_lb}")
                logger.info(f"ARCH-LM Test (Lag 10)   - p-value: {p_valor_arch:.4f} -> {status_arch}")
                logger.info("===============================================")

            except Exception as e:
                logger.error(f"Falha ao rodar diagnósticos de resíduos: {e}")
        else:
            logger.warning("Nenhum modelo convergiu com sucesso. Ignorando testes de diagnóstico.")

        return df_output


def run_validador_econometrico(historico_path: str = None, cadastro_path: str = None, split_date: str = '2023-01-01', n_ativos: int = 30):
    """
    Executa o validador econométrico no período de teste para selecionar o melhor modelo GARCH.
    Avalia os N ativos mais líquidos, calcula o AIC/BIC para cada um, e tira a média.
    Exibe um gráfico comparativo e o salva.
    
    Nota: Utiliza o Spread Equivalente Normalizado (Delta_Spread) como série temporal,
    evitando distância de escala entre indexadores (DI% vs DI+ vs IPCA).
    """
    if historico_path is None:
        base_dir = os.path.dirname(__file__)
        historico_path = os.path.abspath(os.path.join(base_dir, "..", "..", "dados", "debentures_historico_bruto.csv"))
    
    if cadastro_path is None:
        base_dir = os.path.dirname(__file__)
        cadastro_path = os.path.abspath(os.path.join(base_dir, "..", "..", "dados", "cadastro_debentures.csv"))

    logger.info(f"Carregando dados históricos de: {historico_path}")
    if not os.path.exists(historico_path):
        logger.error(f"Arquivo não encontrado: {historico_path}")
        return

    df = pd.read_csv(historico_path)
    df['Data'] = pd.to_datetime(df['Data'])
    
    # Carrega cadastro para obter Indexador por ticker
    indexador_map = {}
    if os.path.exists(cadastro_path):
        df_cad = pd.read_csv(cadastro_path, usecols=['Ticker', 'Indexador'])
        indexador_map = df_cad.set_index('Ticker')['Indexador'].to_dict()
        logger.info(f"Cadastro carregado: {len(indexador_map)} indexadores mapeados.")
    else:
        logger.warning("Cadastro não encontrado. Usando Taxa_Ativo bruta como proxy de spread.")
    
    # Carrega CDI para normalização do spread de ativos %DI
    cdi_map = {}
    try:
        base_dir = os.path.dirname(__file__)
        macro_path = os.path.abspath(os.path.join(base_dir, "..", "..", "dados", "macro_data.csv"))
        df_macro = pd.read_csv(macro_path)
        df_macro['Data'] = pd.to_datetime(df_macro['Data'])
        cdi_map = df_macro.set_index('Data')['CDI_Anual'].to_dict()
    except Exception:
        logger.warning("macro_data.csv não encontrado. Usando CDI fixo de 10.4% para normalização.")
    
    def get_spread_normalizado(df_ativo, indexador_str):
        """Calcula o spread equivalente em pontos base, normalizado pelo indexador."""
        idx = str(indexador_str).upper() if indexador_str else 'PRE'
        taxa = df_ativo['Taxa_Ativo'].copy()
        
        if 'DI' in idx and ('PERCENT' in idx or '%' in idx):
            # %DI: converte para spread sobre o CDI usando a taxa do dia
            datas = df_ativo['Data']
            cdi_vals = datas.map(lambda d: cdi_map.get(d, 10.4))
            fator_cdi = (1 + cdi_vals / 100.0) ** (1/252)
            fator_titulo = (fator_cdi - 1) * (taxa / 100.0) + 1
            spread_equiv = (fator_titulo ** 252 - 1) * 100.0 - cdi_vals
            return spread_equiv.diff().dropna()
        else:
            # DI+, IPCA, PRE: taxa já representa o spread ou a taxa excedente.
            return taxa.diff().dropna()
    
    # Filtra o período de teste
    df_teste = df[df['Data'] >= split_date].copy()
    if df_teste.empty:
        logger.error(f"Não há dados disponíveis após o período de teste ({split_date}).")
        return
    
    # Seleciona os top N ativos mais frequentes (proxies de liquidez)
    top_tickers = df_teste['Ticker'].value_counts().head(n_ativos).index.tolist()
    logger.info(f"Selecionados os {n_ativos} ativos mais líquidos para compor o painel de validação.")
    
    validador = ValidadorEconometrico()
    todos_resultados = []
    
    for i, ticker in enumerate(top_tickers, 1):
        logger.info(f"Processando ativo {i}/{n_ativos}: {ticker}")
        df_ativo = df_teste[df_teste['Ticker'] == ticker].sort_values('Data')
        indexador = indexador_map.get(ticker, 'PRE')
        delta_spread = get_spread_normalizado(df_ativo, indexador)
        
        if len(delta_spread) < 50:
            logger.warning(f"{ticker} tem menos de 50 observações no período. Pulando.")
            continue
            
        try:
            df_modelos = validador.comparar_modelos(delta_spread)
            df_modelos['Ticker'] = ticker
            df_modelos['Indexador'] = indexador
            todos_resultados.append(df_modelos)
        except Exception as e:
            logger.error(f"Erro ao processar {ticker}: {e}")
            
    if not todos_resultados:
        logger.error("Nenhum modelo pôde ser estimado com sucesso.")
        return
        
    df_all = pd.concat(todos_resultados, ignore_index=True)
    
    # Filtra apenas os que convergiram
    df_validos = df_all[df_all['Status de Convergência'] == 'Sucesso'].copy()
    
    if df_validos.empty:
        logger.error("Nenhum modelo convergiu com sucesso em todos os testes.")
        return
        
    # AIC e BIC absolutos dependem da variância e da 
    # escala de cada série temporal, portanto se aplica um "Ranking Médio" ou "Win Rate" (Vitórias).
    
    # Rankeia os modelos dentro de CADA ativo separadamente (Menor AIC = Rank 1)
    df_validos['Rank_AIC'] = df_validos.groupby('Ticker')['AIC'].rank(method='min')
    df_validos['Rank_BIC'] = df_validos.groupby('Ticker')['BIC'].rank(method='min')
    
    # Agrega por Modelo
    df_agg = df_validos.groupby('Nome do Modelo').agg(
        Rank_Medio_AIC=('Rank_AIC', 'mean'),
        Rank_Medio_BIC=('Rank_BIC', 'mean'),
        Vitorias_AIC=('Rank_AIC', lambda x: (x == 1).sum()),
        Total_Convergencias=('Rank_AIC', 'count')
    ).reset_index()
    
    df_agg['Win_Rate_AIC_%'] = (df_agg['Vitorias_AIC'] / len(top_tickers)) * 100
    
    # Ordena pelo melhor Rank Médio de AIC (quanto menor o rank, melhor)
    df_plot = df_agg.sort_values(by='Rank_Medio_AIC').set_index('Nome do Modelo')
    
    logger.info("Torneio concluído. Melhores modelos por Ranking Médio (AIC):")
    logger.info(f"\n{df_plot[['Rank_Medio_AIC', 'Win_Rate_AIC_%', 'Total_Convergencias']].head().to_string()}")
    
    plt.figure(figsize=(14, 7))
    
    x = range(len(df_plot))
    width = 0.35
    
    # Gráfico de barras lado a lado para Rank Médio (AIC e BIC)
    plt.bar([pos - width/2 for pos in x], df_plot['Rank_Medio_AIC'], width, label='Rank Médio AIC', color='skyblue')
    plt.bar([pos + width/2 for pos in x], df_plot['Rank_Medio_BIC'], width, label='Rank Médio BIC', color='salmon')
    
    plt.ylabel('Posição Média no Ranking (1 = Melhor, Menor é Melhor)')
    plt.title(f'Torneio GARCH: Ranking Médio dos Modelos ({n_ativos} Ativos)\nPeríodo de Teste (>= {split_date})')
    plt.xticks(x, df_plot.index, rotation=45, ha="right")
    
    # Adiciona o Win Rate em texto em cima das barras de AIC
    for i, v in enumerate(df_plot['Win_Rate_AIC_%']):
        plt.text(i - width/2, df_plot['Rank_Medio_AIC'].iloc[i] + 0.1, f"{v:.1f}%\nWins", 
                 ha='center', va='bottom', fontsize=9, fontweight='bold', color='darkblue')
                 
    plt.legend()
    plt.grid(axis='y', linestyle='--', alpha=0.7)
    plt.tight_layout()
    
    # Salvar e mostrar o gráfico
    grafico_path = os.path.join(os.path.dirname(historico_path), f"comparacao_modelos_ranking_n{n_ativos}.png")
    plt.savefig(grafico_path)
    logger.info(f"Gráfico salvo em: {grafico_path}")
    
    #plt.show()

if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')
    run_validador_econometrico(n_ativos=2000)
    run_validador_econometrico(n_ativos=3000)
    run_validador_econometrico(n_ativos=5000)
