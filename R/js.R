#' Evaluate JavaScript in the page
#'
#' Evaluates `expr` in the page, optionally awaiting a returned promise, and
#' returns the resulting value. This is the primitive all element work uses,
#' and an escape hatch for one-off scripts. Unlike most `pz_*()` functions it
#' **ends the chain**: it returns the value, not the context.
#'
#' @inheritParams pz_click
#' @param expr A string of JavaScript to evaluate.
#' @param await Await a promise returned by `expr` before returning its value.
#' @param timeout Seconds before the evaluation fails; `NULL` uses the
#'   session default.
#'
#' @return The value produced by `expr` (converted to R), or `NULL`.
#'
#' @examplesIf paparazzi:::examples_run()
#' page <- pz_open(pz_example("tasks"))
#' pz_js(page, "document.querySelectorAll('.task').length")
#'
#' # Arrays come back as lists
#' pz_js(page, "[...document.querySelectorAll('.task-priority')].map(el => el.textContent)")
#'
#' # Returned promises are awaited
#' pz_js(page, "new Promise(resolve => setTimeout(() => resolve('done'), 100))")
#' pz_close(page)
#'
#' @export
pz_js <- function(ctx, expr, ..., await = TRUE, timeout = NULL) {
  check_context(ctx)
  check_dots_empty()
  check_string(expr)
  check_bool(await)
  timeout <- resolve_timeout(timeout, ctx$page)

  res <- cdp_call(
    ctx$page$session$Runtime$evaluate(
      expr,
      awaitPromise = await,
      returnByValue = TRUE,
      timeout_ = timeout
    ),
    timeout,
    "evaluating JavaScript"
  )
  err <- res$exceptionDetails
  if (!is.null(err)) {
    # Non-Error throws (throw "x", Promise.reject("x")) have no
    # description; the thrown value is all there is.
    msg <- err$exception$description %||% err$text %||% "unknown error"
    thrown <- err$exception$value
    if (
      is.null(err$exception$description) &&
        is.atomic(thrown) &&
        length(thrown) == 1
    ) {
      msg <- as.character(thrown)
    }
    cli::cli_abort(
      "JavaScript error: {msg}",
      class = "paparazzi_error_js"
    )
  }
  js_value(res$result)
}

#' Get the underlying ChromoteSession
#'
#' Escape hatch for raw Chrome DevTools Protocol calls.
#'
#' @inheritParams pz_click
#'
#' @return The `chromote::ChromoteSession` backing the page.
#'
#' @examplesIf paparazzi:::examples_run()
#' page <- pz_open(pz_example("tasks"))
#' session <- pz_chromote(page)
#'
#' # Make raw Chrome DevTools Protocol calls
#' session$Browser$getVersion()$product
#' session$Performance$enable()
#' metrics <- session$Performance$getMetrics()$metrics
#' Filter(function(m) m$name == "Nodes", metrics)[[1]]$value
#' pz_close(page)
#'
#' @export
pz_chromote <- function(ctx) {
  check_context(ctx)
  ctx$page$session
}

# CDP reports NaN/Infinity/-Infinity/-0/BigInt as unserializableValue
# with no value field.
js_value <- function(result) {
  if (!is.null(result$value)) {
    return(result$value)
  }
  uv <- result$unserializableValue
  if (is.null(uv)) {
    return(NULL)
  }
  switch(
    uv,
    "NaN" = NaN,
    "Infinity" = Inf,
    "-Infinity" = -Inf,
    "-0" = -0,
    {
      num <- suppressWarnings(as.numeric(sub("n$", "", uv)))
      if (is.na(num)) uv else num
    }
  )
}
