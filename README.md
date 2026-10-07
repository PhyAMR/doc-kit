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
| `snippets/` | VS Code-format snippets (Quarto, LaTeX, math, Python, R, Julia, Rust, shell), usable from LuaSnip/blink/friendly-snippets |

A new Quarto project has no copied extensions and no `.cls` files:

```
mybook/
  _quarto.yml  index.qmd  chapters/  references.bib  .gitignore
  _extensions -> ~/code/doc-kit/extensions        (one symlink)
```

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
`$TEXMFHOME/tex/latex/phu`, and writes `~/.config/doc-kit/author.conf` from
[author.conf.example](author.conf.example). Fill that in: its values replace
`{{AUTHOR}}`, `{{EMAIL}}`, `{{AFFILIATION}}`, … in new documents.

The `hdr*` header snippets in `snippets/quarto.json` (for standalone `.qmd`
files with no `_extensions` link) name the `phu` filter by absolute path; change
`/home/phuniverse/code/doc-kit` there if your checkout lives elsewhere.

## License

MIT, see [LICENSE](LICENSE). `extensions/quarto-journals/elsevier` keeps its own
MIT license (© RStudio, PBC).
