#import "abnt.typ": abnt

#show: abnt.with(
  titulo: "Modelagem de Risco de Cauda no Mercado de Crédito Privado: Uma Abordagem via Markov-Switching GARCH (HMM)",
  autor: "Guilherme Tolotti Azevedo",
  orientador: "Nome do Orientador",
  instituicao: "Nome da Universidade / Instituição",
  ano: "2026",
  local: "São Paulo, SP"
)

// IMPORTAÇÃO DOS CAPÍTULOS
#include "capitulos/1_introducao.typ"
#include "capitulos/2_revisao_teorica.typ"
#include "capitulos/3_metodologia.typ"
#include "capitulos/4_resultados.typ"
#include "capitulos/5_conclusao.typ"

// REFERÊNCIAS BIBLIOGRÁFICAS
#pagebreak()
#bibliography("referencias.bib", style: "associacao-brasileira-de-normas-tecnicas")
