#' Check that `ctx` is a live paparazzi context
#' @noRd
check_context <- function(
  ctx,
  arg = rlang::caller_arg(ctx),
  call = rlang::caller_env()
) {
  if (!inherits(ctx, "PaparazziContext")) {
    rlang::abort(
      sprintf(
        "`%s` must be a paparazzi context (from `pz_open()` or `pz_find*()`), not %s.",
        arg,
        obj_type_friendly(ctx)
      ),
      class = "paparazzi_error_context",
      call = call
    )
  }
  if (ctx$page$is_closed()) {
    rlang::abort(
      "The page is closed.",
      class = "paparazzi_error_closed",
      call = call
    )
  }
  invisible(ctx)
}

#' Friendly type description for error messages
#' @noRd
obj_type_friendly <- function(x) {
  if (is.object(x)) {
    sprintf("an object of class <%s>", paste(class(x), collapse = "/"))
  } else {
    sprintf("a %s", typeof(x))
  }
}

#' Resolve a per-call timeout against the session default (seconds)
#' @noRd
resolve_timeout <- function(
  timeout,
  page,
  arg = rlang::caller_arg(timeout),
  call = rlang::caller_env()
) {
  if (is.null(timeout)) {
    return(page$default_timeout)
  }
  rlang::check_number_decimal(timeout, min = 0, arg = arg, call = call)
  timeout
}
