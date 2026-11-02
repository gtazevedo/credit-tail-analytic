#let abnt(
  titulo: "",
  autor: "Guilherme Tolotti Azevedo",
  ano: "2026",
  mes: "Outubro",
  local: "Belo Horizonte",
  body
) = {
  // Configuração da Página A4, Margens ABNT (esq 3, sup 3, dir 2, inf 2)
  set page(
    paper: "a4",
    margin: (left: 3cm, top: 3cm, right: 2cm, bottom: 2cm),
    header: context {
      let headings = query(heading.where(level: 1))
      let loc = here()
      let has_started = headings.any(h => h.location().page() <= loc.page())
      if has_started {
        let p = counter(page).get().first()
        align(right, text(size: 10pt)[#p])
      }
    }
  )

  // Fonte Arial, 12pt, espaçamento 1.5 linhas proporcional ABNT
  set text(font: "Arial", size: 12pt, lang: "pt")
  set par(justify: true, first-line-indent: 1.25cm, leading: 0.65em)

  // Espaçamentos verticais para figuras, tabelas e equações em relatório técnico
  show figure: set block(spacing: 0.7em)
  show math.equation.where(block: true): set block(spacing: 0.5em)

  // 1. CAPA OFICIAL PUC MINAS
  align(center)[
    #text(size: 13pt, weight: "bold")[
      PONTIFÍCIA UNIVERSIDADE CATÓLICA DE MINAS GERAIS \
      NÚCLEO DE EDUCAÇÃO A DISTÂNCIA \
      Pós-graduação Lato Sensu em Estatística para Ciências de Dados
    ]
    #v(3.5cm)
    #text(size: 13pt)[#autor]
    #v(4.5cm)
    #text(size: 15pt, weight: "bold")[#upper(titulo)]
    #v(1fr)
    #text(size: 12pt)[
      #local \
      #mes de #ano
    ]
  ]

  pagebreak()

  // 2. FOLHA DE ROSTO OFICIAL PUC MINAS
  align(center)[
    #text(size: 13pt)[#autor]
    #v(4cm)
    #text(size: 15pt, weight: "bold")[#upper(titulo)]
    #v(3cm)
    #align(right)[
      #block(width: 55%)[
        #set par(justify: true, first-line-indent: 0pt, leading: 0.6em)
        #text(size: 10pt)[
          Trabalho de Conclusão de Curso apresentado ao Curso de Especialização em Estatística para Ciências de Dados, como requisito parcial à obtenção do título de Especialista.
        ]
      ]
    ]
    #v(1fr)
    #text(size: 12pt)[
      #local \
      #mes de #ano
    ]
  ]

  pagebreak()

  // 3. SUMÁRIO (Filtro oficial PUC Minas: Seções 1 a 12 e subseções da Seção 8)
  show outline.entry: it => {
    if it.level == 1 {
      v(7pt, weak: true)
      strong(it)
    } else if it.level == 2 {
      context {
        let h_nums = counter(heading).at(it.element.location())
        if h_nums.at(0, default: 0) == 8 {
          it
        }
      }
    }
  }
  
  align(center)[#text(size: 12pt, weight: "bold")[SUMÁRIO]]
  v(0.6cm)
  outline(title: none, depth: 2, indent: auto)
  
  pagebreak()

  // Numeração de seções conforme padrão PUC Minas (1., 2., 8.1, etc.)
  set heading(numbering: (..nums) => {
    let list = nums.pos()
    if list.len() == 1 {
      str(list.first()) + "."
    } else {
      list.map(str).join(".")
    }
  })

  show heading: it => {
    if it.level == 1 {
      v(1em, weak: true)
      let num = if it.numbering != none {
        counter(heading).display(it.numbering)
        h(0.5em)
      }
      text(size: 12pt, weight: "bold")[#num#it.body]
      v(0.6em, weak: true)
    } else if it.level == 2 {
      v(0.8em, weak: true)
      let num = if it.numbering != none {
        counter(heading).display(it.numbering)
        h(0.5em)
      }
      text(size: 12pt, weight: "bold")[#num#it.body]
      v(0.4em, weak: true)
    } else {
      v(0.6em, weak: true)
      let num = if it.numbering != none {
        counter(heading).display(it.numbering)
        h(0.5em)
      }
      text(size: 12pt, weight: "bold")[#num#it.body]
      v(0.3em, weak: true)
    }
    // Força indentação do primeiro parágrafo
    par(text(size: 0pt)[])
  }

  // Legendas de figuras e tabelas em tamanho 10pt e espaçamento simples (ABNT)
  show figure.caption: it => {
    set par(leading: 0.45em)
    text(size: 10pt, it)
  }

  // Blocos de código em tamanho 8.5pt com quebra limpa
  show raw: set text(size: 8.5pt, font: ("Consolas", "Courier New"))
  show raw.where(block: true): it => block(
    fill: luma(248),
    inset: 6pt,
    radius: 3pt,
    width: 100%,
    breakable: false,
    stroke: 0.5pt + luma(220),
    it
  )

  set math.equation(numbering: "(1)")

  // Referências bibliográficas conforme ABNT e PUC Minas (tamanho 12pt, espaçamento simples, alinhadas à esquerda, sem recuo)
  show bibliography: set par(leading: 0.4em, spacing: 0.55em, first-line-indent: 0pt, justify: false)
  show bibliography: set text(size: 12pt)

  body
}
