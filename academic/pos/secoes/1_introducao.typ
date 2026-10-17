= Introdução <sec_introducao>

A Estatística para Ciência de Dados vem ganhando espaço no mercado de trabalho porque estabelece a base quantitativa necessária para transformar grandes volumes de dados em decisões objetivas. 
No mercado de capitais, a tomada de decisão orientada por dados auxilia o profissional com estimativas probabilísticas verificáveis, através, por exemplo, da precificação de ativos e do 
gerenciamento de risco de crédito corporativo, conforme demonstrado por #cite(<hull2012risk>). Muitos dos modelos que são usados hoje, contudo, são puramente determinísticos e têm 
dificuldade em capturar, por exemplo, mudanças de regime. Uma solução para isso é a integração entre modelos econométricos clássicos de séries temporais e algoritmos modernos de Aprendizado de Máquina, 
que viabilizam a extração de padrões ocultos e regimes latentes em séries não-lineares, superando limitações históricas de abordagens puramente determinísticas.

O intuito desse trabalho é aplicar a combinação destes modelos para analisar um comportamento do mercado de crédito privado brasileiro, que cresce continuamente e se consolida como ferramenta central 
de captação de recursos para as empresas #cite(<anbima2026recorde>). Entre os instrumentos emitidos, destacam-se as debêntures, cujo volume de emissões registrou uma expansão de 307% entre 2020 e 2025. Porém, esse mercado enfrenta restrições 
crônicas de liquidez, e conforme #cite(<sheng2008liquidez>, form: "prose"), apresenta as seguintes características:

- As transações são dispersas e ocorrem em duas diferentes instituições: Bolsa de Valores de São Paulo (Bovespa Fix) e Sistema Nacional de Debêntures (SND);
- Existe baixa atividade, não havendo registro de transações para períodos longos e, em algumas emissões de debêntures, o volume de transações no mercado secundário é quase nulo e o valor total em reais é baixo;
- Existe um baixo número de negociações diárias;
- Predominância de debêntures de médio prazo (vencimento em torno de quatro anos);
- Demanda significativa por investidores institucionais e fundos de pensão;
- Em geral as emissões não são conversíveis em ações;
- Alguns investidores adquirem debêntures e as mantêm até o vencimento;

Foi observado que algumas dessas características estruturais se mantêm verdadeiras, como:
- A baixa liquidez (onde mais da metade das marcações diárias do mercado giram volumes inferiores a R\$ 1 milhão);
- A exclusividade de emissões do tipo simples;

e outras, como:
- A baixa presença de pessoas físicas e investidores estrangeiros;
- O fato de os intermediários manterem os papéis na carteira até o vencimento;

são reforçadas por estudos recentes como #cite(<barra2021estudo>, form: "prose") e #cite(<anbima2026recorde>, form: "prose"). Porém, observou-se uma mudança em relação a pesquisa de #cite(<sheng2008liquidez>, form: "prose") que sugere amadurecimento 
institucional. A amostra utilizada neste estudo indica que as empresas têm conseguido alongar o perfil de suas dívidas, com as debêntures apresentando uma mediana de sete anos de prazo até o vencimento.

Com prazos estendidos e liquidez de suporte reduzida, a combinação entre a modelagem econométrica de volatilidade condicional e métodos de aprendizado de máquina não-supervisionado surge como uma 
alternativa para identificar mudanças de regimes de crédito antes que as perdas financeiras se materializem.
