= Processamento/Tratamento de Dados <sec_processamento>

O tratamento dos dados de negociação mitiga distorções decorrentes da baixa liquidez, descontinuidades temporais observadas nas séries obtidas e utilização de diferentes indexadores. Para sanar esta necessidade, a massa de dados bruta 
passou por etapas sequenciais de filtragem de liquidez, harmonização de taxas contratuais, engenharia de atributos, tratamento de valores discrepantes (_outliers_) e escalonamento geométrico.

== Divisão Temporal e Filtro de Iliquidez

Os registros foram particionados em dois intervalos cronológicos disjuntos:

- Período de Treinamento (_In-Sample_): De 2 de janeiro de 2018 a 30 de dezembro de 2022. Esta janela serviu para calibrar os parâmetros dos modelos GARCH, selecionar os subconjuntos de variáveis e determinar as matrizes de transição dos regimes;
- Período de Teste e Validação (_Out-of-Sample_): De 2 de janeiro de 2023 a 10 de julho de 2026. Esta janela serviu para executar o teste de antecipação (_Early Warning_) e simular as estratégias de investimento sob condições reais de mercado.

A iliquidez observada no mercado secundário de debêntures impõe extensos intervalos sem negociação, porém, o sistema REUNE/ANBIMA se limita a estratificar o volume diário negociado em 3 faixas ordinais, classificando a Faixa 3 como "Até 1MM". 
Para os fins desta modelagem, visando mitigar vieses decorrentes de extensos períodos sem negociação, os títulos com concentração quase absoluta nessa faixa foram delimitados como cronicamente ilíquidos.
Para isso, desenvolveu-se uma rotina algorítmica de tratamento que, quando habilitada, remove da base de dados para treinamento (posteriormente detalhada em @subcap_processamento) os ativos que permaneceram como ilíquidos durante 
um período igual ou superior a 95% da amostra. O propósito dessa funcionalidade é impedir que, caso sejam observados
eventos de variação de _spread_ espúrios devido à baixa liquidez, eles sejam propagados para o modelo EGARCH, o que poderia corromper a estimação da persistência e dos choques 
(parâmetros $alpha$ e $beta$) da variância condicional. Esses títulos foram excluídos exclusivamente da amostra de calibração, à exceção do ativo RDVT11, removido integralmente de toda a base. Isso ocorreu devido ao fato de que o título não possuía 
cotações no período de treinamento e apresentou variações extremas e esparsas (negociado a PU 1.001,77 em dezembro de 2023, recuando para 1,40 e 0,000014 em março de 2024 antes de retornar a 754,31 em 2025), refletindo a recuperação 
judicial e a reestruturação societária do emissor.

== Harmonização de Taxas e Engenharia de Atributos <subcap_processamento>

A base abrange três categorias contratuais de remuneração: debêntures indexadas a percentual do CDI, debêntures atreladas ao CDI acrescidas de spread e debêntures indexadas a índices de preços (IPCA+). Cada contrato exige tratamento específico para 
isolar o prêmio de risco de crédito.

Para os ativos emitidos a um percentual do CDI (ex.: 120% do DI), realizou-se uma conversão explícita baseada na taxa CDI diária apurada pelo Banco Central, isolando o prêmio excedente sobre a taxa livre de risco:

$ F_"cdi" = (1 + "CDI"_t / 100)^(1/252) $

$ F_"titulo" = (F_"cdi" - 1) times ("Taxa do Ativo"_t / 100) + 1 $

$ S_t = ( (F_"titulo")^252 - 1 ) times 100 - "CDI"_t $

Nos contratos atrelados a inflação (IPCA+) ou sobretaxa direta sobre o DI (DI+), o spread bruto informado pelo mercado secundário já expressa diretamente o prêmio de crédito: $S_t = "Taxa do Ativo"_t$.

A partir dos spreads homogêneos, derivou-se um conjunto de variáveis preditivas voltadas à captura de choques temporais e de dispersão intra-diária. A dinâmica de curto prazo foi representada pela variação diária do spread ($Delta S_t$), 
que serve de entrada ao motor de volatilidade condicional:
$ Delta S_t = S_t - S_(t-1) $ <eq_delta_spread>

Diante da ausência de dados uniformes de duration modificada para a totalidade dos ativos transacionados, mitigou-se a sensibilidade temporal deflacionando o spread pelo logaritmo do prazo remanescente até o vencimento:
$ "Taxa"_"prazo" = S_t / ln(max("DU", 2)) $ <eq_taxa_prazo>

Adicionalmente, computou-se o Z-Score causal do spread em janela móvel de 60 dias úteis, parametrizando a distância da taxa observada em relação à média e ao desvio-padrão históricos do próprio ativo.

Além disso, a dispersão das cotações na sessão foi sintetizada por meio da amplitude intraday ($S_("range")$) e da assimetria relativa dos negócios ($S_("skew")$):
$ S_("range") = "Taxa"_"max" - "Taxa"_"min" $
$ S_("skew") = ("Taxa"_"med" - "Taxa"_"min") / (S_("range") + epsilon) $
adotando-se $epsilon = 10^(-6)$ para blindar o cálculo contra indeterminações divisionais em dias de cotação estática.


== Tratamento de Discrepâncias e Normalização

A contenção de valores anômalos e ruídos operacionais adotou winsorização bilateral restrita aos percentis 1% e 99%, parametrizada exclusivamente sobre o subconjunto _In-Sample_ e subsequentemente mantida para aplicação aos dados _Out-of-Sample_, 
salvaguardando a metodologia contra vazamento de informação retrospectiva (_look-ahead bias_).

Para o escalonamento das features, optou-se pelo estimador robusto de #cite(<rousseeuw2011robust>, form: "prose") (`RobustScaler`), que centraliza os dados na mediana e utiliza o intervalo interquartil ($"IQR" = Q_3 - Q_1$), de forma a prevenir que debêntures com aberturas bruscas de taxa
comprimam artificialmente a escala dos demais instrumentos. Também foi utilizado um limiar mínimo de dispersão equivalente a 10% do IQR mediano de cada classe de indexador, evitando divisões por zero em ativos com baixa volatilidade.

== Implementação em Código-Fonte

A arquitetura dessa etapa concentra-se no módulo `src/credit_tail_analytics/models/credit_risk/preprocessor.py`, no qual a classe `DataPreprocessor` consolida as rotinas de limpeza, separação contábil de indexadores e transformação das séries:

```python
import numpy as np
import pandas as pd
from typing import Dict

class DataPreprocessor:
    """Higienização, harmonização de taxas e engenharia de atributos."""
    
    def __init__(self, filter_low_liquidity: bool = True, split_date: str = '2023-01-01'):
        self.filter_low_liquidity = filter_low_liquidity
        self.split_date = pd.to_datetime(split_date)

    def process(self, df: pd.DataFrame) -> pd.DataFrame:
        df = df.copy()
        # Expulsa ativos com falhas crônicas de marcação (ex.: reorganização judicial)
        if 'Ticker' in df.columns:
            df = df[df['Ticker'] != 'RDVT11'].copy()
            
        df['Data'] = pd.to_datetime(df['Data'])
        df.sort_values(by=['Ticker', 'Data'], inplace=True)
        
        # 1. Reclassificação de indexador via médias estritamente In-Sample (sem look-ahead bias)
        mask_is = df['Data'] < self.split_date
        medias_is = df[mask_is].groupby('Ticker')['Taxa_Ativo'].mean()
        medias_full = df.groupby('Ticker')['Taxa_Ativo'].transform('mean')
        medias_taxa = df['Ticker'].map(medias_is).fillna(medias_full)

        is_di = df['Indexador'].str.upper() == 'DI'
        df.loc[is_di & (medias_taxa > 30), 'Indexador'] = 'DI_Percentual'
        df.loc[is_di & (medias_taxa <= 30), 'Indexador'] = 'DI_Spread'

        # 2. Spread equivalente: capitalização composta para DI% e spread direto para IPCA/DI+
        taxa, cdi = df['Taxa_Ativo'], df['CDI_Anual']
        fator_cdi = (1 + cdi / 100.0) ** (1 / 252)
        fator_tit = (fator_cdi - 1) * (taxa / 100.0) + 1
        spread_pct = ((fator_tit ** 252) - 1) * 100.0 - cdi

        is_pct = df['Indexador'].str.upper() == 'DI_PERCENTUAL'
        is_puro = df['Indexador'].str.upper().isin(['DI_SPREAD', 'IPCA', 'IGPM'])
        df['Spread_Equivalente'] = np.where(is_pct, spread_pct, np.where(is_puro, taxa, taxa - cdi))

        # 3. Taxa ajustada ao prazo e Delta Spread
        df['Taxa_Ajustada_Prazo'] = df['Spread_Equivalente'] / np.log(np.maximum(df['DU_Vencimento'], 2))
        df['Delta_Spread'] = df.groupby('Ticker')['Spread_Equivalente'].diff()

        # 4. Z-Score com janela móvel de 60 dias úteis
        roll = df.groupby('Ticker')['Spread_Equivalente'].rolling(window=60, min_periods=10)
        m = roll.mean().reset_index(level=0, drop=True)
        s = roll.std().reset_index(level=0, drop=True).replace(0, np.nan)
        df['Taxa_ZScore'] = ((df['Spread_Equivalente'] - m) / s).fillna(0.0)

        # 5. Métricas de microestrutura intraday (Range e Skew)
        df['Spread_Range_Intraday'] = df['Taxa_Maxima'] - df['Taxa_Minima']
        df['Spread_Skew_Intraday'] = (df['Taxa_Ativo'] - df['Taxa_Minima']) / (df['Spread_Range_Intraday'] + 1e-6)

        # 6. Remoção de ativos ilíquidos (>= 95% do In-Sample na Faixa 3)
        if self.filter_low_liquidity:
            df_is = df[df['Data'] < self.split_date]
            mask_faixa3 = df_is['Faixa_Volume_ANBIMA'] == 'Até 1MM'
            taxa_iliq = mask_faixa3.groupby(df_is['Ticker']).mean()
            banidos = taxa_iliq[taxa_iliq >= 0.95].index
            df = df[~df['Ticker'].isin(banidos)].reset_index(drop=True)

        return df
```
