# r/phu.R: what each class becomes, and what knitr keeps printing.
# Run: Rscript tests/unit/test_phu.R (tests/run does, with the lab's R library)
kit <- normalizePath(file.path(dirname(sub("--file=", "", grep("--file=", commandArgs(FALSE), value = TRUE))), "..", ".."))
info <- tempfile(fileext = ".json")
fails <- 0
check <- function(what, ok) {
  if (!isTRUE(ok)) { fails <<- fails + 1; cat("FAIL:", what, "\n") }
}

# the look off: nothing is defined
writeLines('{"format": {"metadata": {"phu-look": false}}}', info)
Sys.setenv(QUARTO_EXECUTE_INFO = info)
source(file.path(kit, "r", "phu.R"))
check("look off leaves no render function", !exists(".phu_render", envir = globalenv()))

writeLines('{"format": {"metadata": {"phu-look": true}}}', info)
source(file.path(kit, "r", "phu.R"))
render <- get(".phu_render", envir = globalenv())

html <- render(data.frame(text = c("$5", "<b>", "a & b", "**x**"), n = 1:4))
check("frame is an HTML table", grepl('^<table class="dataframe">', html))
check("cells escaped", grepl("<td>&lt;b&gt;</td>", html, fixed = TRUE) && grepl("<td>a &amp; b</td>", html, fixed = TRUE))
check("markdown characters kept as text", grepl("<td>**x**</td>", html, fixed = TRUE) && grepl("<td>$5</td>", html, fixed = TRUE))
check("numbers right aligned", grepl('<td style="text-align: right;">1</td>', html, fixed = TRUE))

long <- render(iris)
check("long frame: header + head + gap + tail", lengths(regmatches(long, gregexpr("<tr><th>", long))) == 1 + 5 + 1 + 5)
check("long frame: size line", grepl("<p>150 rows \u00d7 5 columns</p>", long, fixed = TRUE))
check("long frame: last row kept", grepl("<tr><th>150</th>", long, fixed = TRUE))

wide <- render(as.data.frame(matrix(1:60, 3)))
check("wide frame: gap column", grepl("<th>\u22ef</th>", wide, fixed = TRUE) && grepl("<th>V20</th>", wide, fixed = TRUE))
check("row names kept", grepl("<tr><th>Mazda RX4</th>", render(head(mtcars)), fixed = TRUE))

if (requireNamespace("tibble", quietly = TRUE)) {
  tib <- render(tibble::tibble(id = 1:2, items = list(1:3, letters[1:2])))
  check("tibble with a list column", grepl("<td>1, 2, 3</td>", tib, fixed = TRUE))
}

md <- render(matrix(c(1, -2.5, 3, NA), 2))
check("matrix as bmatrix", grepl("\\begin{bmatrix}", md, fixed = TRUE) && grepl("{.phu-shape}", md, fixed = TRUE))
check("negative by value", grepl("\\phuneg{\\texttt{-2.5}}", md, fixed = TRUE) && lengths(regmatches(md, gregexpr("phuneg", md))) == 1)
check("logical matrix", grepl("\\texttt{TRUE}", render(matrix(c(TRUE, FALSE), 1)), fixed = TRUE))
check("named numeric matrix is a table", grepl("<table", render(cor(mtcars[, 1:3])), fixed = TRUE))
big <- render(matrix(1:400, 20))
check("big matrix: dots", grepl("\\ddots", big, fixed = TRUE) && grepl("integer \u00b7 20 \u00d7 20", big, fixed = TRUE))

for (x in list(1:30, letters, factor(c("a", "b")), table(c(1, 1, 2)), list(a = 1), "a string",
               matrix(letters[1:4], 2), summary(lm(mpg ~ wt, mtcars))))
  check(paste("stays knitr's printing:", class(x)[1]), is.null(render(x)))

knitr::opts_knit$set(rmarkdown.df_print = "kable")
check("df-print set in the document wins", is.null(render(head(mtcars))))
knitr::opts_knit$set(rmarkdown.df_print = NULL)

if (fails) {
  cat(fails, "R checks failed\n"); quit(status = 1)
} else cat("all R checks passed\n")
