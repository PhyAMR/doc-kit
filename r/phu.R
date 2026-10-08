# phu.R: R plots in the phunotes look, for Quarto books and reports.
#
# Code stays ordinary: plot(), hist(), ggplot(). ~/.Rprofile sources this
# when Quarto renders (QUARTO_DOCUMENT_PATH is set; install.sh adds the
# line). If the document uses the look (a phu-* format or
# `phu-look: true` in it, its _quarto*.yml or their metadata-files), it
# - makes theme_phu() the ggplot2 theme, with the ink/rust/grey palette;
# - gives base graphics the same fonts, colours and axes;
# - draws PDF figures with cairo_pdf, which finds EB Garamond.
# Printed output is untouched here: the phu filter typesets it.
# PHU_DISPLAY=0 turns it off.
local({
  INK <- "#1f1d1a"; ACCENT <- "#b4442b"; FAINT <- "#6f6a61"; GRID <- "#ece6da"
  PALETTE <- c(INK, ACCENT, "#8a8374", "#4b463e", "#c9c0ad")
  FAMILY <- "EB Garamond"

  read <- function(path) {
    if (!file.exists(path) || dir.exists(path)) return("")
    paste(readLines(path, n = 4000, warn = FALSE), collapse = "\n")
  }
  wants_look <- function() {
    dir <- Sys.getenv("QUARTO_DOCUMENT_PATH")
    file <- Sys.getenv("QUARTO_DOCUMENT_FILE")
    if (!nzchar(dir)) return(FALSE)
    texts <- if (nzchar(file)) read(file.path(dir, file)) else character()
    d <- normalizePath(dir, mustWork = FALSE)
    repeat {
      ymls <- list.files(d, pattern = "^_quarto(-[[:alnum:]_-]+)?\\.ya?ml$", full.names = TRUE)
      for (y in ymls) {
        text <- read(y)
        texts <- c(texts, text)
        refs <- regmatches(text, gregexpr("(?m)^\\s*-\\s*\\S+\\.ya?ml\\s*$", text, perl = TRUE))[[1]]
        for (r in trimws(sub("^\\s*-\\s*", "", refs))) texts <- c(texts, read(file.path(d, r)))
      }
      parent <- dirname(d)
      if (length(ymls) || parent == d) break
      d <- parent
    }
    any(grepl("phu-look:\\s*true|\\bphu-(pdf|html|epub)(?![.[:alnum:]_-])", texts, perl = TRUE))
  }
  if (!wants_look()) return(invisible())

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
    # pdf() knows only the PostScript fonts; cairo_pdf finds EB Garamond
    if (capabilities("cairo")) knitr::opts_hooks$set(dev = function(options) {
      if (identical(options$dev, "pdf")) options$dev <- "cairo_pdf"
      options
    })
  }
  if (isNamespaceLoaded("knitr")) knitr_setup()
  else setHook(packageEvent("knitr", "onLoad"), knitr_setup)
})
