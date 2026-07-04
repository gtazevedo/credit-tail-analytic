import logging
import pandas as pd
from arch import arch_model
from arch.univariate.base import ARCHModelResult

logger = logging.getLogger(__name__)

class MotorEGARCH:
    """
    Motor estatístico de risco de cauda utilizando o modelo AR(1)-EGARCH(1,1) 
    com distribuição t-Student para os resíduos.

    Attributes:
        aic (float | None): Critério de Informação de Akaike do modelo ajustado.
        bic (float | None): Critério de Informação Bayesiano do modelo ajustado.
        modelo_ajustado (ARCHModelResult | None): O resultado completo do ajuste do modelo.
    """

    def __init__(self) -> None:
        """Inicializa o MotorEGARCH preparando os atributos de critérios de informação."""
        self.aic: float | None = None
        self.bic: float | None = None
        self.modelo_ajustado: ARCHModelResult | None = None

    def estimar_volatilidade(self, spread_credito: pd.Series) -> pd.Series:
        """
        Estima a volatilidade condicional da série temporal do spread de crédito.

        Instancia um modelo AR(1)-EGARCH(1,1) com distribuição t-Student. Faz o fit do 
        modelo silenciosamente e extrai os critérios AIC e BIC para justificativa do TCC.

        Args:
            spread_credito (pd.Series): Série temporal contendo o Spread de Crédito diário.

        Returns:
            pd.Series: Série temporal da volatilidade condicional projetada.

        Raises:
            ValueError: Se a série de entrada estiver vazia ou com formato inválido.
            RuntimeError: Se houver falha de convergência do solver numérico do pacote arch.
        """
        if spread_credito.empty:
            raise ValueError("A série temporal de spread de crédito fornecida está vazia.")
        
        # Limpeza preventiva: o arch_model falhará se houver NaNs no meio da série
        dados_limpos = spread_credito.dropna()
        if dados_limpos.empty:
            raise ValueError("A série temporal continha apenas valores nulos.")

        try:
            # Instancia o modelo AR(1) para a média e EGARCH(1,1) para a variância.
            # Os parâmetros p=1, o=1, q=1 configuram os componentes simétrico, 
            # assimétrico e defasado da volatilidade (EGARCH 1,1 com assimetria).
            # A distribuição 'studentst' é fundamental para capturar as caudas pesadas.
            am = arch_model(
                dados_limpos,
                mean='AR',
                lags=1,
                vol='EGARCH',
                p=1,
                o=1,
                q=1,
                dist='studentst'
            )

            # Fit do modelo: disp='off' previne logs excessivos a cada iteração do solver
            res = am.fit(disp='off', options={'maxiter': 1000})

            # Extração e armazenamento dos critérios de informação para o TCC
            self.modelo_ajustado = res
            self.aic = res.aic
            self.bic = res.bic
            
            logger.info(f"Modelo EGARCH ajustado com sucesso. AIC: {self.aic:.2f} | BIC: {self.bic:.2f}")

            # Retorna a série temporal da volatilidade condicional para uso na matriz K-Means
            return res.conditional_volatility

        except Exception as e:
            logger.error(f"Falha de convergência no solver numérico do modelo EGARCH: {e}")
            raise RuntimeError(f"O motor EGARCH não conseguiu atingir a convergência matemática. Detalhes: {e}") from e
