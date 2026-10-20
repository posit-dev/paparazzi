#' Describe a JavaScript condition for a locator
#'
#' [pz_js()] wraps a trusted JavaScript function-source string for [pz_loc()]'s
#' `match`. It does not execute the source or open a browser. paparazzi calls
#' the function with each candidate DOM element when it resolves the locator.
#' The function must return primitive `true` or `false`; missing returns,
#' other values, Boolean objects, and Promises are errors. Async functions
#' and awaiting are not supported.
#'
#' Keep functions inexpensive and free of side effects. The read-only
#' contract is not a sandbox: functions may inspect ancestors, descendants,
#' computed styles, and page state outside the candidate scope. Only use
#' trusted source. A timeout does not forcibly stop runaway JavaScript.
#' Use [pz_evaluate()] to execute JavaScript immediately, or [pz_expect_js()]
#' for an existing JavaScript expectation.
#'
#' @param source A single function-source string, e.g.
#'   `"el => el.parentElement.matches('.ready')"` or
#'   `"function(el) { return el.querySelector('.status') !== null; }"`.
#'
#' @return An S3 object of class `paparazzi_js`.
#' @examples
#' ready <- pz_js('el => el.querySelector(".status")?.textContent === "Ready"')
#' pz_loc("tr", match = ready)
#'
#' @export
pz_js <- function(source) {
  check_string(source)
  structure(list(source = source), class = "paparazzi_js")
}

#' @export
print.paparazzi_js <- function(x, ...) {
  cli::cat_line("<paparazzi_js> ", format_js(x))
  invisible(x)
}

#' Evaluate JavaScript in the page
#'
#' Evaluates `expr` in the page, optionally awaiting a returned promise, and
#' returns the resulting value. This is paparazzi's equivalent of Playwright's
#' `page.evaluate()` (and likewise Puppeteer and the CDP `Runtime.evaluate`).
#' It is the primitive all element work uses and an escape hatch for one-off
#' scripts. Unlike most `pz_*()` functions it
#' **ends the chain**: it returns the value, not the context.
#'
#' @inheritParams pz_act_click
#' @param expr A string of JavaScript to evaluate.
#' @param await Await a promise returned by `expr` before returning its value.
#' @param timeout Seconds before the evaluation fails; `NULL` uses the
#'   session default.
#'
#' @return The value produced by `expr` (converted to R), or `NULL`.
#'
#' @examplesIf paparazzi:::examples_run(site = TRUE)
#' page <- pz_open(pz_example("tasks"))
#' pz_evaluate(page, "document.querySelectorAll('.task').length")
#'
#' # Arrays come back as lists
#' pz_evaluate(page, "[...document.querySelectorAll('.task-priority')].map(el => el.textContent)")
#'
#' # Returned promises are awaited
#' pz_evaluate(page, "new Promise(resolve => setTimeout(() => resolve('done'), 100))")
#' pz_close(page)
#'
#' @export
pz_evaluate <- function(ctx, expr, ..., await = TRUE, timeout = NULL) {
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
#' @inheritParams pz_act_click
#'
#' @return The `chromote::ChromoteSession` backing the page.
#'
#' @examplesIf paparazzi:::examples_run(site = TRUE)
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

is_js <- function(x) {
  inherits(x, "paparazzi_js")
}

format_js <- function(x) {
  paste0("pz_js(", encodeString(x$source, quote = '"'), ")")
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
