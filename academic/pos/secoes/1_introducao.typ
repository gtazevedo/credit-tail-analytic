= Introdução <sec_introducao>

A Estatística para Ciência de Dados estabelece o arcabouço analítico para orientar deliberações objetivas em ambientes de incerteza quantitativa. No mercado de capitais, foco desta pesquisa, a modelagem baseada em dados fornece estimativas probabilísticas verificáveis para a precificação de ativos e o gerenciamento de risco de crédito corporativo, conforme sistematizado por #cite(<hull2012risk>, form: "prose").

A modelagem quantitativa contemporânea dispõe de diferentes paradigmas para séries temporais financeiras. De um lado, as abordagens estatísticas e econométricas clássicas fornecem fundamentação analítica rigorosa 
para a heterocedasticidade condicional e distribuições com caudas pesadas, porém com parâmetros frequentemente estáticos frente a quebras estruturais. De outro lado, modelos modernos de Aprendizado Profundo (_Deep Learning_), 
como redes neurais recorrentes (LSTM) e _Transformers_, destacam-se pela capacidade de aprender relações sequenciais altamente não lineares, mas demandam séries densas, contínuas e amplo volume amostral para evitar sobreajuste 
(_overfitting_). No mercado secundário de crédito corporativo brasileiro, a escassez de negociações diárias e a descontinuidade temporal dificultam o treinamento estável de arquiteturas de _Deep Learning_. Nesse 
contexto de dados esparsos e fragmentados, a integração entre modelos econométricos clássicos de séries temporais (como o EGARCH com inovações t-Student) e algoritmos não supervisionados de Aprendizado de Máquina (como K-Means e 
Modelos Ocultos de Markov) viabiliza a extração de regimes latentes de risco preservando a estabilidade numérica, a interpretabilidade teórica e a parcimônia paramétrica.

O objetivo deste trabalho é aplicar a combinação desses modelos para analisar a dinâmica dos regimes de risco de crédito no mercado secundário de debêntures brasileiro, segmento que cresce continuamente e consolida-se como uma das principais vias 
de captação de recursos para as empresas #cite(<anbima2026recorde>). Dentre os instrumentos emitidos, as debêntures registraram uma expansão de 307% entre 2020 e 2025. Entretanto, esse mercado enfrenta restrições 
crônicas de liquidez e, conforme #cite(<sheng2008liquidez>, form: "prose"), apresenta as seguintes características:

- As transações são dispersas e ocorrem em duas diferentes instituições: Bolsa de Valores de São Paulo (Bovespa Fix) e Sistema Nacional de Debêntures (SND);
- Existe baixa atividade, não havendo registro de transações para períodos longos e, em algumas emissões de debêntures, o volume de transações no mercado secundário é quase nulo e o valor total em reais é baixo;
- Existe um baixo número de negociações diárias;
- Predominância de debêntures de médio prazo (vencimento em torno de quatro anos);
- Demanda significativa por investidores institucionais e fundos de pensão;
- Em geral as emissões não são conversíveis em ações;
- Alguns investidores adquirem debêntures e as mantêm até o vencimento;

Observa-se que parte dessas características estruturais permanece verificável na prática de mercado, destacando-se a liquidez reduzida (na qual mais da metade das marcações diárias compreende volumes inferiores a R\$ 1 milhão) e a exclusividade de emissões simples. 
Adicionalmente, a baixa presença de pessoas físicas e de investidores não residentes, bem como a manutenção dos títulos em carteira própria pelos intermediários até a data de resgate, são corroboradas por estudos recentes como #cite(<barra2021estudo>, form: "prose") e #cite(<anbima2026recorde>, form: "prose"). Em contrapartida, constata-se uma alteração estrutural em relação ao diagnóstico de #cite(<sheng2008liquidez>, form: "prose") que reflete amadurecimento institucional: as empresas têm conseguido alongar o perfil de suas dívidas, uma vez que a amostra selecionada neste estudo exibe mediana de sete anos de prazo até o vencimento.

Com prazos estendidos e liquidez de suporte reduzida, a combinação entre a modelagem econométrica de volatilidade condicional e métodos de aprendizado de máquina não supervisionado possibilita antecipar transições de regimes de crédito antes que 
as perdas financeiras sejam materializadas, auxiliando na manutenção do desempenho e na preservação patrimonial da carteira.
