--[[
  phu-output.lua: code output in the phunotes look.

  Decides from the structure Quarto and the kernels produce, never from
  the text of the output: what was printed is shown as printed.

    .cell-output-stdout / -stderr / -error
        console text. LaTeX: the code block inside phuout, labelled
        out / msg / error; HTML and EPUB style the same classes in CSS.
    a table in .cell-output-display
        a displayed data frame (pandas' HTML, or R's from phu.R), which
        Quarto has already parsed into a table. Row-header columns (the
        index, row names) left, data columns right; LaTeX: the row headers
        in the faint ink.
    other raw HTML in .cell-output-display
        e.g. pandas' "100 rows × 3 columns" under a long frame: read as
        HTML for formats that drop raw HTML, and set small and faint.
    .phu-array (Markdown written by phu.py / phu.R for matrices)
        LaTeX: centred, its .phu-shape line set as a label.

  Used by phu.lua (doc-kit) and vendored by projects that cannot depend
  on the kit; keep it self-contained.
--]]

local M = {}

local LABELS = { ["cell-output-stdout"] = "out", ["cell-output-stderr"] = "msg",
                 ["cell-output-error"] = "error" }

local function raw(s) return pandoc.RawBlock("latex", s) end

local function console(el, label, latex)
  if not latex then return nil end
  local out = pandoc.Blocks({})
  for _, b in ipairs(el.content) do
    if b.t == "CodeBlock" then
      out:extend({ raw("\\begin{phuout}[" .. label .. "]"), b, raw("\\end{phuout}") })
    else
      out:insert(b)
    end
  end
  el.content = out
  return el
end

local function is_row_header(cell)
  return cell.attributes["data-quarto-table-cell-role"] == "th"
end

-- index cells faint (LaTeX); row-header columns left, data columns right,
-- as Jupyter and R's console show a data frame
local function style_table(tbl, latex)
  local first = tbl.bodies[1] and tbl.bodies[1].body[1]
  local heads = 0
  if first then
    for _, c in ipairs(first.cells) do
      if not is_row_header(c) then break end
      heads = heads + 1
    end
  end
  for k, spec in ipairs(tbl.colspecs) do
    tbl.colspecs[k] = { k <= heads and pandoc.AlignLeft or pandoc.AlignRight, spec[2] }
  end
  if latex then
    for _, body in ipairs(tbl.bodies) do
      for _, row in ipairs(body.body) do
        for _, c in ipairs(row.cells) do
          if is_row_header(c) then
            local inl = pandoc.utils.blocks_to_inlines(c.contents)
            inl:insert(1, pandoc.RawInline("latex", "\\textcolor{inkFaint}{"))
            inl:insert(pandoc.RawInline("latex", "}"))
            c.contents = { pandoc.Plain(inl) }
          end
        end
      end
    end
  end
  return tbl
end

local function small_faint(blocks)
  local out = pandoc.Blocks({ raw("{\\centering\\footnotesize\\color{inkFaint}") })
  out:extend(blocks)
  out:insert(raw("\\par}"))
  return out
end

-- Quarto has parsed the tables (they sit in a scaffold Div inside the output)
local function display(el, latex)
  local web = quarto.doc.is_format("html")   -- EPUB counts as html here
  return el:walk({
    Table = function(t) return style_table(t, latex) end,
    RawBlock = function(b)
      if b.format ~= "html" or web then return nil end
      local blocks = pandoc.Blocks(pandoc.read(b.text, "html").blocks)
        :walk({ Div = function(d) return d.content end })
      if #blocks == 0 then return {} end
      return latex and small_faint(blocks) or blocks
    end,
  })
end

local function array(el)
  local out = pandoc.Blocks({ raw("\\begin{phuarray}") })
  for _, b in ipairs(el.content) do
    local shape
    if b.t == "Para" or b.t == "Plain" then
      for _, i in ipairs(b.content) do
        if i.t == "Span" and i.classes:includes("phu-shape") then shape = i end
      end
    end
    if shape then
      out:insert(raw("\\phushape{" .. pandoc.write(pandoc.Pandoc({ pandoc.Plain(shape.content) }), "latex")
        :gsub("%s+$", "") .. "}"))
    else
      out:insert(b)
    end
  end
  out:insert(raw("\\end{phuarray}"))
  return out
end

--- Transform one Div; nil leaves it alone.
function M.transform(el, latex)
  for class, label in pairs(LABELS) do
    if el.classes:includes(class) then return console(el, label, latex) end
  end
  if el.classes:includes("cell-output-display") then return display(el, latex) end
  if el.classes:includes("phu-array") and latex then return array(el) end
  return nil
end

return M
