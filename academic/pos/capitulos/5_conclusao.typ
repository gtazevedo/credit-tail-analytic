= Conclusão

Esta dissertação teve como objetivo desenvolver e avaliar uma metodologia quantitativa baseada em Aprendizado de Máquina Não Supervisionado para a identificação precoce de regimes de estresse (*Early Warning*) no mercado secundário de debêntures brasileiro. Motivada pela assimetria de retornos inerente aos ativos de crédito privado e pelos recentes episódios de contágio sistêmico, a pesquisa buscou responder se algoritmos de clusterização poderiam superar o carrego passivo de portfólio protegendo o capital contra perdas extremas na cauda esquerda.

== Principais Descobertas

Os resultados empíricos demonstraram de forma contundente a importância da modelagem temporal para a gestão de risco de crédito. O Modelo Oculto de Markov (HMM) provou-se substancialmente superior ao agrupamento geométrico clássico do K-Means. Ao integrar a dependência sequencial através de matrizes de transição estocásticas, o filtro Bayesiano do HMM foi capaz de antecipar a deterioração de emissores meses antes da materialização do *default*, evitando os atrasos e a instabilidade de classificação (*flickering*) que afligiram o K-Means.

A avaliação da utilidade econômica, consolidada no *backtest* financeiro, validou a tese de que a liquidação preventiva é financeiramente superior à inércia. A estratégia ativa orientada pelo HMM (com liquidação no estágio Amarelo) gerou um retorno total acumulado de 32,62%, mitigando massivamente o risco de cauda e apresentando um *Sharpe Ratio* superior ao índice passivo (*Buy-and-Hold*), que amargou 22,42% ao reter papéis inadimplentes até o vencimento.

Além disso, o estudo documentou a "armadilha da inércia combinada" por meio do modelo *Ensemble*. Ao tentar fundir a reatividade do HMM com a letargia do K-Means, a modelagem mista induziu a carteira ao efeito chicote (*whipsaw*), corroendo o capital com excesso de custos transacionais e evidenciando que, em momentos de pânico, atrasar o *stop loss* anula o valor econômico da predição preditiva.

== Implicações Práticas

Para a indústria de gestão de recursos, a metodologia desenvolvida oferece um arcabouço robusto e sistemático para a gestão de liquidez e risco em carteiras de crédito privado. Em um mercado caracterizado por baixa liquidez estrutural e precificação defasada como o brasileiro, a remoção do viés comportamental (que frequentemente leva gestores a "segurar" posições perdedoras na esperança de recuperação) por um gatilho quantitativo comprovou seu valor. 

A operacionalização do modelo HMM demonstrou que assumir prejuízos controlados de marcação a mercado no curto prazo (pagando os custos de atrito e transação) é o prêmio de seguro matematicamente correto a se pagar para garantir a sobrevivência do portfólio contra os eventos catastróficos de *default*.

== Limitações e Recomendações para Estudos Futuros

Apesar dos resultados promissores, o presente estudo possui limitações inerentes à estrutura dos dados financeiros. A principal limitação concentrou-se na convergência da volatilidade condicional (EGARCH) para ativos altamente ilíquidos durante o período *In-Sample*, o que distorceu a sensibilidade do algoritmo em ativos com longo histórico de ausência de negociação. Além disso, a dependência exclusiva da curva de apreçamento da Anbima significa que o modelo herda qualquer ineficiência temporal ou "suavização" de preços imposta pela associação.

Para trabalhos futuros, recomenda-se a exploração de duas frentes de pesquisa: (i) a incorporação de modelos de aprendizado profundo focados em séries temporais, como Redes Neurais Recorrentes (LSTMs) ou *Transformers*, para capturar relações não-lineares mais complexas; e (ii) a inclusão de dados não-estruturados, como Análise de Sentimento de notícias corporativas (*Natural Language Processing*), atuando como variáveis preditoras exógenas (covariáveis) nas matrizes de transição probabilísticas do próprio HMM.
