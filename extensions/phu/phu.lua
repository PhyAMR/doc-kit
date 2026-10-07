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
