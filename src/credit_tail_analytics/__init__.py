"""
credit_tail_analytics
=====================
Motor quantitativo de risco de cauda para debêntures brasileiras.

Compara K-Means (baseline atemporal) com Hidden Markov Models (modelo proposto
com memória temporal) para classificação de regime de crédito, segmentado por
grupo de indexador (CDI+, IPCA, %CDI, etc.).

Uso rápido
----------
>>> from credit_tail_analytics.models.credit_risk.risk_pipeline import CreditRiskEngine
>>> from credit_tail_analytics.models.credit_risk.run_frequentist_engine import run_frequentist_pipeline
>>> from credit_tail_analytics.visualization.frequentist_defense_visuals import run_defense_visuals

Comando CLI (após instalação)
-----------------------------
    credit-risk-engine --model_type both --split_date 2023-01-01
"""

__version__ = "1.0.0"
__author__  = "Guilherme Azevedo"
__email__   = "guilherme.tt.azevedo@gmail.com"
__license__ = "MIT"

# Exports públicos de alto nível
from credit_tail_analytics.models.credit_risk.risk_pipeline import CreditRiskEngine
from credit_tail_analytics.models.credit_risk.feature_selection import FeatureSelector
from credit_tail_analytics.models.credit_risk.run_frequentist_engine import run_frequentist_pipeline
from credit_tail_analytics.analysis.selecao_modelos import (
    ValidadorEconometrico,
    recommend_garch_spec,
    run_validador_econometrico,
)
from credit_tail_analytics.visualization.frequentist_defense_visuals import run_defense_visuals

__all__ = [
    "CreditRiskEngine",
    "FeatureSelector",
    "run_frequentist_pipeline",
    "ValidadorEconometrico",
    "recommend_garch_spec",
    "run_validador_econometrico",
    "run_defense_visuals",
]
