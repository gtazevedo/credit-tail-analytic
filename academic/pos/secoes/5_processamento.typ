= Processamento/Tratamento de Dados <sec_processamento>

A preparação dos dados assegura que as estimativas econométricas e as classificações estatísticas reflitam dinâmicas reais de mercado, e não ruídos de liquidez fragmentada. A massa de dados bruta passou por etapas sequenciais de filtragem de liquidez, harmonização de 
taxas contratuais, engenharia de atributos, tratamento de valores discrepantes (_outliers_) e escalonamento geométrico.

== Divisão Temporal e Filtro de Iliquidez

Os registros foram particionados em dois intervalos cronológicos disjuntos:

- Período de Treinamento (_In-Sample_): De 2 de janeiro de 2018 a 30 de dezembro de 2022. Esta janela serviu para calibrar os parâmetros dos modelos GARCH, selecionar os subconjuntos de variáveis e determinar as matrizes de transição dos regimes;
- Período de Teste e Validação (_Out-of-Sample_): De 2 de janeiro de 2023 a 10 de julho de 2026. Esta janela serviu para executar o teste de antecipação (_Early Warning_) e simular as estratégias de investimento sob condições reais de mercado.

Como citado na @problemas_pesquisa, um desafio inerente ao mercado secundário de crédito privado brasileiro é a baixa liquidez dos ativos, inclusive com alguns chegando a registrar
dias sem negociação. A ANBIMA classifica o volume de negociação, no sistema de informações consultado, em faixas, sendo a faixa mais baixa dada por "Até 1MM"; portanto, considerando as informações disponíveis durante a realização desta pesquisa,
esses são os ativos definidos como ilíquidos. Para lidar com essa característica, desenvolveu-se uma rotina algorítmica de tratamento que, quando habilitada, 
remove da base de dados para treinamento (que será detalhada posteriormente em @subcap_processamento) os ativos que permaneceram como ilíquidos durante um período igual ou superior a 95% da amostra.
O propósito dessa funcionalidade é impedir que, caso sejam observados
eventos de variação de _spread_ espúrios devido à baixa liquidez, eles sejam propagados para o modelo EGARCH, o que poderia corromper a estimação da persistência e dos choques 
(parâmetros $alpha$ e $beta$) da variância condicional. Esses ativos foram removidos apenas da amostra de calibração, com a exceção de RDVT11, que foi removido manualmente de toda a base
devido aos seguintes fatores:
- O ativo não tinha dados de negociação durante a etapa de treinamento, então seria considerado posteriormente, mesmo ilíquido;
- A série de preços do ativo apresenta grandes variações, com espaçamento elevado entre os dados, o que pode introduzir vieses na estimação;
    - Em 05/12/2023 o ativo foi negociado com PU de 1.001,77, sendo negociado novamente apenas em 20/03/2024 com PU de 1,40 e posteriormente em 21/03/2024 com PU de 0,000014. O papel voltou a ser negociado em 26/07/2024 com PU de 38,04 e em 28/02/2025 com PU de 754,31;
- A empresa emissora passou por eventos de reestruturação societária e recuperação judicial.

== Harmonização de Taxas e Engenharia de Atributos <subcap_processamento>

A base abrange três categorias contratuais de remuneração: debêntures indexadas a percentual do CDI, debêntures atreladas ao CDI acrescidas de spread e debêntures indexadas a índices de preços (IPCA+). Cada contrato exige tratamento específico para 
isolar o prêmio de risco de crédito.

Para os ativos emitidos a um percentual do CDI (ex.: 120% do DI), realizou-se uma conversão explícita baseada na taxa CDI diária apurada pelo Banco Central, isolando o prêmio excedente sobre a taxa livre de risco:

$ F_"cdi" = (1 + "CDI"_t / 100)^(1/252) $

$ F_"titulo" = (F_"cdi" - 1) times ("Taxa do Ativo"_t / 100) + 1 $

$ S_t = ( (F_"titulo")^252 - 1 ) times 100 - "CDI"_t $

Nos contratos atrelados a inflação (IPCA+) ou sobretaxa direta sobre o DI (DI+), o spread bruto informado pelo mercado secundário já expressa diretamente o prêmio de crédito: $S_t = "Taxa do Ativo"_t$.

Com os spreads homogêneos calculados, foram construídos os seguintes atributos derivados:

1. *Variação Diária do Spread* (_Delta Spread_): Atua como variável de entrada para a modelagem da variância condicional:
   $ Delta S_t = S_t - S_(t-1) $

2. *Taxa Ajustada ao Prazo:* Em razão da indisponibilidade de dados homogêneos de duration modificada para toda a amostra, ajustou-se o spread pelo logaritmo dos dias úteis restantes até o vencimento:
   $ "Taxa"_"prazo" = S_t / ln(max("DU", 2)) $

3. *_Z-Score_ Móvel de Spread:* Calculado sobre uma janela causal deslizante de 60 dias úteis, mensurando a distância em desvios-padrão da taxa corrente frente ao histórico recente do próprio ativo;

4. *_Spread Range_ e _Spread Skew Intraday_:* Métricas de dispersão e assimetria das cotações observadas ao longo da mesma sessão de negócios:
   $ S_("range") = "Taxa"_"max" - "Taxa"_"min" $
   $ S_("skew") = ("Taxa"_"med" - "Taxa"_"min") / (S_("range") + epsilon) $
   adotando-se $epsilon = 10^(-6)$ para assegurar estabilidade numérica.

== Tratamento de Discrepâncias e Normalização

Choques extremos e registros pontuais atípicos foram tratados por meio de Winsorização bilateral nos percentis 1% e 99%, calculados estritamente sobre os dados _In-Sample_. Os limites encontrados foram congelados e aplicados para limitar os 
dados _Out-of-Sample_, eliminando a contaminação por informação futura (_look-ahead bias_).

A padronização das variáveis utilizou o algoritmo `RobustScaler`, fundamentado no estimador por quantis de #cite(<rousseeuw2011robust>, form: "prose"), que subtrai a mediana e divide pela amplitude interquartil ($"IQR" = Q_3 - Q_1$). O método mitiga distorções 
causadas por observações anômalas. Para evitar indefinições numéricas em ativos com baixa oscilação, fixou-se um piso de variância equivalente a 10% do IQR mediano do indexador correspondente.

== Implementação em Código-Fonte

A classe `DataPreprocessor`, localizada em `src/credit_tail_analytics/models/credit_risk/preprocessor.py`, executa as operações de limpeza, separação de indexadores, engenharia de atributos e filtragem transversal de liquidez:

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

        # 4. Z-Score causal com janela móvel de 60 dias úteis
        roll = df.groupby('Ticker')['Spread_Equivalente'].rolling(window=60, min_periods=10)
        m = roll.mean().reset_index(level=0, drop=True)
        s = roll.std().reset_index(level=0, drop=True).replace(0, np.nan)
        df['Taxa_ZScore'] = ((df['Spread_Equivalente'] - m) / s).fillna(0.0)

        # 5. Métricas de microestrutura intraday (Range e Skew)
        df['Spread_Range_Intraday'] = df['Taxa_Maxima'] - df['Taxa_Minima']
        df['Spread_Skew_Intraday'] = (df['Taxa_Ativo'] - df['Taxa_Minima']) / (df['Spread_Range_Intraday'] + 1e-6)

        # 6. Banimento transversal de ativos cronicamente ilíquidos (>= 95% do In-Sample na Faixa 3)
        if self.filter_low_liquidity:
            df_is = df[df['Data'] < self.split_date]
            mask_faixa3 = df_is['Faixa_Volume_ANBIMA'] == 'Até 1MM'
            taxa_iliq = mask_faixa3.groupby(df_is['Ticker']).mean()
            banidos = taxa_iliq[taxa_iliq >= 0.95].index
            df = df[~df['Ticker'].isin(banidos)].reset_index(drop=True)

        return df
```
