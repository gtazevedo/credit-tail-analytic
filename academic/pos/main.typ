#import "abnt.typ": abnt

#show: abnt.with(
  titulo: "Modelagem de Risco de Cauda no Mercado de Crédito Privado: Uma Abordagem Híbrida via EGARCH-t e Modelos Ocultos de Markov",
  autor: "Guilherme Tolotti Azevedo",
  ano: "2026",
  mes: "Outubro",
  local: "Belo Horizonte"
)

// ESTRUTURA OFICIAL DO RELATÓRIO TÉCNICO PUC MINAS (12 SEÇÕES)
#include "secoes/1_introducao.typ"
#include "secoes/2_problema_solucao.typ"
#include "secoes/3_canvas_analitico.typ"
#include "secoes/4_coleta_dados.typ"
#include "secoes/5_processamento.typ"
#include "secoes/6_analise_exploratoria.typ"
#include "secoes/7_aplicacao_modelos.typ"
#include "secoes/8_pipeline_automacao.typ"
#include "secoes/9_discussao_resultados.typ"
#include "secoes/10_conclusao.typ"
#include "secoes/11_links.typ"

// 12. REFERÊNCIAS
= Referências <sec_referencias>
#bibliography("referencias.bib", title: none, style: "associacao-brasileira-de-normas-tecnicas")
