#' Describe a JavaScript condition for a locator
#'
#' @description
#' Use [pz_js()] with [pz_loc()] to select elements using a JavaScript
#' condition. For example, you can select a table row only when its status
#' cell says "Ready", rather than checking the text of the whole row. Pass
#' the condition to [pz_loc()]'s `match` argument.
#'
#' paparazzi calls your function with each element and keeps the element
#' when the function returns `true`, or excludes it when it returns `false`.
#' It repeats the check whenever it looks for matching elements, including
#' while waiting for an element to become available.
#'
#' Your function can inspect the element, its parents and children, styles,
#' or other parts of the page. Use it to read the page without changing it:
#' paparazzi does not prevent your JavaScript from making changes. Use code
#' you wrote or understand, and keep the check quick. Code that never
#' finishes, such as an endless loop, can leave the browser unresponsive;
#' setting a timeout does not guarantee that such code will stop.
#'
#' @param source A single string defining a JavaScript function, e.g.
#'   `"el => el.parentElement.matches('.ready')"` or
#'   `"function(el) { return el.querySelector('.status') !== null; }"`.
#'   The function receives a DOM element as its argument. It must return
#'   the JavaScript value `true` or `false`, not a string or another object.
#'   Missing returns are errors. Async functions and functions returning
#'   Promises are not supported.
#'
#' @return A JavaScript condition object of class `paparazzi_js`.
#' @seealso
#' * [pz_loc()] accepts the condition in `match` to select elements.
#' * [pz_regex()] describes a text pattern for a locator or expectation.
#' * [pz_evaluate()] runs JavaScript in the page and returns its result.
#' * [pz_expect_js()] checks a JavaScript condition on selected elements.
#'
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
