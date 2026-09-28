# Vendored subset of rlang's standalone-purrr.R (unlicense):
# https://github.com/r-lib/rlang/blob/main/R/standalone-purrr.R
#
# Internal-only purrr-like API on top of base R. Not drop-in replacements
# for purrr; deliberately unexported so a future purrr import can't clash.
# Only helpers with call sites in this package are vendored -- to add more,
# copy fresh from the upstream standalone (behavior quirks there are known
# and accepted, e.g. map2 recycles unequal lengths like mapply).
#
# map2 has no direct call sites but backs imap.
#
# cursor.R collates after this file via its @include roxygen tag, because
# its load-time CURSOR_ART block calls these helpers.

map_lgl <- function(.x, .f, ...) {
  .rlang_purrr_map_mold(.x, .f, logical(1), ...)
}
map_dbl <- function(.x, .f, ...) {
  .rlang_purrr_map_mold(.x, .f, double(1), ...)
}
map_chr <- function(.x, .f, ...) {
  .rlang_purrr_map_mold(.x, .f, character(1), ...)
}

.rlang_purrr_map_mold <- function(.x, .f, .mold, ...) {
  .f <- as_function(.f, env = global_env())
  out <- vapply(.x, .f, .mold, ..., USE.NAMES = FALSE)
  names(out) <- names(.x)
  out
}

map2 <- function(.x, .y, .f, ...) {
  .f <- as_function(.f, env = global_env())
  out <- mapply(.f, .x, .y, MoreArgs = list(...), SIMPLIFY = FALSE)
  if (length(out) == length(.x)) {
    set_names(out, names(.x))
  } else {
    set_names(out, NULL)
  }
}

imap <- function(.x, .f, ...) {
  map2(.x, names(.x) %||% seq_along(.x), .f, ...)
}

some <- function(.x, .p, ...) {
  .p <- as_function(.p, env = global_env())

  for (i in seq_along(.x)) {
    if (is_true(.p(.x[[i]], ...))) {
      return(TRUE)
    }
  }
  FALSE
}

every <- function(.x, .p, ...) {
  .p <- as_function(.p, env = global_env())

  for (i in seq_along(.x)) {
    if (!is_true(.p(.x[[i]], ...))) {
      return(FALSE)
    }
  }
  TRUE
}
