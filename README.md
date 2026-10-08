# doc-kit

One kit for every Quarto book, report and paper and every LaTeX document.
Documents **link** to the kit instead of copying it, so a fix here reaches every
document that uses it.

```bash
newdoc book   ~/thesis/notes -t "Thesis notes"   # Quarto book (PDF + HTML + EPUB)
newdoc report lab1   -t "Lab 1"                   # one Quarto document
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
| `extensions/phu/phu-output.lua` | Typesets ordinary code output: arrays, data frames, loop prints (self-contained, vendorable) |
| `python/` | `phu.py` + `phu.mplstyle`: plot style for books and reports, plate helpers |
| `r/phu.R` | The same for base R graphics and ggplot2 (`theme_phu()`) |
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

Code is written normally. `phu-output.lua` reads what Python and R print
(numpy arrays, pandas and R data frames, tibbles, R vectors and matrices, a
loop printing a line per step) and typesets it; everything else stays console
text. Plots (matplotlib, pandas, seaborn, base R, ggplot2) follow the look
through the IPython startup file and `~/.Rprofile` line that `install.sh`
sets up, only when the document uses the look. `PHU_DISPLAY=0` turns the
plot style off.

## License

MIT, see [LICENSE](LICENSE). `extensions/quarto-journals/elsevier` keeps its own
MIT license (© RStudio, PBC).
