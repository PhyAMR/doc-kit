--[[
  phu.lua: write LaTeX once, get it in PDF and HTML.

  1. Macros. phu-macros.tex is the single list of \newcommand's. PDF gets
     it through \usepackage{phunotes}; for HTML this filter hands the same
     definitions to MathJax; for EPUB (MathML, no JavaScript) it expands
     them in every formula.

  2. LaTeX cells. A ```{=latex} block is passed through to the PDF as is.
     For HTML and EPUB every block is compiled (lualatex, as the PDF, and
     pdftocairo, in a standalone page where \newpage and friends do
     nothing) and shown as an SVG image if it draws anything; blocks that
     draw nothing (\vspace, \newcommand...) are left out. Nothing is decided from the block's
     text. PDF-only content: ::: {.content-visible when-format="pdf"}.
     A block LaTeX can't compile is left out of HTML with a warning.
     SVGs are cached in .quarto/phu-svg/ (project, else document folder).

  3. tex-packages. A list in the front matter, e.g.
       tex-packages: [pgfplots, circuitikz]
     loads them in the PDF and in the SVG compile, so both see the same.

  4. The look (books and reports: the phu-* formats set phu-look: true).
     In the PDF callouts become phucallout and code cells get their
     language tag (\phucodelang). Code output goes through phu-output.lua,
     which styles it by kind (console text, displayed table, matrix) and
     never reads its text. What a displayed value becomes is decided in
     the kernels by its type (python/phu.py, r/phu.R). Code is never
     changed.
--]]

local MACROS = quarto.utils.resolve_path("phu-macros.tex")

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

local function svg_preamble()
  local lines = { "\\documentclass[border=2pt]{standalone}", "\\usepackage{phunotes}" }
  for _, p in ipairs(packages) do
    table.insert(lines, "\\usepackage{" .. p .. "}")
  end
  return table.concat(lines, "\n")
end

-- page-level commands mean nothing in a standalone picture
local NO_PAGES = "\\renewcommand\\newpage{}\\renewcommand\\clearpage{}" ..
  "\\renewcommand\\cleardoublepage{}\\renewcommand\\pagebreak[1][]{}" ..
  "\\renewcommand\\nopagebreak[1][]{}"

-- Does the SVG draw anything? pdftocairo keeps glyphs and clip paths in
-- <defs> and draws with <use>, <path> and <image> outside it.
local function draws(svg)
  local body = svg:gsub("<defs>.-</defs>", "")
  return body:find("<path", 1, true) or body:find("<use", 1, true) or body:find("<image", 1, true)
end

-- The SVG text of a LaTeX block; "" when it draws nothing; nil (with a
-- warning) when LaTeX fails.
local function to_svg(code)
  local docdir = pandoc.path.directory(quarto.doc.input_file)
  local source = svg_preamble() .. "\n\\begin{document}\n\\begingroup" .. NO_PAGES .. "\n" ..
    code .. "\n\\endgroup\n\\end{document}\n"
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
      return pcall(pandoc.pipe, "lualatex",
        { "-interaction=nonstopmode", "-halt-on-error", "-output-directory=" .. tmp, tex }, "")
    end)
    local pdf = pandoc.path.join({ tmp, "cell.pdf" })
    if not ok or not read(pdf) then
      local log = read(pandoc.path.join({ tmp, "cell.log" })) or ""
      local err = log:match("\n(! [^\n]*\n[^\n]*)") or "see the LaTeX log"
      quarto.log.warning("phu: LaTeX cell failed, left out of HTML:\n" .. err ..
        "\n" .. code:sub(1, 200))
      return
    end
    local svgfile = pandoc.path.join({ tmp, "cell.svg" })
    if pcall(pandoc.pipe, "pdftocairo", { "-svg", pdf, svgfile }, "") then
      svg = read(svgfile)
      if svg and not draws(svg) then svg = "" end
    end
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

-- 4. the look ----------------------------------------------------------
local output = dofile(quarto.utils.resolve_path("phu-output.lua"))
local LOOK = false

local function latex_inlines(inlines)
  return pandoc.write(pandoc.Pandoc({ pandoc.Plain(inlines) }), "latex"):gsub("%s+$", "")
end

-- code cell: language tag before the code
local function latex_code_lang(el)
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

local function is_latex(fmt)
  return fmt == "latex" or fmt == "tex"
end

return {
  {
    Meta = function(meta)
      LOOK = meta["phu-look"] == true or pandoc.utils.stringify(meta["phu-look"] or "") == "true"
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
      if not LOOK then return nil end
      local latex = quarto.doc.is_format("latex")
      if el.classes:includes("cell") then return latex and latex_code_lang(el) or nil end
      return output.transform(el, latex)
    end,
    Callout = function(el)
      if LOOK and quarto.doc.is_format("latex") then return latex_callout(el) end
    end,
    RawBlock = function(el)
      local web = quarto.doc.is_format("html") or quarto.doc.is_format("epub")
      if not (web and is_latex(el.format)) then return nil end
      local svg = to_svg(el.text)
      if not svg or svg == "" then return {} end
      local src = "data:image/svg+xml;base64," .. quarto.base64.encode(svg)
      return pandoc.Para({ pandoc.Image({}, src, "", pandoc.Attr("", { "phu-svg" })) })
    end,
  },
}
