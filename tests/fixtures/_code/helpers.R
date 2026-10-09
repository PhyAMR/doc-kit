# Helpers kept in their own file and brought into documents in several ways.

## ---- moving-average
moving_average <- function(x, k = 3) {
  as.numeric(stats::filter(x, rep(1 / k, k), sides = 2))[-c(1, length(x))]
}

## ---- greeting
greeting <- "hello from _code/helpers.R"
