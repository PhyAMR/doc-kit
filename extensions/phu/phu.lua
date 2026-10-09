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

  5. Reports in a book. A report (phu-report: true, the report template)
     renders on its own, and a book can list it as a chapter: its title
     becomes the chapter title and its sections (# ...) move one level
     down. HTML renders each chapter as its own page, where Quarto shows
     the report's subtitle, author, date and abstract. PDF and EPUB render
     the book as one document; Quarto marks where each file starts
     (quarto-file-metadata) and leaves the chapter's front matter in a
     .quarto-title-block code block, which becomes the report's header
     here, and the report's bibliography is added to the book's.
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

-- 5. reports in a book ---------------------------------------------------
local function truthy(v)
  return v == true or pandoc.utils.stringify(v or "") == "true"
end

-- The JSON in Quarto's <!-- quarto-file-metadata: base64 --> marker
local function file_marker(b)
  local raw = b.t == "RawBlock" and b
    or b.t == "Para" and #b.content == 1 and b.content[1].t == "RawInline" and b.content[1]
  local data = raw and raw.format == "html" and
    raw.text:match("^<!%-%- quarto%-file%-metadata: (%S+) %-%->$")
  if not data then return nil end
  local ok, info = pcall(function() return quarto.json.decode(quarto.base64.decode(data)) end)
  return ok and info or nil
end

local function shift_headers(blocks)
  return pandoc.Blocks(blocks):walk({ Header = function(h)
    h.level = h.level + 1
    return h
  end })
end

local MONTHS = { "January", "February", "March", "April", "May", "June", "July",
  "August", "September", "October", "November", "December" }

-- "2026-10-01" / today -> "October 1, 2026", as Quarto shows dates
local function long_date(s)
  if s == "today" or s == "now" or s == "last-modified" then s = os.date("%Y-%m-%d") end
  local y, m, d = s:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)")
  if not y then return s end
  return ("%s %d, %s"):format(MONTHS[tonumber(m)], tonumber(d), y)
end

local function author_names(author)
  local list = pandoc.utils.type(author) == "List" and author or { author }
  local out = {}
  for _, a in ipairs(list) do
    local name = pandoc.utils.type(a) == "table" and a.name or a
    if pandoc.utils.type(name) == "table" then -- name: {given, family} or {literal}
      name = name.literal or pandoc.utils.stringify(name.given or "") .. " " ..
        pandoc.utils.stringify(name.family or "")
    end
    name = pandoc.utils.stringify(name or ""):match("^%s*(.-)%s*$")
    if name ~= "" then table.insert(out, name) end
  end
  return out
end

-- The report's subtitle, "authors · date" and abstract under the chapter
-- title (PDF and EPUB; Quarto's own block shows only subtitle and abstract)
local function report_header(meta)
  local line = table.concat(author_names(meta.author), ", ")
  if meta.date then
    local date = long_date(pandoc.utils.stringify(meta.date))
    line = line == "" and date or line .. " · " .. date
  end
  local abstract = meta.abstract and as_blocks(meta.abstract) or pandoc.Blocks({})
  if quarto.doc.is_format("latex") and LOOK then
    local blocks = pandoc.Blocks({ pandoc.RawBlock("latex", ("\\begin{phureport}{%s}{%s}"):format(
      meta.subtitle and latex_inlines(meta.subtitle) or "", latex_inlines(pandoc.Inlines(line)))) })
    if #abstract > 0 then blocks:insert(pandoc.RawBlock("latex", "\\phureportabstract")) end
    blocks:extend(abstract)
    blocks:insert(pandoc.RawBlock("latex", "\\end{phureport}"))
    return blocks
  end
  local content = pandoc.Blocks({})
  if meta.subtitle then
    content:insert(pandoc.Div(pandoc.Para(meta.subtitle), pandoc.Attr("", { "subtitle" })))
  end
  if line ~= "" then
    content:insert(pandoc.Div(pandoc.Para(pandoc.Inlines(line)), pandoc.Attr("", { "byline" })))
  end
  if #abstract > 0 then
    content:insert(pandoc.Div(abstract, pandoc.Attr("", { "abstract" })))
  end
  return pandoc.Blocks({ pandoc.Div(content, pandoc.Attr("", { "phu-report" })) })
end

local function as_list(v)
  if v == nil then return pandoc.List() end
  return pandoc.utils.type(v) == "List" and v or pandoc.List({ v })
end

-- Quarto's book: HTML renders each chapter alone (the report's metadata is
-- the document's), PDF and EPUB one document holding every chapter.
local function reports_in_book(doc)
  local meta = doc.meta
  if not meta.book or truthy(meta["phu-chapter-preview"]) then return nil end
  if truthy(meta["phu-report"]) then
    doc.blocks = shift_headers(doc.blocks)
    return doc
  end
  local out, found, in_report, dir = pandoc.Blocks({}), false, false, "."
  local bibs = as_list(meta.bibliography)
  for _, b in ipairs(doc.blocks) do
    local marker = file_marker(b)
    if marker and marker.bookItemType then -- the next chapter (or part, appendix)
      in_report, dir = false, marker.resourceDir or "."
      out:insert(b)
    elseif b.t == "Div" and b.classes:find_if(function(c) return c:match("^quarto%-book%-") end) then
      in_report = false
      out:insert(b)
    elseif b.t == "CodeBlock" and b.classes:includes("quarto-title-block") then
      local fm = pandoc.read(b.text, "markdown").meta
      if truthy(fm["phu-report"]) then
        found, in_report = true, true
        out:extend(report_header(fm))
        for _, bib in ipairs(as_list(fm.bibliography)) do
          bibs:insert(pandoc.path.normalize(pandoc.path.join({ dir, pandoc.utils.stringify(bib) })))
        end
      else
        out:insert(b)
      end
    else
      out:extend(in_report and shift_headers({ b }) or { b })
    end
  end
  if not found then return nil end
  doc.blocks = out
  if #bibs > 0 then
    local seen, unique = {}, pandoc.List()
    for _, bib in ipairs(bibs) do
      local path = pandoc.utils.stringify(bib)
      if not seen[path] then
        seen[path] = true
        unique:insert(pandoc.MetaString(path))
      end
    end
    doc.meta.bibliography = unique
  end
  return doc
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
        -- (quarto_view passes phu-chapter-offset, and number-offset for HTML);
        -- a report keeps its own title page
        if meta["phu-chapter-preview"] and not truthy(meta["phu-report"]) then
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
  { Pandoc = reports_in_book },
}
