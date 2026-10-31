= Introdução <sec_introducao>

A Estatística aplicada à Ciência de Dados estabelece métodos analíticos para estimar eventos sob incerteza quantitativa. No mercado de capitais, formulações 
baseadas em dados produzem estimativas probabilísticas para a precificação de ativos e a gestão de risco #cite(<hull2012risk>).

Nas séries temporais financeiras, a econometria tradicional foca na heterocedasticidade condicional por formulações de parâmetros fixos, ao passo que modelos de aprendizado profundo demandam 
históricos contínuos e volumosos. No mercado secundário brasileiro, contudo, a baixa liquidez impede a observação contínua de cotações, inviabilizando redes neurais densas.

Nesse cenário de negociações esparsas, a integração entre modelos econométricos (EGARCH-t) e aprendizado de máquina não supervisionado (K-Means e Modelos Ocultos de Markov) 
permite identificar regimes latentes com menor número de parâmetros e maior estabilidade de estimação.

O objetivo deste estudo é empregar essa integração metodológica para gerar sinais preventivos sobre a transição de títulos de crédito corporativo para estados de estresse, com foco
nas debêntures, que apresentaram uma expansão de 307% entre 2020 e 2025, consolidando-se na captação corporativa #cite(<anbima2026recorde>). Apesar desse crescimento, o mercado 
enfrenta baixa liquidez, conforme sintetizado por #cite(<sheng2008liquidez>, form: "prose"), o segmento apresenta as seguintes características estruturais:

- As transações são dispersas e ocorrem em duas diferentes instituições: Bolsa de Valores de São Paulo (Bovespa Fix) e Sistema Nacional de Debêntures (SND);
- Existe baixa atividade, não havendo registro de transações para períodos longos e, em algumas emissões de debêntures, o volume de transações no mercado secundário é quase nulo e o valor total em reais é baixo;
- Existe um baixo número de negociações diárias;
- Predominância de debêntures de médio prazo (vencimento em torno de quatro anos);
- Demanda significativa por investidores institucionais e fundos de pensão;
- Em geral as emissões não são conversíveis em ações;
- Alguns investidores adquirem debêntures e as mantêm até o vencimento.

Esses traços persistem nos dados obtidos, com volumes diários concentrados abaixo de R\$ 1 milhão e retenção até o vencimento #cite(<barra2021estudo>)#cite(<anbima2026recorde>). Por outro lado, 
observa-se um alongamento dos prazos de emissão, visto que a amostra apresenta mediana de sete anos até o vencimento. Com prazos mais longos e baixa liquidez secundária, a identificação de regimes latentes 
ajuda a detectar aumentos de risco antes de quedas acentuadas nos preços.