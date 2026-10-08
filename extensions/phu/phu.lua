--[[
  phu.lua: write LaTeX once, get it in PDF and HTML.

  1. Macros. phu-macros.tex is the single list of \newcommand's. PDF gets
     it through \usepackage{phunotes}; for HTML this filter hands the same
     definitions to MathJax; for EPUB (MathML, no JavaScript) it expands
     them in every formula.

  2. LaTeX cells. A ```{=latex} block is passed through to the PDF as is.
     For HTML and EPUB it is compiled (pdflatex + pdftocairo) to an SVG and shown
     as an image when it draws something: tikzpicture, circuitikz, axis,
     tabular, forest, or any block whose first line is `% svg`. Other
     LaTeX blocks (\newpage, \vspace...) just don't appear in HTML; start
     a block with `% pdf-only` to skip the SVG on purpose.
     SVGs are cached in .quarto/phu-svg/ (project, else document folder).

  3. tex-packages. A list in the front matter, e.g.
       tex-packages: [pgfplots, circuitikz]
     loads them in the PDF and in the SVG compile, so both see the same.

  4. The phunotes look in the PDF: callouts become phucallout, code cells
     get their language tag (\phucodelang), text output goes in phuout.

  5. Arrays from code. The phu display helpers (python/phu.py, r/phu.R)
     print matrices and vectors as a ::: {.phu-array} pipe table plus a
     "float64 · 3 × 3" line. Here that becomes a bracketed array in the PDF
     and a styled table in HTML, negatives in the accent colour.
--]]

local MACROS = quarto.utils.resolve_path("phu-macros.tex")
local SVG_ENVS = { "tikzpicture", "circuitikz", "axis", "tabular", "forest" }

local packages = {}

local function read(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("a")
  f:close()
  return s
end

local function write(path, s)
  local f = assert(io.open(path, "w"))
  f:write(s)
  f:close()
end

-- \providecommand / \DeclareMathOperator are LaTeX-only: rewrite them
-- into the \newcommand form MathJax understands.
local function mathjax_macros()
  local out = {}
  for line in (read(MACROS) or ""):gmatch("[^\n]+") do
    local star, name, body = line:match("^\\DeclareMathOperator(%*?){(\\%a+)}{(.*)}%s*$")
    if name then
      table.insert(out, ("\\newcommand{%s}{\\operatorname%s{%s}}"):format(name, star, body))
    else
      local rest = line:match("^\\providecommand(.*)") or line:match("^\\renewcommand(.*)")
        or line:match("^\\newcommand(.*)")
      if rest then table.insert(out, "\\newcommand" .. rest) end
    end
  end
  return table.concat(out, "\n")
end

local function wants_svg(text)
  local first = text:match("^%s*([^\n]*)") or ""
  if first:match("^%%%s*pdf%-only") then return false end
  if first:match("^%%%s*svg") then return true end
  for _, env in ipairs(SVG_ENVS) do
    if text:find("\\begin{" .. env .. "}", 1, true) then return true end
  end
  return false
end

local function svg_preamble()
  local lines = { "\\documentclass[border=2pt]{standalone}", "\\usepackage{phunotes}" }
  for _, p in ipairs(packages) do
    table.insert(lines, "\\usepackage{" .. p .. "}")
  end
  return table.concat(lines, "\n")
end

-- Returns the SVG text, or nil (with a warning) when LaTeX fails.
local function to_svg(code)
  local docdir = pandoc.path.directory(quarto.doc.input_file)
  local source = svg_preamble() .. "\n\\begin{document}\n" .. code .. "\n\\end{document}\n"
  local root = quarto.project.directory or docdir
  local cache_dir = pandoc.path.join({ root, ".quarto", "phu-svg" })
  local cached = pandoc.path.join({ cache_dir, pandoc.utils.sha1(source) .. ".svg" })
  local hit = read(cached)
  if hit then return hit end

  local svg
  pandoc.system.with_temporary_directory("phu-svg", function(tmp)
    local tex = pandoc.path.join({ tmp, "cell.tex" })
    write(tex, source)
    -- from the document's folder, so \includegraphics/\input paths work
    local ok = pandoc.system.with_working_directory(docdir, function()
      return pcall(pandoc.pipe, "pdflatex",
        { "-interaction=nonstopmode", "-halt-on-error", "-output-directory=" .. tmp, tex }, "")
    end)
    if not ok then
      local log = read(pandoc.path.join({ tmp, "cell.log" })) or ""
      local err = log:match("\n(! [^\n]*\n[^\n]*)") or "see the LaTeX log"
      quarto.log.warning("phu: LaTeX cell failed, left out of HTML:\n" .. err ..
        "\n" .. code:sub(1, 200))
      return
    end
    local svgfile = pandoc.path.join({ tmp, "cell.svg" })
    pandoc.pipe("pdftocairo", { "-svg", pandoc.path.join({ tmp, "cell.pdf" }), svgfile }, "")
    svg = read(svgfile)
  end)
  if svg then
    pandoc.system.make_directory(cache_dir, true)
    write(cached, svg)
  end
  return svg
end

-- EPUB: let pandoc's own LaTeX reader apply the macros to one formula
local macro_defs, expanded = nil, {}
local function expand_math(el)
  macro_defs = macro_defs or mathjax_macros()
  if not expanded[el.text] then
    local doc = pandoc.read(macro_defs .. "\n\n$" .. el.text .. "$", "markdown+latex_macros")
    local found
    doc:walk({ Math = function(m) found = found or m.text end })
    expanded[el.text] = found or el.text
  end
  el.text = expanded[el.text]
  return el
end

-- 4. the PDF look ------------------------------------------------------
local function latex_inlines(inlines)
  return pandoc.write(pandoc.Pandoc({ pandoc.Plain(inlines) }), "latex"):gsub("%s+$", "")
end

local function output_block(code)
  return pandoc.RawBlock("latex", "\\begin{phuout}\n\\begin{Verbatim}\n" .. code.text ..
    "\n\\end{Verbatim}\n\\end{phuout}")
end

local TEXT_OUTPUTS = { "cell-output-stdout", "cell-output-display" }

local function latex_cell_parts(el)
  -- code cell: language tag before the code
  if el.classes:includes("cell") then
    local out = {}
    for _, b in ipairs(el.content) do
      if b.t == "CodeBlock" and b.classes:includes("cell-code") and b.classes[1] ~= "cell-code" then
        table.insert(out, pandoc.RawBlock("latex", "\\phucodelang{" .. b.classes[1] .. "}"))
      end
      table.insert(out, b)
    end
    el.content = out
    return el
  end
  -- text output: tagged "out"
  for _, cls in ipairs(TEXT_OUTPUTS) do
    if el.classes:includes(cls) then
      local changed = false
      el.content = el.content:map(function(b)
        if b.t == "CodeBlock" then
          changed = true
          return output_block(b)
        end
        return b
      end)
      return changed and el or nil
    end
  end
end

local function as_blocks(x)
  local kind = pandoc.utils.type(x)
  if kind == "Block" then return pandoc.Blocks({ x }) end
  if kind == "Inlines" or kind == "Inline" then return pandoc.Blocks({ pandoc.Plain(x) }) end
  return pandoc.Blocks(x or {})
end

local function latex_callout(el)
  local title = el.title and latex_inlines(pandoc.utils.blocks_to_inlines(as_blocks(el.title))) or ""
  local blocks = pandoc.Blocks({ pandoc.RawBlock("latex",
    "\\begin{phucallout}{" .. (el.type or "note") .. "}{" .. title .. "}") })
  blocks:extend(as_blocks(el.content))
  blocks:insert(pandoc.RawBlock("latex", "\\end{phucallout}"))
  return blocks
end

-- 5. arrays from code ----------------------------------------------------
local function is_negative(s)
  return s:match("^%-%d") or s:match("^\u{2212}") or s:match("^%-%.%d")
end

local LATEX_GLYPHS = { ["\u{22EE}"] = "\\vdots", ["\u{22EF}"] = "\\cdots",
  ["\u{2026}"] = "\\cdots", ["\u{22F1}"] = "\\ddots" }

local function latex_cell(s, index)
  if LATEX_GLYPHS[s] then return LATEX_GLYPHS[s] end
  s = s:gsub("\u{2212}", "-")
  local tex = latex_inlines({ pandoc.Str(s) })
  if index then return "\\phuix{" .. tex .. "}" end
  tex = "\\text{\\ttfamily\\small " .. tex .. "}"
  return is_negative(s) and "\\phuneg{" .. tex .. "}" or tex
end

local function array_rows(tbl)
  local rows = {}
  local function add(row)
    local cells = {}
    for _, c in ipairs(row.cells) do
      table.insert(cells, pandoc.utils.stringify(c.contents))
    end
    table.insert(rows, cells)
  end
  for _, r in ipairs(tbl.head.rows) do add(r) end
  for _, body in ipairs(tbl.bodies) do
    for _, r in ipairs(body.body) do add(r) end
  end
  return rows
end

local function array_latex(el)
  local tbl, rest = nil, pandoc.List()
  for _, b in ipairs(el.content) do
    if b.t == "Table" and not tbl then tbl = b else rest:insert(b) end
  end
  if not tbl then return nil end
  local rows = array_rows(tbl)
  local ncol = #rows[1]
  local lines = {}
  for i, r in ipairs(rows) do
    local cells = {}
    for j, s in ipairs(r) do
      table.insert(cells, (s == "" and "") or latex_cell(s, i == 1 or j == 1))
    end
    table.insert(lines, table.concat(cells, " & "))
  end
  local tex = "\\[\\left[\\begin{array}{r@{\\hspace{1.2em}}" .. string.rep("r", ncol - 1) .. "}\n" ..
    table.concat(lines, " \\\\\n") .. "\n\\end{array}\\right]\\]"
  local out = pandoc.Blocks({ pandoc.RawBlock("latex", "\\begin{center}" .. tex) })
  for _, b in ipairs(rest) do
    out:insert(pandoc.RawBlock("latex", "{\\footnotesize\\color{inkFaint}\\phulabel{" ..
      latex_inlines(pandoc.utils.blocks_to_inlines({ b })) .. "}}"))
  end
  out:insert(pandoc.RawBlock("latex", "\\end{center}"))
  return out
end

-- data frames: faint index column and a small "30 rows × 4 columns" line
-- pandoc wraps pipe tables with long source lines; keep natural widths
local function natural_widths(tbl)
  for i, spec in ipairs(tbl.colspecs) do
    tbl.colspecs[i] = { spec[1], pandoc.ColWidthDefault }
  end
end

local function frame_latex(el)
  local out = pandoc.Blocks({})
  for _, b in ipairs(el.content) do
    if b.t == "Table" then
      natural_widths(b)
      for _, body in ipairs(b.bodies) do
        for _, row in ipairs(body.body) do
          local c = row.cells[1]
          if c then
            local inl = pandoc.utils.blocks_to_inlines(c.contents)
            inl:insert(1, pandoc.RawInline("latex", "\\textcolor{inkFaint}{"))
            inl:insert(pandoc.RawInline("latex", "}"))
            c.contents = { pandoc.Plain(inl) }
          end
        end
      end
      out:insert(b)
    else
      out:insert(pandoc.RawBlock("latex", "\\begin{center}\\vspace{-6pt}{\\footnotesize\\color{inkFaint}\\phulabel{" ..
        latex_inlines(pandoc.utils.blocks_to_inlines({ b })) .. "}}\\end{center}"))
    end
  end
  return out
end

-- HTML: mark negative entries; the CSS draws the brackets
local function array_html(el)
  for _, b in ipairs(el.content) do
    if b.t == "Table" then
      natural_widths(b)
      for _, body in ipairs(b.bodies) do
        for _, row in ipairs(body.body) do
          for _, c in ipairs(row.cells) do
            if is_negative(pandoc.utils.stringify(c.contents)) then
              c.contents = { pandoc.Plain({ pandoc.Span(pandoc.utils.blocks_to_inlines(c.contents),
                pandoc.Attr("", { "neg" })) }) }
            end
          end
        end
      end
    end
  end
  return el
end

local function is_latex(fmt)
  return fmt == "latex" or fmt == "tex"
end

return {
  {
    Meta = function(meta)
      for _, p in ipairs(meta["tex-packages"] or {}) do
        table.insert(packages, pandoc.utils.stringify(p))
      end
      if quarto.doc.is_format("latex") then
        for _, p in ipairs(packages) do
          quarto.doc.include_text("in-header", "\\usepackage{" .. p .. "}")
        end
        -- chapter preview (book template's _quarto-chapter.yml): no title
        -- page, and the chapter keeps its number in the book
        -- (quarto_view passes phu-chapter-offset, and number-offset for HTML)
        if meta["phu-chapter-preview"] then
          local offset = tonumber(pandoc.utils.stringify(meta["phu-chapter-offset"] or "0")) or 0
          quarto.doc.include_text("in-header", "\\AtBeginDocument{\\let\\maketitle\\relax" ..
            "\\ifcsname c@chapter\\endcsname\\setcounter{chapter}{" .. offset .. "}\\fi}")
        end
      elseif quarto.doc.is_format("html") and not quarto.doc.is_format("epub") then
        quarto.doc.include_text("before-body",
          '<div class="hidden" aria-hidden="true">\\(' .. mathjax_macros() .. "\\)</div>")
      end
    end,
  },
  {
    Math = function(el)
      if quarto.doc.is_format("epub") then return expand_math(el) end
    end,
    Div = function(el)
      local latex = quarto.doc.is_format("latex")
      if el.classes:includes("phu-array") then
        return latex and array_latex(el) or array_html(el)
      end
      if el.classes:includes("phu-frame") then
        if latex then return frame_latex(el) end
        el.content = el.content:walk({ Table = function(t) natural_widths(t); return t end })
        return el
      end
      if latex then return latex_cell_parts(el) end
    end,
    Callout = function(el)
      if quarto.doc.is_format("latex") then return latex_callout(el) end
    end,
    RawBlock = function(el)
      local web = quarto.doc.is_format("html") or quarto.doc.is_format("epub")
      if not (web and is_latex(el.format) and wants_svg(el.text)) then
        return nil
      end
      local svg = to_svg(el.text)
      if not svg then return {} end
      local src = "data:image/svg+xml;base64," .. quarto.base64.encode(svg)
      return pandoc.Para({ pandoc.Image({}, src, "", pandoc.Attr("", { "phu-svg" })) })
    end,
  },
}
