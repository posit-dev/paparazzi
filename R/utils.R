check_context <- function(
  ctx,
  arg = rlang::caller_arg(ctx),
  call = rlang::caller_env()
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
