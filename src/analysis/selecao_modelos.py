import logging
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
        Testa GARCH normal vs EGARCH normal vs EGARCH-t.
        Aplica testes de Ljung-Box e ARCH-LM nos resíduos do modelo campeão.

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
        campeao_obj = None

        logger.info("Iniciando Torneio de Modelos Econométricos...")

        # 1. GARCH(1,1) com distribuição Normal (Modelo Base Clássico)
        res_garch = self._estimar_modelo(
            dados, 'GARCH(1,1) Normal',
            mean='AR', lags=1, vol='GARCH', p=1, q=1, dist='normal'
        )
        resultados.append(res_garch)

        # 2. EGARCH(1,1) com distribuição Normal (Teste de Assimetria de Informação)
        res_egarch_norm = self._estimar_modelo(
            dados, 'EGARCH(1,1) Normal',
            mean='AR', lags=1, vol='EGARCH', p=1, o=1, q=1, dist='normal'
        )
        resultados.append(res_egarch_norm)

        # 3. EGARCH(1,1) com distribuição t-Student (Teste de Cauda Pesada - Nosso Campeão)
        res_egarch_t = self._estimar_modelo(
            dados, 'EGARCH(1,1) t-Student',
            mean='AR', lags=1, vol='EGARCH', p=1, o=1, q=1, dist='studentst'
        )
        resultados.append(res_egarch_t)
        campeao_obj = res_egarch_t.get('modelo_obj')

        # 4. EGARCH(2,1) com distribuição t-Student (Teste de Parcimônia/Overfitting)
        res_egarch_21_t = self._estimar_modelo(
            dados, 'EGARCH(2,1) t-Student',
            mean='AR', lags=1, vol='EGARCH', p=2, o=1, q=1, dist='studentst'
        )
        resultados.append(res_egarch_21_t)

        df_torneio = pd.DataFrame(resultados)
        
        # Isola os metadados brutos do dataframe final
        df_output = df_torneio.drop(columns=['modelo_obj']).copy()
        
        # -----------------------------------------------------------
        # VALIDAÇÃO DO CAMPEÃO: Teste de Resíduos
        # -----------------------------------------------------------
        if campeao_obj is not None:
            logger.info("Executando testes de diagnóstico no modelo EGARCH(1,1) t-Student...")
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
            logger.warning("O modelo vencedor não convergiu. Ignorando testes de diagnóstico.")

        return df_output
