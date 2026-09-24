# rlang exports no check_character(); this covers type + minimum length
# + no NAs, following the conventions of rlang's other checkers.
check_character <- function(
  x,
  ...,
  min = 1,
  allow_null = FALSE,
  arg = caller_arg(x),
  call = caller_env()
) {
  if (!missing(x)) {
    if (allow_null && is.null(x)) {
      return(invisible(NULL))
    }
    if (is.character(x)) {
      if (length(x) < min) {
        cli::cli_abort(
          "{.arg {arg}} must have at least {min} element{?s}.",
          class = "paparazzi_error_input",
          call = call
        )
      }
      if (anyNA(x)) {
        cli::cli_abort(
          "{.arg {arg}} can't be `NA`.",
          class = "paparazzi_error_input",
          call = call
        )
      }
      return(invisible(NULL))
    }
  }
  stop_input_type(x, "a character vector", arg = arg, call = call)
}

check_page <- function(
  page,
  arg = caller_arg(page),
  call = caller_env()
) {
  if (!is_pz_page(page)) {
    cli::cli_abort(
      "{.arg {arg}} must be a page from {.fn pz_open}.",
      class = "paparazzi_error_input",
      call = call
    )
  }
  invisible(page)
}

is_pz_page <- function(x) {
  inherits(x, "PaparazziPage")
}
