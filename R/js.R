#' Evaluate JavaScript in the page
#'
#' Evaluates `expr` in the page, optionally awaiting a returned promise, and
#' returns the resulting value. This is the primitive all element work uses,
#' and an escape hatch for one-off scripts. Unlike most `pz_*()` functions it
#' **ends the chain**: it returns the value, not the context.
#'
#' @param ctx A paparazzi context.
#' @param expr A string of JavaScript to evaluate.
#' @param ... Checked empty; reserved for future use.
#' @param await Await a promise returned by `expr` before returning its value.
#' @return The value produced by `expr` (converted to R), or `NULL`.
#' @export
pz_js <- function(ctx, expr, ..., await = TRUE) {
  check_context(ctx)
  rlang::check_dots_empty()
  rlang::check_string(expr)
  rlang::check_bool(await)

  res <- ctx$page$session$Runtime$evaluate(
    expr,
    awaitPromise = await,
    returnByValue = TRUE
  )
  err <- res$exceptionDetails
  if (!is.null(err)) {
    msg <- err$exception$description %||% err$text %||% "unknown error"
    rlang::abort(
      paste0("JavaScript error: ", msg),
      class = "paparazzi_error_js"
    )
  }
  res$result$value
}

#' Get the underlying ChromoteSession
#'
#' Escape hatch for raw Chrome DevTools Protocol calls.
#'
#' @param ctx A paparazzi context.
#' @return The `chromote::ChromoteSession` backing the page.
#' @export
pz_chromote <- function(ctx) {
  check_context(ctx)
  ctx$page$session
}
