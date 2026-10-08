# phu.R: R output in Quarto documents, in the phunotes look (doc-kit).
#
# Sourced from ~/.Rprofile (install.sh adds the line) when Quarto renders,
# i.e. QUARTO_DOCUMENT_PATH is set; PHU_DISPLAY=0 turns it off. It
# - prints numeric matrices and long numeric vectors as a ::: {.phu-array}
#   grid (the phu filter brackets it in the PDF and styles it in HTML),
#   keeping only the head and tail of big ones;
# - prints data frames (and tibbles) as a booktabs table, truncated, with a
#   "1000 rows × 5 columns" line;
# - sets theme_phu() as the ggplot2 theme when ggplot2 loads.
# Same output as python/phu.py.
local({
  MAX_VECTOR <- 12; MAX_ROWS <- 10; MAX_COLS <- 8; HEAD <- 5; TAIL <- 3
  FRAME_ROWS <- 14; FRAME_HEAD <- 6; FRAME_TAIL <- 4; FRAME_COLS <- 8; MAX_TEXT <- 40
  VDOTS <- "⋮"; CDOTS <- "⋯"; DDOTS <- "⋱"; MINUS <- "−"
  TIMES <- "×"; DOT <- "·"

  # one format for a whole array or column, so the digits line up
  fmt <- function(x) {
    if (is.logical(x)) return(ifelse(is.na(x), "NA", as.character(x)))
    if (is.integer(x)) return(gsub("-", MINUS, ifelse(is.na(x), "NA", as.character(x))))
    ok <- is.finite(x)
    a <- abs(x[ok & x != 0])
    big <- if (length(a)) max(a) else 0
    small <- if (length(a)) min(a) else 0
    if (big >= 1e5 || (small > 0 && small < 1e-3 && big < 1)) {
      s <- formatC(x, format = "e", digits = 3)
    } else {
      dec <- function(v) {
        s <- sub("0+$", "", formatC(abs(v), format = "f", digits = 4))
        if (grepl("\\.", s)) nchar(sub(".*\\.", "", s)) else 0
      }
      d <- if (any(ok)) max(vapply(x[ok], dec, 0)) else 1
      s <- formatC(x, format = "f", digits = min(max(d, 1), 4))
    }
    s[!ok] <- as.character(x[!ok])
    gsub("-", MINUS, trimws(s))
  }

  escape <- function(x) {
    x <- as.character(x)
    long <- !is.na(x) & nchar(x) > MAX_TEXT
    x[long] <- paste0(substr(x[long], 1, MAX_TEXT - 1), "…")
    x[is.na(x)] <- "NA"
    x <- gsub("([\\\\|*_`<>$#\\[\\]])", "\\\\\\1", x, perl = TRUE)
    gsub("\n", " ", x)
  }

  pick <- function(n, limit, head, tail) {
    if (n <= limit) seq_len(n) else c(seq_len(head), NA, (n - tail + 1):n)
  }

  pipe <- function(header, rows, align) {
    line <- function(cells) paste0("| ", paste(cells, collapse = " | "), " |")
    c(line(header),
      paste0("|", paste(ifelse(align == "r", "--:", ":--"), collapse = "|"), "|"),
      vapply(rows, line, ""))
  }

  # rows/cols: indices with NA where the gap goes; m: a numeric matrix
  grid <- function(m, rows, cols, row_labels) {
    rr <- rows[!is.na(rows)]; cc <- cols[!is.na(cols)]
    text <- matrix(fmt(as.vector(m[rr, cc, drop = FALSE])), nrow = length(rr))
    out <- list(); i <- 0
    for (r in rows) {
      if (is.na(r)) {
        out[[length(out) + 1]] <- c(VDOTS, ifelse(is.na(cols), DDOTS, VDOTS))
        next
      }
      i <- i + 1; j <- 0
      cells <- vapply(cols, function(c) if (is.na(c)) CDOTS else "", "")
      cells[!is.na(cols)] <- text[i, ]
      out[[length(out) + 1]] <- c(row_labels(r), cells)
    }
    out
  }

  array_md <- function(m, dims, type) {
    vector <- is.null(dim(m))
    if (vector) {
      cols <- pick(length(m), MAX_VECTOR, HEAD, TAIL)
      rows <- 1; m <- matrix(m, nrow = 1); label <- function(r) ""
    } else {
      rows <- pick(nrow(m), MAX_ROWS, HEAD, TAIL)
      cols <- pick(ncol(m), MAX_COLS, HEAD, TAIL)
      label <- function(r) if (!is.null(rownames(m))) escape(rownames(m)[r]) else as.character(r)
    }
    cn <- if (!vector && !is.null(colnames(m))) escape(colnames(m)) else as.character(seq_len(ncol(m)))
    header <- c("", ifelse(is.na(cols), CDOTS, cn[ifelse(is.na(cols), 1, cols)]))
    body <- grid(m, rows, cols, label)
    paste(c("::: {.phu-array}", pipe(header, body, rep("r", length(header))), "",
            paste(type, DOT, paste(dims, collapse = paste0(" ", TIMES, " "))), ":::", ""),
          collapse = "\n")
  }

  frame_md <- function(df) {
    df <- as.data.frame(df)
    n <- nrow(df); m <- ncol(df)
    rows <- pick(n, FRAME_ROWS, FRAME_HEAD, FRAME_TAIL)
    cols <- pick(m, FRAME_COLS, HEAD, TAIL)
    rr <- rows[!is.na(rows)]
    texts <- list(); align <- "l"
    for (c in cols) {
      if (is.na(c)) { texts[[length(texts) + 1]] <- rep(CDOTS, length(rr)); align <- c(align, "r"); next }
      x <- df[rr, c]
      num <- is.numeric(x)
      texts[[length(texts) + 1]] <- if (num) fmt(x) else escape(x)
      align <- c(align, if (num) "r" else "l")
    }
    header <- c("", ifelse(is.na(cols), CDOTS, escape(names(df))[ifelse(is.na(cols), 1, cols)]))
    labels <- escape(rownames(df))
    body <- list(); i <- 0
    for (r in rows) {
      if (is.na(r)) { body[[length(body) + 1]] <- rep(VDOTS, length(header)); next }
      i <- i + 1
      body[[length(body) + 1]] <- c(labels[r], vapply(texts, function(t) t[i], ""))
    }
    paste(c("::: {.phu-frame}", pipe(header, body, align), "",
            paste(n, "rows", TIMES, m, "columns"), ":::", ""), collapse = "\n")
  }

  knit_matrix <- function(x, ...) {
    if (!(is.numeric(x) || is.logical(x)) || length(dim(x)) != 2 || length(x) == 0) return(NextMethod())
    knitr::asis_output(array_md(x, dim(x), typeof(x)))
  }
  knit_vector <- function(x, ...) {
    if (length(x) <= MAX_VECTOR || !is.null(attributes(x))) return(NextMethod())
    knitr::asis_output(array_md(x, length(x), typeof(x)))
  }
  knit_frame <- function(x, ...) knitr::asis_output(frame_md(x))

  theme_phu <- function(base_size = 10) {
    ink <- "#1f1d1a"; faint <- "#6f6a61"
    ggplot2::theme_bw(base_size = base_size, base_family = "EB Garamond") +
      ggplot2::theme(
        panel.border = ggplot2::element_rect(colour = ink, fill = NA, linewidth = 0.4),
        panel.grid.major = ggplot2::element_line(colour = "#ece6da", linewidth = 0.3),
        panel.grid.minor = ggplot2::element_line(colour = "#f3eee5", linewidth = 0.2),
        axis.ticks = ggplot2::element_line(colour = ink, linewidth = 0.3),
        axis.ticks.length = ggplot2::unit(-3, "pt"),
        axis.text = ggplot2::element_text(colour = faint, size = base_size * 0.85),
        legend.key = ggplot2::element_blank(),
        legend.background = ggplot2::element_blank(),
        strip.background = ggplot2::element_blank(),
        strip.text = ggplot2::element_text(colour = ink, hjust = 0),
        plot.title = ggplot2::element_text(hjust = 0, size = base_size),
        plot.title.position = "plot"
      )
  }
  assign("theme_phu", theme_phu, envir = globalenv())

  register <- function(...) {
    ns <- asNamespace("knitr")
    registerS3method("knit_print", "matrix", knit_matrix, envir = ns)
    registerS3method("knit_print", "numeric", knit_vector, envir = ns)
    # rmarkdown registers its own knit_print.data.frame while rendering,
    # so data frames go through the chunk render option instead
    knitr::opts_chunk$set(render = function(x, ...) {
      if (is.data.frame(x)) knit_frame(x) else knitr::knit_print(x, ...)
    })
    # pdf() knows only the PostScript fonts; cairo_pdf finds EB Garamond
    if (capabilities("cairo")) knitr::opts_hooks$set(dev = function(options) {
      if (identical(options$dev, "pdf")) options$dev <- "cairo_pdf"
      options
    })
  }
  if (isNamespaceLoaded("knitr")) register()
  else setHook(packageEvent("knitr", "onLoad"), register)

  ggplot_setup <- function(...) {
    ggplot2::theme_set(theme_phu())
    ggplot2::update_geom_defaults("line", list(colour = "#1f1d1a"))
    ggplot2::update_geom_defaults("point", list(colour = "#1f1d1a"))
    options(ggplot2.discrete.colour = c("#1f1d1a", "#b4442b", "#8a8374", "#4b463e", "#c9c0ad"))
  }
  if (isNamespaceLoaded("ggplot2")) ggplot_setup()
  else setHook(packageEvent("ggplot2", "onLoad"), ggplot_setup)
})
