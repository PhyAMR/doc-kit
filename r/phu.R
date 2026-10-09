# phu.R: R output and plots in the phunotes look, for Quarto books and reports.
#
# Code stays ordinary. ~/.Rprofile sources this when Quarto renders
# (QUARTO_DOCUMENT_PATH is set; install.sh adds the line). If the document
# uses the look (`phu-look: true` in the format metadata Quarto writes to
# the file named by QUARTO_EXECUTE_INFO):
# - auto-printed values are rendered by class, through knitr's `render`
#   chunk option; nothing reads printed text, so print() and cat() stay
#   console text:
#     data frames (tibble, data.table), numeric matrices with dimnames
#                       an HTML table like pandas' (Quarto turns it into a
#                       native table in every format); long and wide ones
#                       keep their head and tail, as in python/phu.py
#     numeric or logical matrices without dimnames
#                       a bracketed matrix (bmatrix, in Markdown)
#     anything else     knitr's usual printing
#   A document that sets `df-print:` keeps its choice for data frames.
# - ggplot2 gets theme_phu() and the ink/rust/grey palette, base graphics
#   the same fonts, colours and axes, PDF figures cairo_pdf.
# PHU_DISPLAY=0 turns it off. An renv project skips ~/.Rprofile: output
# there is knitr's usual, without the look.
local({
  INK <- "#1f1d1a"; ACCENT <- "#b4442b"; FAINT <- "#6f6a61"; GRID <- "#ece6da"
  PALETTE <- c(INK, ACCENT, "#8a8374", "#4b463e", "#c9c0ad")
  FAMILY <- "EB Garamond"
  # the same limits as python/phu.py (pandas' display options there)
  FRAME_MAX_ROWS <- 14; FRAME_HEAD <- 5; FRAME_TAIL <- 5
  FRAME_MAX_COLS <- 8; FRAME_LEFT <- 4; FRAME_RIGHT <- 4
  ARRAY_ROWS <- 10; ARRAY_COLS <- 8; ARRAY_HEAD <- 5; ARRAY_TAIL <- 3
  VDOTS <- "⋮"; CDOTS <- "⋯"; DDOTS <- "⋱"

  wants_look <- function() {
    path <- Sys.getenv("QUARTO_EXECUTE_INFO")
    if (!nzchar(path) || !file.exists(path) || !requireNamespace("jsonlite", quietly = TRUE))
      return(FALSE)
    info <- tryCatch(jsonlite::fromJSON(path, simplifyVector = FALSE), error = function(e) NULL)
    isTRUE(info$format$metadata[["phu-look"]])
  }
  if (!wants_look()) return(invisible())

  # --- display by class ------------------------------------------------
  esc <- function(s) {
    s <- gsub("&", "&amp;", s, fixed = TRUE)
    s <- gsub("<", "&lt;", s, fixed = TRUE)
    gsub(">", "&gt;", s, fixed = TRUE)
  }
  # positions to show along an axis of length n; NA marks the gap
  keep <- function(n, limit, head, tail) {
    if (n <= limit) seq_len(n) else c(seq_len(head), NA, (n - tail + 1):n)
  }

  frame_html <- function(x) {
    x <- as.data.frame(x)
    n <- nrow(x); m <- ncol(x)
    rows <- keep(n, FRAME_MAX_ROWS, FRAME_HEAD, FRAME_TAIL)
    cols <- keep(m, FRAME_MAX_COLS, FRAME_LEFT, FRAME_RIGHT)
    kr <- rows[!is.na(rows)]; kc <- cols[!is.na(cols)]
    sub <- x[kr, kc, drop = FALSE]
    txt <- format(sub)   # R's own printing of each column: digits, NA, dates
    numeric <- vapply(sub, is.numeric, logical(1))
    labels <- rownames(x)[kr]
    td <- function(v, right) paste0("<td", if (right) ' style="text-align: right;"', ">", esc(v), "</td>")
    head <- paste0("<th>", esc(ifelse(is.na(cols), CDOTS, names(x)[ifelse(is.na(cols), 1, cols)])), "</th>",
                   collapse = "")
    body <- vapply(seq_along(rows), function(i) {
      if (is.na(rows[i])) {
        cells <- paste0("<td>", ifelse(is.na(cols), DDOTS, VDOTS), "</td>", collapse = "")
        return(paste0("<tr><th>", VDOTS, "</th>", cells, "</tr>"))
      }
      k <- match(rows[i], kr)
      cells <- vapply(seq_along(cols), function(j) {
        if (is.na(cols[j])) return(paste0("<td>", CDOTS, "</td>"))
        jj <- match(cols[j], kc)
        td(trimws(txt[[jj]][k]), numeric[[jj]])
      }, character(1))
      paste0("<tr><th>", esc(labels[k]), "</th>", paste0(cells, collapse = ""), "</tr>")
    }, character(1))
    dims <- if (n > length(kr) || m > length(kc)) paste0("\n\n<p>", n, " rows × ", m, " columns</p>") else ""
    paste0('<table class="dataframe">\n<thead><tr><th></th>', head, "</tr></thead>\n<tbody>\n",
           paste0(body, collapse = "\n"), "\n</tbody>\n</table>", dims, "\n")
  }

  matrix_md <- function(x) {
    rows <- keep(nrow(x), ARRAY_ROWS, ARRAY_HEAD, ARRAY_TAIL)
    cols <- keep(ncol(x), ARRAY_COLS, ARRAY_HEAD, ARRAY_TAIL)
    kr <- rows[!is.na(rows)]; kc <- cols[!is.na(cols)]
    sub <- x[kr, kc, drop = FALSE]
    txt <- trimws(format(sub))   # one format for the whole matrix, as print() does
    negative <- if (is.numeric(sub)) !is.na(sub) & sub < 0 else sub & FALSE
    lines <- vapply(seq_along(rows), function(i) {
      if (is.na(rows[i])) return(paste(ifelse(is.na(cols), "\\ddots", "\\vdots"), collapse = " & "))
      k <- match(rows[i], kr)
      paste(vapply(seq_along(cols), function(j) {
        if (is.na(cols[j])) return("\\cdots")
        jj <- match(cols[j], kc)
        v <- paste0("\\texttt{", txt[k, jj], "}")
        if (negative[k, jj]) paste0("\\phuneg{", v, "}") else v
      }, character(1)), collapse = " & ")
    }, character(1))
    shape <- paste0(typeof(x), " · ", nrow(x), " × ", ncol(x))
    paste0("::: {.phu-array}\n$$\n\\begin{bmatrix}\n", paste(lines, collapse = " \\\\\n"),
           "\n\\end{bmatrix}\n$$\n\n[", shape, "]{.phu-shape}\n:::\n")
  }

  plain_matrix <- function(x) identical(class(x), c("matrix", "array")) && length(x) > 0
  df_print_set <- function() {
    choice <- knitr::opts_knit$get("rmarkdown.df_print")
    !is.null(choice) && !identical(choice, "default")
  }
  phu_render <- function(x) {
    if (is.data.frame(x) && ncol(x) > 0 && !df_print_set()) return(frame_html(x))
    if (plain_matrix(x) && is.numeric(x) && !is.null(dimnames(x))) return(frame_html(x))
    if (plain_matrix(x) && (is.numeric(x) || is.logical(x))) return(matrix_md(x))
    NULL
  }
  render <- function(x, options, ...) {
    out <- tryCatch(phu_render(x), error = function(e) NULL)
    if (is.null(out)) knitr::knit_print(x, options = options, ...) else knitr::asis_output(out)
  }
  assign(".phu_render", phu_render, envir = globalenv())

  # --- plots -----------------------------------------------------------
  theme_phu <- function(base_size = 10) {
    ggplot2::theme_bw(base_size = base_size, base_family = FAMILY) +
      ggplot2::theme(
        panel.border = ggplot2::element_rect(colour = INK, fill = NA, linewidth = 0.4),
        panel.grid.major = ggplot2::element_line(colour = GRID, linewidth = 0.3),
        panel.grid.minor = ggplot2::element_line(colour = "#f3eee5", linewidth = 0.2),
        axis.ticks = ggplot2::element_line(colour = INK, linewidth = 0.3),
        axis.ticks.length = ggplot2::unit(-3, "pt"),
        axis.text = ggplot2::element_text(colour = FAINT, size = base_size * 0.85),
        legend.key = ggplot2::element_blank(),
        legend.background = ggplot2::element_blank(),
        strip.background = ggplot2::element_blank(),
        strip.text = ggplot2::element_text(colour = INK, hjust = 0),
        plot.title = ggplot2::element_text(hjust = 0, size = base_size),
        plot.title.position = "plot"
      )
  }
  assign("theme_phu", theme_phu, envir = globalenv())

  ggplot_setup <- function(...) {
    ggplot2::theme_set(theme_phu())
    for (geom in c("line", "path", "point", "step", "text"))
      ggplot2::update_geom_defaults(geom, list(colour = INK))
    ggplot2::update_geom_defaults("smooth", list(colour = ACCENT, fill = GRID))
    for (geom in c("bar", "col", "area", "density", "boxplot", "violin"))
      ggplot2::update_geom_defaults(geom, list(fill = "#d8d2c4", colour = INK))
    options(ggplot2.discrete.colour = PALETTE, ggplot2.discrete.fill = PALETTE,
            ggplot2.continuous.colour = function(...) ggplot2::scale_colour_gradient(low = GRID, high = INK, ...),
            ggplot2.continuous.fill = function(...) ggplot2::scale_fill_gradient(low = GRID, high = INK, ...))
  }
  if (isNamespaceLoaded("ggplot2")) ggplot_setup()
  else setHook(packageEvent("ggplot2", "onLoad"), ggplot_setup)

  # base graphics: every new plot starts from these settings
  grDevices::palette(PALETTE)
  setHook("before.plot.new", function() {
    graphics::par(family = FAMILY, fg = INK, col = INK, col.axis = FAINT, col.lab = INK,
                  col.main = INK, font.main = 1, cex.main = 1, tcl = -0.25, mgp = c(2, 0.5, 0),
                  las = 1, bty = "o", lwd = 0.8)
  })

  knitr_setup <- function(...) {
    # rmarkdown registers its own knit_print.data.frame while rendering, so
    # values go through the `render` chunk option instead
    knitr::opts_chunk$set(render = render)
    # pdf() knows only the PostScript fonts; cairo_pdf finds EB Garamond
    if (capabilities("cairo")) knitr::opts_hooks$set(dev = function(options) {
      if (identical(options$dev, "pdf")) options$dev <- "cairo_pdf"
      options
    })
  }
  if (isNamespaceLoaded("knitr")) knitr_setup()
  else setHook(packageEvent("knitr", "onLoad"), knitr_setup)
})
