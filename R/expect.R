#' Expect at least one element to match
#'
#' `pz_expect_exists()` passes when at least one element matching `target`
#' is in the DOM, visible or not. It's the one expectation where multiple
#' matches don't all have to satisfy the check: existence needs only one.
#' With `not = TRUE` it passes when nothing matches.
#'
#' Expectations retry until they pass or `timeout` elapses, then return
#' `ctx` invisibly. Outside of testthat, a failure aborts with a classed
#' error of class `"paparazzi_expectation_failure"` showing the target,
#' the last observed value, and the time waited; inside testthat, the
#' failure is instead reported as a test failure, and a pass counts as a
#' successful testthat expectation.
#'
#' @param ctx A paparazzi context.
#' @param ... Checked empty; reserved for future use.
#' @param target A CSS selector string, a [pz_loc()] spec, or a list of
#'   specs and strings (a union matching any of them). `NULL` means the
#'   current context: today only the root exists, where it stands for the
#'   page body, so `pz_expect_exists(page)` trivially passes.
#' @param not Invert the check.
#' @param timeout Seconds to wait for the expectation to pass; `NULL`
#'   (default) uses the session default, `0` checks once.
#' @return `ctx`, invisibly.
#' @examples
#' \dontrun{
#' page <- pz_open("https://example.com")
#' page |> pz_expect_exists(target = "a")
#' page |> pz_expect_exists(target = ".modal", not = TRUE)
#' }
#' @export
pz_expect_exists <- function(
  ctx,
  ...,
  target = NULL,
  not = FALSE,
  timeout = NULL
) {
  check_dots_empty()
  expect_impl(
    ctx = ctx,
    target = target,
    not = not,
    timeout = timeout,
    check = check_exists(not),
    description = if (not) "Expected no element to match" else "Expected an element to match",
    call = current_env()
  )
}

#' Expect a number of matching elements
#'
#' `pz_expect_count()` passes when the number of elements matching
#' `target` satisfies the requirement: `n` is exact, or `min` and/or
#' `max` give an inclusive range (either may be `NULL`, meaning
#' unbounded). With `not = TRUE` it passes when the count does anything
#' else. Specify exactly one of `n` or `min`/`max`.
#'
#' Outside of testthat, a failure aborts with a classed error of class
#' `"paparazzi_expectation_failure"`; inside testthat, the failure is
#' reported as a test failure instead. See [pz_expect_exists()] for the
#' retry, timeout, and bridge behavior shared by all expectations.
#'
#' @param ctx A paparazzi context.
#' @param n Exact number of matching elements.
#' @param ... Checked empty; reserved for future use.
#' @param min Inclusive lower bound on the number of matches (`NULL` =
#'   unbounded).
#' @param max Inclusive upper bound on the number of matches (`NULL` =
#'   unbounded).
#' @param target A CSS selector string, a [pz_loc()] spec, or a list of
#'   specs and strings (a union matching any of them). `NULL` means the
#'   page body.
#' @param not Invert the check.
#' @param timeout Seconds to wait for the expectation to pass; `NULL`
#'   (default) uses the session default, `0` checks once.
#' @return `ctx`, invisibly.
#' @examples
#' \dontrun{
#' page <- pz_open("https://example.com")
#' page |> pz_expect_count(1, target = "h1")
#' page |> pz_expect_count(min = 1, target = "a")
#' page |> pz_expect_count(0, target = ".modal", not = TRUE)
#' }
#' @export
pz_expect_count <- function(
  ctx,
  n = NULL,
  ...,
  min = NULL,
  max = NULL,
  target = NULL,
  not = FALSE,
  timeout = NULL
) {
  check_dots_empty()
  call <- current_env()
  if (!is.null(n)) {
    if (!is.null(min) || !is.null(max)) {
      cli::cli_abort(
        "Can't combine {.arg n} with {.arg min} or {.arg max}; {.arg n} is exact, so specify one or the other.",
        class = "paparazzi_error_input",
        call = call
      )
    }
    check_number_whole(n, min = 0)
    min <- n
    max <- n
  } else {
    if (is.null(min) && is.null(max)) {
      cli::cli_abort(
        "Specify {.arg n} for an exact count, or {.arg min} and/or {.arg max} for a range.",
        class = "paparazzi_error_input",
        call = call
      )
    }
    if (!is.null(min)) {
      check_number_whole(min, min = 0)
    }
    if (!is.null(max)) {
      check_number_whole(max, min = 0)
    }
    if (!is.null(min) && !is.null(max) && min > max) {
      cli::cli_abort(
        "{.arg min} ({min}) can't be greater than {.arg max} ({max}).",
        class = "paparazzi_error_input",
        call = call
      )
    }
  }
  expect_impl(
    ctx = ctx,
    target = target,
    not = not,
    timeout = timeout,
    check = check_count(min, max, not),
    description = expect_headline_count(n, min, max, not),
    call = call
  )
}

#' Expect elements to be visible
#'
#' `pz_expect_visible()` passes when at least one element matches and
#' every match is visible. `pz_expect_hidden()` is exactly
#' `pz_expect_visible(not = TRUE)`: it passes when no match is visible,
#' including when nothing matches.
#'
#' Visibility follows the browser's own
#' [checkVisibility()](https://developer.mozilla.org/en-US/docs/Web/API/Element/checkVisibility)
#' with CSS checks, so `display: none` and `visibility: hidden` anywhere
#' up the ancestor chain count as hidden; opacity and viewport position
#' are not considered (a `pz_expect_in_viewport()` entry may arrive
#' later).
#'
#' Outside of testthat, a failure aborts with a classed error of class
#' `"paparazzi_expectation_failure"`; inside testthat, the failure is
#' reported as a test failure instead. See [pz_expect_exists()] for the
#' retry, timeout, and bridge behavior shared by all expectations.
#'
#' @param ctx A paparazzi context.
#' @param ... Checked empty; reserved for future use.
#' @param target A CSS selector string, a [pz_loc()] spec, or a list of
#'   specs and strings (a union matching any of them). `NULL` means the
#'   page body.
#' @param not Invert the check.
#' @param timeout Seconds to wait for the expectation to pass; `NULL`
#'   (default) uses the session default, `0` checks once.
#' @return `ctx`, invisibly.
#' @examples
#' \dontrun{
#' page <- pz_open("https://example.com")
#' page |> pz_expect_visible(target = "h1")
#' page |> pz_expect_hidden(target = ".modal")
#' }
#' @export
pz_expect_visible <- function(
  ctx,
  ...,
  target = NULL,
  not = FALSE,
  timeout = NULL
) {
  check_dots_empty()
  expect_impl(
    ctx = ctx,
    target = target,
    not = not,
    timeout = timeout,
    check = check_visible(not),
    description = if (not) "Expected no element to be visible" else "Expected all elements to be visible",
    call = current_env()
  )
}

#' @rdname pz_expect_visible
#' @export
pz_expect_hidden <- function(
  ctx,
  ...,
  target = NULL,
  not = FALSE,
  timeout = NULL
) {
  pz_expect_visible(ctx, ..., target = target, not = !not, timeout = timeout)
}

#' Expect element text content
#'
#' `pz_expect_text()` passes when at least one element matches and the
#' text of every match satisfies `text`. Whitespace collapses on both
#' sides before comparing, so `"Save   now"` matches text reading
#' "Save now".
#'
#' A length-1 `text` applies to every match. A length-`n` `text` requires
#' exactly `n` matches and compares pairwise, in order. With
#' `not = TRUE`, the expectation passes when no match satisfies `text`,
#' including when nothing matches.
#'
#' Outside of testthat, a failure aborts with a classed error of class
#' `"paparazzi_expectation_failure"`; inside testthat, the failure is
#' reported as a test failure instead. See [pz_expect_exists()] for the
#' retry, timeout, and bridge behavior shared by all expectations.
#'
#' @param ctx A paparazzi context.
#' @param text A character vector of expected text: length 1 applies to
#'   every match, length `n` is compared pairwise in order.
#' @param ... Checked empty; reserved for future use.
#' @param match How to compare `text`: `"contains"` (substring),
#'   `"exact"`, or `"regex"` (an R regex matched with [grepl()]).
#' @param target A CSS selector string, a [pz_loc()] spec, or a list of
#'   specs and strings (a union matching any of them). `NULL` means the
#'   page body, so `pz_expect_text(page, "Welcome")` checks the page text.
#' @param not Invert the check.
#' @param timeout Seconds to wait for the expectation to pass; `NULL`
#'   (default) uses the session default, `0` checks once.
#' @return `ctx`, invisibly.
#' @examples
#' \dontrun{
#' page <- pz_open("https://example.com")
#' page |> pz_expect_text("Example Domain")
#' page |> pz_expect_text("Example", target = "h1", match = "exact")
#' page |> pz_expect_text("example", target = "h1", not = TRUE)
#' }
#' @export
pz_expect_text <- function(
  ctx,
  text,
  ...,
  target = NULL,
  match = c("contains", "exact", "regex"),
  not = FALSE,
  timeout = NULL
) {
  check_dots_empty()
  # rlang exports no check_character(); the hand-rolled equivalent
  # (type + at least one element) uses its conventions.
  if (!is.character(text)) {
    stop_input_type(text, "a character vector")
  }
  if (!length(text)) {
    cli::cli_abort(
      "{.arg text} must have at least one element.",
      class = "paparazzi_error_input"
    )
  }
  match <- arg_match(match)
  expect_impl(
    ctx = ctx,
    target = target,
    not = not,
    timeout = timeout,
    check = check_text(collapse_ws(text), match, not),
    description = expect_headline_text(text, match, not),
    call = current_env()
  )
}

#' Retry an expectation check
#'
#' Like `pz_poll()`, but instead of aborting on the deadline it returns
#' the last failure result so the caller can raise the rich classed
#' error. `fn()` returns `list(pass = TRUE)` or `list(pass = FALSE,
#' observed = <value for the error>)`. Between checks, pumps `loop` (the
#' page's child loop) so timers keep firing. `timeout = 0` checks once.
#'
#' @noRd
expect_retry <- function(fn, timeout, loop, interval = 0.1) {
  deadline <- Sys.time() + timeout
  repeat {
    result <- fn()
    if (isTRUE(result$pass)) {
      return(invisible(result))
    }
    remaining <- as.numeric(difftime(deadline, Sys.time(), units = "secs"))
    if (remaining <= 0) {
      return(invisible(result))
    }
    later::run_now(timeoutSecs = min(remaining, interval), loop = loop)
  }
}

#' Drive one expectation: resolve, check, retry
#'
#' Resolves `target` once per poll iteration with `loc_resolve_once()`
#' and releases the handle after each iteration: `check(els)` extracts
#' the observed values to R first, so nothing pins across iterations.
#' `check(els)` returns `list(pass, observed)`; comparison happens in R,
#' not in a JS predicate, so the classed failure reports a real
#' last-seen value. `target = NULL` means the current context: until
#' scoped contexts exist, that's the root, where it resolves to a single
#' implicit `document.body` element -- a one-element JS array, resolved
#' with loc_resolve_once() but without the loc resolver expression.
#' Passes and failures route through the testthat bridge when running
#' inside testthat; outside, a failure is a `paparazzi_expectation_failure`.
#'
#' @noRd
expect_impl <- function(
  ctx,
  target,
  not,
  timeout,
  check,
  description,
  call = caller_env()
) {
  check_bool(not, call = call)
  check_context(ctx, call = call)
  timeout <- resolve_timeout(timeout, ctx$page, call = call)

  if (is.null(target)) {
    expr <- "[document.body]"
    target_desc <- "document.body"
  } else {
    locs <- as_loc_list(target, call = call)
    target_desc <- format_loc(locs)
    expr <- loc_resolver_expr(locs)
  }

  start <- Sys.time()
  result <- expect_retry(
    fn = function() {
      els <- loc_resolve_once(ctx, expr, target_desc, call)
      on.exit(release_elements(els), add = TRUE)
      check(els)
    },
    timeout = timeout,
    loop = ctx$page$child_loop
  )
  waited <- round(as.numeric(difftime(Sys.time(), start, units = "secs")), 1)

  msg <- expect_failure_message(description, target_desc, result$observed, waited)
  if (isTRUE(result$pass)) {
    expect_bridge(TRUE, msg)
    return(invisible(ctx))
  }
  if (expect_bridge(FALSE, msg)) {
    # Inside testthat the failure is already registered as a test failure.
    return(invisible(ctx))
  }
  cli::cli_abort(msg, class = "paparazzi_expectation_failure", call = call)
}

# testthat is in Suggests: inside tests, passes count and failures are
# reported through testthat::expect(); anywhere else, the caller gets the
# classed error instead. Returns FALSE when the bridge is inactive.
expect_bridge <- function(ok, msg) {
  if (!requireNamespace("testthat", quietly = TRUE) || !testthat::is_testing()) {
    return(FALSE)
  }
  testthat::expect(ok, paste(msg, collapse = "\n"))
  TRUE
}

# The SPEC's failure format: headline, Target, Last seen, Waited. Unnamed
# cli_abort() bullets render one per line, indented by the error display.
expect_failure_message <- function(headline, target, observed, waited) {
  c(
    headline,
    paste0("Target: ", target),
    paste0("Last seen: ", observed),
    paste0("Waited ", waited, "s.")
  )
}

# Read observed values off a resolved element array with one
# callFunctionOn. The handle is released by the caller right after;
# timeouts surface as paparazzi_error_timeout, like loc_resolve_once().
els_call <- function(els, js, call = caller_env()) {
  timeout <- els$page$default_timeout
  res <- tryCatch(
    els$page$session$Runtime$callFunctionOn(
      js,
      objectId = els$object_id,
      returnByValue = TRUE,
      timeout_ = timeout
    ),
    error = function(e) {
      if (grepl("timed out", conditionMessage(e), ignore.case = TRUE)) {
        cli::cli_abort(
          "Timed out after {timeout}s reading elements matching {els$description}.",
          class = "paparazzi_error_timeout",
          call = call,
          parent = e
        )
      }
      stop(e)
    }
  )
  err <- res$exceptionDetails
  if (!is.null(err)) {
    cli::cli_abort(
      "JavaScript error reading elements matching {els$description}: {err$exception$description %||% err$text %||% 'unknown error'}.",
      class = "paparazzi_error_js",
      call = call
    )
  }
  unlist(res$result$value)
}

# Whitespace collapse for text comparison, both sides: runs collapse to a
# single space, then leading/trailing space is dropped.
collapse_ws <- function(x) {
  trimws(gsub("\\s+", " ", x))
}

expect_visible_js <- "function() {
  return this.map((el) => el.checkVisibility({ checkVisibilityCSS: true }));
}"

expect_text_js <- "function() {
  return this.map((el) => el.textContent);
}"

expect_seen_count <- function(count) {
  paste0(count, if (count == 1L) " match" else " matches")
}

expect_seen_texts <- function(texts) {
  expect_truncate(paste0('"', texts, '"', collapse = ", "))
}

expect_truncate <- function(x, width = 80) {
  if (nchar(x) > width) {
    paste0(substr(x, 1, width - 3), "...")
  } else {
    x
  }
}

# Each check takes a resolved element set and returns list(pass, observed).
# `not` is folded in at construction: it passes when no match satisfies
# the positive condition, including zero matches (SPEC table).

check_exists <- function(not) {
  function(els) {
    pass <- if (not) els$count == 0L else els$count >= 1L
    list(pass = pass, observed = expect_seen_count(els$count))
  }
}

check_count <- function(min, max, not) {
  # n was already encoded as min = max = n; NULL bounds are unbounded.
  min <- min %||% -Inf
  max <- max %||% Inf
  function(els) {
    pass <- els$count >= min && els$count <= max
    if (not) {
      pass <- !pass
    }
    list(pass = pass, observed = expect_seen_count(els$count))
  }
}

check_visible <- function(not) {
  function(els) {
    if (els$count == 0L) {
      # No remote object exists for an empty set; zero matches satisfies
      # only the negated form.
      return(list(pass = not, observed = expect_seen_count(0L)))
    }
    n_visible <- sum(els_call(els, expect_visible_js))
    pass <- if (not) n_visible == 0L else n_visible == els$count
    list(pass = pass, observed = paste0(n_visible, " of ", els$count, " visible"))
  }
}

check_text <- function(text, match, not) {
  function(els) {
    if (els$count == 0L) {
      return(list(pass = not, observed = expect_seen_count(0L)))
    }
    texts <- collapse_ws(els_call(els, expect_text_js))
    if (length(text) == 1L) {
      # A single value applies to every match; at least one is required.
      hits <- vapply(texts, expect_text_matches, logical(1), pattern = text, match = match)
      # Negated passes only when NO match satisfies (SPEC), which is
      # stronger than "not all": partial satisfaction fails both forms.
      pass <- if (not) !any(hits) else all(hits)
    } else {
      # A vector requires exactly n matches, compared pairwise in order;
      # the negation passes when the pairwise condition doesn't hold.
      pairwise <- els$count == length(text) && all(vapply(
        seq_along(text),
        function(i) expect_text_matches(texts[[i]], text[[i]], match),
        logical(1)
      ))
      pass <- if (not) !pairwise else pairwise
    }
    list(pass = pass, observed = expect_seen_texts(texts))
  }
}

expect_text_matches <- function(x, pattern, match) {
  switch(
    match,
    contains = grepl(pattern, x, fixed = TRUE),
    exact = identical(x, pattern),
    regex = grepl(pattern, x)
  )
}

expect_headline_count <- function(n, min, max, not) {
  what <- if (!is.null(n)) {
    paste0("exactly ", n)
  } else if (is.null(min)) {
    paste0("at most ", max)
  } else if (is.null(max)) {
    paste0("at least ", min)
  } else {
    paste0("between ", min, " and ", max)
  }
  paste0("Expected count ", if (not) "not " else "", "to be ", what)
}

expect_headline_text <- function(text, match, not) {
  what <- switch(
    match,
    contains = paste0('"', text, '"', collapse = ", "),
    exact = paste0('"', text, '"', collapse = ", "),
    regex = paste0("/", text, "/", collapse = ", ")
  )
  verb <- switch(match, contains = "contain", exact = "be", regex = "match")
  label <- if (length(text) == 1L) "text" else "texts"
  paste0("Expected ", label, if (not) " not", " to ", verb, " ", what)
}
