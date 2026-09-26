check_context <- function(
  ctx,
  arg = caller_arg(ctx),
  call = caller_env()
) {
  if (!inherits(ctx, "PaparazziContext")) {
    cli::cli_abort(
      "{.arg {arg}} must be a paparazzi context (from {.fn pz_open} or {.fn pz_find*}), not {.obj_type_friendly {ctx}}.",
      class = "paparazzi_error_context",
      call = call
    )
  }
  if (ctx$page$is_closed()) {
    cli::cli_abort(
      "The page is closed.",
      class = "paparazzi_error_closed",
      call = call
    )
  }
  invisible(ctx)
}

# `which` validation shared by pz_loc() and the pz_find*() family: a
# string ("first"/"last") or a 1-based whole number. The find wrappers
# pass their literal which, so they only need the numeric form.
check_which <- function(
  which,
  strings = TRUE,
  arg = caller_arg(which),
  call = caller_env()
) {
  if (is_string(which)) {
    if (!strings) {
      cli::cli_abort(
        "{.arg {arg}} must be a whole number, not {.str {which}}. Use {.fn pz_find_first} or {.fn pz_find_last} to pick the first or last match.",
        class = "paparazzi_error_input",
        call = call
      )
    }
    return(arg_match(
      which,
      values = c("first", "last"),
      error_arg = arg,
      error_call = call
    ))
  }
  check_number_whole(which, min = 1, arg = arg, call = call)
  which
}

resolve_timeout <- function(
  timeout,
  page,
  arg = caller_arg(timeout),
  call = caller_env()
) {
  if (is.null(timeout)) {
    return(page$default_timeout)
  }
  check_number_decimal(timeout, min = 0, arg = arg, call = call)
  timeout
}

# Force a lazy chromote command, re-raising a chromote timeout as
# paparazzi_error_timeout that names what was being done. `cmd` must stay
# a promise so the command itself runs under the tryCatch.
cdp_call <- function(cmd, timeout, doing, call = caller_env()) {
  tryCatch(
    cmd,
    error = function(e) {
      if (grepl("timed out", conditionMessage(e), ignore.case = TRUE)) {
        cli::cli_abort(
          "Timed out after {timeout}s {doing}.",
          class = "paparazzi_error_timeout",
          call = call,
          parent = e
        )
      }
      stop(e)
    }
  )
}

# A Runtime command succeeds even when the expression throws; the
# exception arrives in the response instead.
cdp_check_exception <- function(res, doing = NULL, call = caller_env()) {
  err <- res$exceptionDetails
  if (is.null(err)) {
    return(invisible(res))
  }
  detail <- err$exception$description %||% err$text %||% "unknown error"
  cli::cli_abort(
    if (is.null(doing)) {
      "JavaScript error: {detail}."
    } else {
      "JavaScript error {doing}: {detail}."
    },
    class = "paparazzi_error_js",
    call = call
  )
}
