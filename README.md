# doc-kit

One kit for every Quarto book, report and paper and every LaTeX document.
Documents **link** to the kit instead of copying it, so a fix here reaches every
document that uses it.

```bash
newdoc book   ~/thesis/notes -t "Thesis notes"   # Quarto book (PDF + HTML + EPUB)
newdoc report lab1   -t "Lab 1"                   # one Quarto document
newdoc report notes/assignments/hw1 -t "HW 1"     # ... also a chapter of the book in notes/
newdoc paper  cmb-v2 -t "Large-angle statistics"  # Quarto + Elsevier journal format
newdoc tex    draft  -t "Draft"                   # plain LaTeX
newdoc link   [DIR]  # point an existing Quarto folder at the kit
```

## What's in it

| Folder | What |
|---|---|
| `bin/newdoc` | Starts a document from `projects/` and links `_extensions` |
| `projects/` | Skeletons: `book`, `report`, `paper`, `tex`, plus their `.gitignore`s |
| `extensions/phu` | Quarto extension: `phu-pdf` / `phu-html` / `phu-epub` formats and the `phu` filter (the notes look, shared macros) |
| `extensions/quarto-journals/elsevier` | [quarto-journals/elsevier](https://github.com/quarto-journals/elsevier) 0.4.5, vendored unchanged (MIT, its own `LICENSE`) |
| `latex/` | `phumacros.sty` (math macros), `phunotes.sty` (macros + the notes look), `phu-macros.tex` |
| `extensions/phu/phu-output.lua` | Styles code output by kind: console text, displayed tables, matrices (self-contained, vendorable) |
| `python/` | `phu.py` + `phu.mplstyle`: displayed values by type, plot style, plate helpers |
| `r/phu.R` | The same for R: data frames and matrices by class, base graphics and ggplot2 (`theme_phu()`) |
| `tests/` | The lab: fixtures, course corpus, runner and dashboard (`tests/run`, see below) |
| `snippets/` | VS Code-format snippets (Quarto, LaTeX, math, Python, R, Julia, Rust, shell), usable from LuaSnip/blink/friendly-snippets |

A new Quarto project has no copied extensions and no `.cls` files:

```
mybook/
  _quarto.yml  index.qmd  chapters/  references.bib  .gitignore
  _extensions -> ~/code/doc-kit/extensions        (one symlink)
```

A book also gets `_quarto-chapter.yml`: `quarto render chapters/x.qmd --profile
chapter` renders one chapter on its own (into `_chapter/`, keeping its number
with `-M phu-chapter-offset:N -M number-offset:[N]`).

A report is a project of its own (`_quarto.yml` with `type: default`), so
`quarto render` in its folder renders it alone even inside a book. Made inside a
book's folder, `newdoc report` also lists it in the book's `chapters:` (part
"Assignments", or `--part NAME`). Its header has `phu-report: true`: in the book
its title becomes the chapter title, its `#` sections move one level down, its
subtitle, authors, date and abstract go under the chapter title and its
bibliography joins the book's. Labels start with the report's name
(`#sec-hw1-intro`) so they stay unique in the book.

Quarto doesn't follow links *inside* `_extensions`, so the whole folder is
linked. LaTeX documents use `\usepackage{phunotes}`, found through
`$TEXMFHOME`. `newdoc link` on a folder with a copied `_extensions/` renames it
to `_extensions.bak`; delete that once a render works. For a journal
submission set `keep-tex: true` in the paper.

## Install

Requirements: Python 3, [Quarto](https://quarto.org) ≥ 1.4, a TeX distribution.

```bash
git clone https://github.com/PhyAMR/doc-kit ~/code/doc-kit
~/code/doc-kit/install.sh
```

This links `newdoc` into `~/.local/bin` and `latex/` into
`$TEXMFHOME/tex/latex/phu`, links EB Garamond and IBM Plex Mono from TeX Live
into `~/.local/share/fonts/doc-kit` (for matplotlib), hooks the plot
style into IPython (`~/.ipython/profile_default/startup/50-doc-kit.py`) and R
(`~/.Rprofile`), active only when Quarto renders a book or report, and writes `~/.config/doc-kit/author.conf` from
[author.conf.example](author.conf.example). Fill that in: its values replace
`{{AUTHOR}}`, `{{EMAIL}}`, `{{AFFILIATION}}`, … in new documents.

The `hdr*` header snippets in `snippets/quarto.json` (for standalone `.qmd`
files with no `_extensions` link) name the `phu` filter by absolute path; change
`/home/phuniverse/code/doc-kit` there if your checkout lives elsewhere.

## The look

Books and reports (the `phu-*` formats, or `phu-look: true`): EB Garamond and
IBM Plex Mono, one rust accent (`#b4442b`), white page. Results get drafting
corner marks, exercises/examples/solutions a title-block header row, callouts
a label hung in the margin, code a rule and a language tag with monochrome
highlighting (`extensions/phu/phu.theme`). `\usepackage[cm]{phunotes}` keeps
Computer Modern. Reports come in one or two columns (`newdoc report -2`).

Code is written normally, and its output follows one rule:

- **Printed text stays as printed.** `print()`, `cat()`, messages, warnings and
  errors are console text (tagged *out*, *msg*, *error*). Nothing reads what
  was printed, so no character in it can change how it is shown.
- **A displayed value is rendered by its type** (the cell's last expression,
  `display(x)`, R's auto-printing), through Jupyter's and knitr's own display
  systems: pandas DataFrames and Series and R data frames (tibble,
  data.table, named matrices) become tables, long and wide ones cut to head
  and tail with their size underneath; 2-D numeric numpy arrays and R
  matrices become bracketed matrices. Everything else keeps its own
  representation (plots, sympy, Styler, plain text). Quarto turns the tables
  into native tables for PDF, HTML and EPUB.
- **Styling follows the kind of output**, never its content.

Plots (matplotlib, pandas, seaborn, base R, ggplot2) follow the look too.
All of this comes from the IPython startup file and the `~/.Rprofile` line
that `install.sh` sets up, and is active only when Quarto renders a document
whose format has `phu-look: true` (the `phu-*` formats). `PHU_DISPLAY=0`
turns it off. An renv project skips `~/.Rprofile`; its output is then plain
knitr output, without the look.

Raw LaTeX blocks (```` ```{=latex} ````) go to the PDF as they are. For HTML
and EPUB each one is compiled to an SVG and shown if it draws something
(`\vspace`, `\newcommand`, `\newpage` draw nothing and are left out). For
content meant only for the PDF use `::: {.content-visible when-format="pdf"}`.

## The lab

`tests/` renders synthetic and real documents with the kit and keeps every
run, so a change to the kit can be judged before it reaches a book:

```bash
tests/run setup              # once: clone the corpus, Python env (uv), R packages
tests/run                    # quick: fixtures, newdoc report/book, unit tests (~2 min)
tests/run --set corpus -j 6  # pydata-book, r4ds, PDSH (saved outputs)
tests/run --set master       # copies of ~/Master's books, with the look synced
tests/run open               # the dashboard: runs over time, doc x format grid, pages
```

`fixtures/` holds the cases (output of every kind, hostile characters, code
from files, LaTeX); `corpus.toml` pins the course repositories. Each render
is compared with the same document in plain `pdf`/`html`: a failure, or more
cell errors, only with the kit is a *kit* problem. The dashboard shows each
run's PDF pages beside the previous run's and outlines the pages that changed.

## License

MIT, see [LICENSE](LICENSE). `extensions/quarto-journals/elsevier` keeps its own
MIT license (© RStudio, PBC).
