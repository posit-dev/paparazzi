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

check_annotation_label <- function(label, call = caller_env()) {
  if (is.null(label) || isTRUE(label)) {
    return(label)
  }
  if (
    !(is.character(label) || is.numeric(label)) ||
      length(label) != 1L ||
      is.na(label)
  ) {
    cli::cli_abort(
      "{.arg label} must be `TRUE`, one string or one number.",
      call = call
    )
  }
  as.character(label)
}

check_annotation_id <- function(
  id,
  allow_reserved = FALSE,
  call = caller_env()
) {
  if (is.null(id)) {
    return(invisible(NULL))
  }
  check_string(id, allow_empty = FALSE, call = call)
  if (!allow_reserved && id %in% c("spotlight", "caption")) {
    cli::cli_abort(
      "{.arg id} cannot be {.val spotlight} or {.val caption}.",
      call = call
    )
  }
  invisible(NULL)
}

check_annotation_font_size <- function(
  x,
  arg = caller_arg(x),
  call = caller_env()
) {
  check_positive_css_px(x, arg = arg, call = call)
}

check_positive_css_px <- function(
  x,
  arg = caller_arg(x),
  call = caller_env()
) {
  check_number_decimal(
    x,
    min = 0,
    allow_infinite = FALSE,
    arg = arg,
    call = call
  )
  if (x == 0) {
    cli::cli_abort("{.arg {arg}} must be greater than 0.", call = call)
  }
  invisible(x)
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
