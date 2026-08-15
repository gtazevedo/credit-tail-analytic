#let abnt(
  titulo: "",
  autor: "",
  orientador: "",
  instituicao: "",
  ano: "",
  local: "",
  body
) = {
  // Configuração da Página A4, Margens ABNT (esq 3, sup 3, dir 2, inf 2)
  set page(
    paper: "a4",
    margin: (left: 3cm, top: 3cm, right: 2cm, bottom: 2cm),
    numbering: "1",
    number-align: right + top
  )

  // Fonte Arial, 12pt, espaçamento 1.5 linhas (em Typst, 0.8em equivale a 1.5 linhas)
  set text(font: "Arial", size: 12pt, lang: "pt")
  set par(justify: true, first-line-indent: 1.25cm, leading: 0.8em)

  // Título e capa simples
  align(center)[
    #text(size: 14pt, weight: "bold")[#instituicao] \
    #v(3cm)
    #text(size: 14pt)[#autor] \
    #v(6cm)
    #text(size: 16pt, weight: "bold")[#upper(titulo)] \
    #v(1fr)
    #align(right)[
      #block(width: 50%)[
        #text(size: 10pt)[Dissertação apresentada como requisito parcial para obtenção do grau de Especialista. \ Orientador: #orientador]
      ]
    ]
    #v(1fr)
    #local \
    #ano
  ]

  pagebreak()

  // Sumário ABNT
  show outline.entry.where(level: 1): it => {
    v(12pt, weak: true)
    strong(it)
  }
  
  align(center)[#text(weight: "bold")[SUMÁRIO]]
  v(1cm)
  outline(title: none, depth: 3)
  
  pagebreak()

  // Numeração de capítulos e subcapítulos
  set heading(numbering: "1.1")
  show heading: it => {
    if it.level == 1 {
      pagebreak(weak: true)
    }
    v(1.5em)
    let num = if it.numbering != none {
      counter(heading).display(it.numbering)
      h(0.5em)
    }
    if it.level == 1 {
      text(size: 12pt, weight: "bold")[#num#upper(it.body)]
    } else {
      text(size: 12pt, weight: "bold")[#num#it.body]
    }
    v(1.5em)
  }

  // Legendas de figuras em tamanho 10pt (ABNT)
  show figure.caption: it => text(size: 10pt, it)

  set math.equation(numbering: "(1)")

  body
}
