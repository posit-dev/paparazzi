#' Expect at least one element to match
#'
#' @description
#' [pz_expect_exists()] passes when at least one element matching `target`
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
#' @inheritParams pz_act_click
#' @param target A CSS selector string, a [pz_loc()] spec, or a list of
#'   specs and strings (a union matching any of them). `NULL` means the
#'   current context: the pinned set at a scoped context (so
#'   [pz_expect_exists()] on one trivially passes while the scope is
#'   live), the page body at the root.
#' @param not Invert the check.
#' @param timeout Seconds to wait for the expectation to pass; `NULL`
#'   (default) uses the session default, `0` checks once.
#'
#' @return `ctx`, invisibly.
#' @examplesIf paparazzi:::examples_run()
#' page <- pz_open(pz_example("tasks"))
#' page |> pz_expect_exists(target = ".task")
#'
#' # The help panel is in the page even while it's hidden
#' page |> pz_expect_exists(target = "#help")
#' page |> pz_expect_exists(target = ".error-message", not = TRUE)
#'
#' # A failing expectation retries until the timeout, then errors
#' try(pz_expect_exists(page, target = ".error-message", timeout = 0.5))
#' pz_close(page)
#'
#' @export
pz_expect_exists <- function(
  ctx,
  target = NULL,
  ...,
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
    description = if (not) {
      "Expected no element to match"
    } else {
      "Expected an element to match"
    }
  )
}

#' Expect a number of matching elements
#'
#' @description
#' [pz_expect_count()] passes when the number of elements matching
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
#' @inheritParams pz_expect_exists
#' @param n Exact expected count. Exclusive with `min` and `max`.
#'   `NULL` disables the exact-count check; supply `min` or `max`.
#' @param min Minimum count; with `max`, an inclusive range check.
#'   `NULL` omits the lower bound.
#' @param max Maximum count; with `min`, an inclusive range check.
#'   `NULL` omits the upper bound.
#'
#' @return `ctx`, invisibly.
#' @examplesIf paparazzi:::examples_run()
#' page <- pz_open(pz_example("tasks"))
#' page |> pz_expect_count(7, target = ".task")
#' page |> pz_expect_count(min = 1, max = 2, target = ".task.done")
#'
#' # Expectations retry, so they wait for the page to catch up: the new task
#' # appears after a short "Saving..." delay
#' page |>
#'   pz_act_type("Buy milk", target = "#task-title") |>
#'   pz_act_click("#add-task") |>
#'   pz_expect_count(8, target = ".task")
#' pz_close(page)
#'
#' @export
pz_expect_count <- function(
  ctx,
  n = NULL,
  target = NULL,
  ...,
  min = NULL,
  max = NULL,
  not = FALSE,
  timeout = NULL
) {
  check_dots_empty()
  if (!is.null(n)) {
    if (!is.null(min) || !is.null(max)) {
      cli::cli_abort(
        "Can't combine {.arg n} with {.arg min} or {.arg max}; {.arg n} is exact, so specify one or the other.",
        class = "paparazzi_error_input"
      )
    }
    check_number_whole(n, min = 0)
    min <- n
    max <- n
  } else {
    if (is.null(min) && is.null(max)) {
      cli::cli_abort(
        "Specify {.arg n} for an exact count, or {.arg min} and/or {.arg max} for a range.",
        class = "paparazzi_error_input"
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
        class = "paparazzi_error_input"
      )
    }
  }
  expect_impl(
    ctx = ctx,
    target = target,
    not = not,
    timeout = timeout,
    check = check_count(min, max, not),
    description = expect_headline_count(n, min, max, not)
  )
}

#' Expect elements to be visible
#'
#' @description
#' [pz_expect_visible()] passes when at least one element matches and
#' every match is visible. [pz_expect_hidden()] is exactly
#' `pz_expect_visible(not = TRUE)`: it passes when no match is visible,
#' including when nothing matches.
#'
#' Visibility follows the browser's own `checkVisibility()`
#' (<https://developer.mozilla.org/en-US/docs/Web/API/Element/checkVisibility>)
#' with CSS checks, so `display: none` and `visibility: hidden` anywhere
#' up the ancestor chain count as hidden. Opacity and viewport position
#' are not considered; use [pz_expect_in_viewport()] for position.
#'
#' Outside of testthat, a failure aborts with a classed error of class
#' `"paparazzi_expectation_failure"`; inside testthat, the failure is
#' reported as a test failure instead. See [pz_expect_exists()] for the
#' retry, timeout, and bridge behavior shared by all expectations.
#'
#' @inheritParams pz_expect_exists
#'
#' @return `ctx`, invisibly.
#' @examplesIf paparazzi:::examples_run()
#' page <- pz_open(pz_example("tasks"))
#' page |> pz_expect_hidden(target = "#help")
#'
#' page |>
#'   pz_act_click("#toggle-help") |>
#'   pz_expect_visible(target = "#help")
#'
#' # Every match must pass, so check one task or narrow the target
#' page |> pz_expect_visible(target = pz_loc(".task", has_text = "passport"))
#' pz_close(page)
#'
#' @export
pz_expect_visible <- function(
  ctx,
  target = NULL,
  ...,
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
    description = if (not) {
      "Expected no element to be visible"
    } else {
      "Expected all elements to be visible"
    }
  )
}

#' @rdname pz_expect_visible
#' @export
pz_expect_hidden <- function(
  ctx,
  target = NULL,
  ...,
  not = FALSE,
  timeout = NULL
) {
  check_bool(not)
  pz_expect_visible(ctx, ..., target = target, not = !not, timeout = timeout)
}

#' Expect element text content
#'
#' @description
#' [pz_expect_text()] passes when at least one element matches and the
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
#' @inheritParams pz_act_click
#' @param text A character vector of expected text: length 1 applies to
#'   every match, length `n` is compared pairwise in order.
#' @param match How to compare `text`: `"contains"` (substring),
#'   `"exact"`, or `"regex"` (an R regex matched with [grepl()]).
#' @inheritParams pz_expect_exists
#' @param target A CSS selector string, a [pz_loc()] spec, or a list of
#'   specs and strings (a union matching any of them). `NULL` means the
#'   current context: the pinned set at a scoped context, or the page
#'   body at the root, so `pz_expect_text(page, "Welcome")` checks the
#'   page text.
#'
#' @return `ctx`, invisibly.
#' @examplesIf paparazzi:::examples_run()
#' page <- pz_open(pz_example("tasks"))
#' page |> pz_expect_text("Tasks", target = "h1", match = "exact")
#' page |> pz_expect_text("passport", target = pz_loc(".task", which = "first"))
#'
#' # A vector compares pairwise with the matches, in order
#' page |> pz_expect_text(c("All", "Open", "Done"), target = ".filters a")
#'
#' # Regular expressions use R's syntax
#' page |> pz_expect_text("^[A-Z]", target = ".task-title", match = "regex")
#'
#' # On failure, the error shows the target and the last text seen
#' try(pz_expect_text(page, "otters", target = "h1", timeout = 0.5))
#' pz_close(page)
#'
#' @export
pz_expect_text <- function(
  ctx,
  text,
  target = NULL,
  ...,
  match = c("contains", "exact", "regex"),
  not = FALSE,
  timeout = NULL
) {
  check_dots_empty()
  check_character(text)
  match <- arg_match(match)
  expect_impl(
    ctx = ctx,
    target = target,
    not = not,
    timeout = timeout,
    check = check_text(collapse_ws(text), match, not),
    description = expect_headline_text(text, match, not)
  )
}

#' Expect elements to be enabled
#'
#' @description
#' [pz_expect_enabled()] passes when at least one element matches and
#' every match is enabled. An element counts as disabled when it matches
#' the browser's `:disabled` selector, so inputs inside a disabled
#' `<fieldset>` are disabled too.
#'
#' Outside of testthat, a failure aborts with a classed error of class
#' `"paparazzi_expectation_failure"`; inside testthat, the failure is
#' reported as a test failure instead. See [pz_expect_exists()] for the
#' retry, timeout, and bridge behavior shared by all expectations.
#'
#' @inheritParams pz_expect_exists
#'
#' @return `ctx`, invisibly.
#' @examplesIf paparazzi:::examples_run()
#' page <- pz_open(pz_example("tasks"))
#'
#' # Add is disabled until the title has text
#' page |> pz_expect_enabled(target = "#add-task", not = TRUE)
#' page |>
#'   pz_act_type("Buy milk", target = "#task-title") |>
#'   pz_expect_enabled(target = "#add-task")
#' pz_close(page)
#'
#' @export
pz_expect_enabled <- function(
  ctx,
  target = NULL,
  ...,
  not = FALSE,
  timeout = NULL
) {
  check_dots_empty()
  expect_impl(
    ctx = ctx,
    target = target,
    not = not,
    timeout = timeout,
    check = check_state(expect_enabled_js, not, "enabled"),
    description = if (not) {
      "Expected no element to be enabled"
    } else {
      "Expected all elements to be enabled"
    }
  )
}

#' Expect elements to be focused
#'
#' @description
#' [pz_expect_focused()] passes when at least one element matches and
#' every match is the page's focused element (`document.activeElement`).
#' Focus it with [pz_act_focus()] or a [pz_act_click()], and remove it with
#' [pz_act_blur()].
#'
#' Outside of testthat, a failure aborts with a classed error of class
#' `"paparazzi_expectation_failure"`; inside testthat, the failure is
#' reported as a test failure instead. See [pz_expect_exists()] for the
#' retry, timeout, and bridge behavior shared by all expectations.
#'
#' @inheritParams pz_expect_exists
#'
#' @return `ctx`, invisibly.
#' @examplesIf paparazzi:::examples_run()
#' page <- pz_open(pz_example("tasks"))
#' page |>
#'   pz_act_click("#task-title") |>
#'   pz_expect_focused(target = "#task-title")
#'
#' page |>
#'   pz_act_press("Tab") |>
#'   pz_expect_focused(target = "#task-priority")
#' pz_close(page)
#'
#' @export
pz_expect_focused <- function(
  ctx,
  target = NULL,
  ...,
  not = FALSE,
  timeout = NULL
) {
  check_dots_empty()
  expect_impl(
    ctx = ctx,
    target = target,
    not = not,
    timeout = timeout,
    check = check_state(expect_focused_js, not, "focused"),
    description = if (not) {
      "Expected no element to be focused"
    } else {
      "Expected all elements to be focused"
    }
  )
}

#' Expect elements to be checked
#'
#' @description
#' [pz_expect_checked()] passes when at least one element matches and
#' every match is checked (the browser's `:checked` selector, so
#' checkboxes, radios, and select options all count). Toggle with
#' [pz_act_click()] or `pz_set_value()`.
#'
#' Outside of testthat, a failure aborts with a classed error of class
#' `"paparazzi_expectation_failure"`; inside testthat, the failure is
#' reported as a test failure instead. See [pz_expect_exists()] for the
#' retry, timeout, and bridge behavior shared by all expectations.
#'
#' @inheritParams pz_expect_exists
#'
#' @return `ctx`, invisibly.
#' @examplesIf paparazzi:::examples_run()
#' page <- pz_open(pz_example("tasks"))
#' page |> pz_expect_checked(target = "#task-urgent", not = TRUE)
#' page |>
#'   pz_act_click("#task-urgent") |>
#'   pz_expect_checked(target = "#task-urgent")
#' pz_close(page)
#'
#' @export
pz_expect_checked <- function(
  ctx,
  target = NULL,
  ...,
  not = FALSE,
  timeout = NULL
) {
  check_dots_empty()
  expect_impl(
    ctx = ctx,
    target = target,
    not = not,
    timeout = timeout,
    check = check_state(expect_checked_js, not, "checked"),
    description = if (not) {
      "Expected no element to be checked"
    } else {
      "Expected all elements to be checked"
    }
  )
}

#' Expect elements to be in the viewport
#'
#' @description
#' [pz_expect_in_viewport()] passes when at least one element matches
#' and every match overlaps the viewport: its bounding box crosses the
#' visible area by any amount. Elements entirely above, below, or beside
#' the fold fail; visibility itself is a separate expectation,
#' [pz_expect_visible()].
#'
#' Outside of testthat, a failure aborts with a classed error of class
#' `"paparazzi_expectation_failure"`; inside testthat, the failure is
#' reported as a test failure instead. See [pz_expect_exists()] for the
#' retry, timeout, and bridge behavior shared by all expectations.
#'
#' @inheritParams pz_expect_exists
#'
#' @return `ctx`, invisibly.
#' @examplesIf paparazzi:::examples_run()
#' page <- pz_open(pz_example("tasks"), height = 500)
#'
#' # The last task is inside the scrolling list, below its visible area
#' last_task <- pz_loc(".task", which = "last")
#' page |> pz_expect_in_viewport(target = last_task, not = TRUE)
#' page |>
#'   pz_act_scroll(last_task) |>
#'   pz_expect_in_viewport(target = last_task)
#' pz_close(page)
#'
#' @export
pz_expect_in_viewport <- function(
  ctx,
  target = NULL,
  ...,
  not = FALSE,
  timeout = NULL
) {
  check_dots_empty()
  expect_impl(
    ctx = ctx,
    target = target,
    not = not,
    timeout = timeout,
    check = check_state(expect_viewport_js, not, "in viewport"),
    description = if (not) {
      "Expected no element to be in the viewport"
    } else {
      "Expected all elements to be in the viewport"
    }
  )
}

#' Expect element values
#'
#' @description
#' [pz_expect_value()] passes when at least one element matches and the
#' `value` property of every match satisfies `value`. Elements without a
#' value property (paragraphs, divs) read as missing and satisfy no
#' `value`. Checkbox and radio values come from their `value` attribute
#' (the default is `"on"`), whatever their checked state.
#'
#' A length-1 `value` applies to every match. A length-`n` `value`
#' requires exactly `n` matches and compares pairwise, in order. With
#' `not = TRUE`, the expectation passes when no match satisfies `value`,
#' including when nothing matches.
#'
#' Outside of testthat, a failure aborts with a classed error of class
#' `"paparazzi_expectation_failure"`; inside testthat, the failure is
#' reported as a test failure instead. See [pz_expect_exists()] for the
#' retry, timeout, and bridge behavior shared by all expectations.
#'
#' @inheritParams pz_expect_text
#' @param value A character vector of expected values: length 1 applies
#'   to every match, length `n` is compared pairwise in order.
#'
#' @return `ctx`, invisibly.
#' @examplesIf paparazzi:::examples_run()
#' page <- pz_open(pz_example("tasks"))
#' page |> pz_expect_value("normal", target = "#task-priority", match = "exact")
#'
#' page |>
#'   pz_act_type("Buy milk", target = "#task-title") |>
#'   pz_expect_value("milk", target = "#task-title")
#' pz_close(page)
#'
#' @export
pz_expect_value <- function(
  ctx,
  value,
  target = NULL,
  ...,
  match = c("contains", "exact", "regex"),
  not = FALSE,
  timeout = NULL
) {
  check_dots_empty()
  check_character(value)
  match <- arg_match(match)
  expect_impl(
    ctx = ctx,
    target = target,
    not = not,
    timeout = timeout,
    check = check_text_like(get_value_js, collapse_ws(value), match, not),
    description = expect_headline_text(value, match, not, label = "value")
  )
}

#' Expect attributes
#'
#' @description
#' [pz_expect_attr()] passes when at least one element matches and every
#' matched element satisfies every named attribute/value pair in `...`.
#' Missing attributes satisfy no pair. Comparisons are exact by default;
#' `.match = "contains"` or `"regex"` applies to all pairs in the call.
#'
#' A length-1 value applies to every element. A vector requires exactly
#' that many matches and compares pairwise, in order. With `.not = TRUE`,
#' the expectation passes when the combined condition does not hold,
#' including when no element matches.
#'
#' Outside of testthat, a failure aborts with a classed error of class
#' `"paparazzi_expectation_failure"`; inside testthat, the failure is
#' reported as a test failure. See [pz_expect_exists()] for the
#' retry, timeout, and bridge behavior shared by all expectations.
#'
#' @param ctx A paparazzi context.
#' @param .target A CSS selector string, a [pz_loc()] spec, or a list of
#'   either. `NULL` selects the current context.
#' @param ... Named attribute/value pairs. Values are character vectors;
#'   use backticks for names such as `aria-expanded`. Dynamic dots support
#'   splicing a named list with `!!!`.
#' @param .match Comparison mode for all pairs: `"exact"` (default),
#'   `"contains"`, or `"regex"`.
#' @param .not Invert the combined expectation?
#' @param .timeout Seconds to wait; `NULL` uses the session default.
#'
#' @return `ctx`, invisibly.
#' @examplesIf paparazzi:::examples_run()
#' page <- pz_open(pz_example("tasks"))
#' page |> pz_expect_attr(
#'   pz_loc(".task", has_text = "tax"), `data-priority` = "high"
#' )
#'
#' page |>
#'   pz_act_click("#toggle-help") |>
#'   pz_expect_attr("#toggle-help", `aria-expanded` = "true")
#' pz_close(page)
#'
#' @export
pz_expect_attr <- function(
  ctx,
  .target = NULL,
  ...,
  .match = c("exact", "contains", "regex"),
  .not = FALSE,
  .timeout = NULL
) {
  pairs <- expect_attr_pairs(list2(...), call = environment())
  .match <- arg_match(.match)
  expect_impl(
    ctx = ctx,
    target = .target,
    not = .not,
    timeout = .timeout,
    check = check_attr_pairs(pairs, .match, .not),
    description = expect_headline_attrs(pairs, .match, .not)
  )
}

#' Expect a class
#'
#' @description
#' [pz_expect_class()] passes when at least one element matches and every
#' match carries `class`. With `not = TRUE` it passes when no match does,
#' including when nothing matches. `class` is one class name, not a
#' space-separated list: expect each class with its own call.
#'
#' Outside of testthat, a failure aborts with a classed error of class
#' `"paparazzi_expectation_failure"`; inside testthat, the failure is
#' reported as a test failure instead. See [pz_expect_exists()] for the
#' retry, timeout, and bridge behavior shared by all expectations.
#'
#' @inheritParams pz_expect_exists
#' @param class A single class name to expect on every match.
#'
#' @return `ctx`, invisibly.
#' @examplesIf paparazzi:::examples_run()
#' page <- pz_open(pz_example("tasks"))
#' water <- pz_loc(".task", has_text = "Water")
#' page |> pz_expect_class("done", target = water, not = TRUE)
#'
#' page |>
#'   pz_find(water) |>
#'   pz_act_click(".task-done") |>
#'   pz_expect_class("done")
#' pz_close(page)
#'
#' @export
pz_expect_class <- function(
  ctx,
  class,
  target = NULL,
  ...,
  not = FALSE,
  timeout = NULL
) {
  check_dots_empty()
  check_string(class)
  if (grepl("\\s", class)) {
    cli::cli_abort(
      c(
        "{.arg class} must be a single class name, not {.str {class}}.",
        i = "Expect each class with its own {.fn pz_expect_class} call."
      ),
      class = "paparazzi_error_input"
    )
  }
  expect_impl(
    ctx = ctx,
    target = target,
    not = not,
    timeout = timeout,
    check = check_state(
      expect_class_js(class),
      not,
      paste0("with class \"", class, "\"")
    ),
    description = if (not) {
      paste0("Expected no element to have class \"", class, "\"")
    } else {
      paste0("Expected all elements to have class \"", class, "\"")
    }
  )
}

#' Expect a JavaScript predicate to hold
#'
#' @description
#' [pz_expect_js()] passes when at least one element matches and the
#' predicate holds for every match: `expr` is evaluated as a function
#' receiving the element, e.g. `"el => el.scrollTop > 0"`. It's the
#' escape hatch for conditions the catalog doesn't cover. A predicate
#' that throws is a JavaScript error, not a failed check.
#'
#' Outside of testthat, a failure aborts with a classed error of class
#' `"paparazzi_expectation_failure"`; inside testthat, the failure is
#' reported as a test failure instead. See [pz_expect_exists()] for the
#' retry, timeout, and bridge behavior shared by all expectations.
#'
#' @inheritParams pz_expect_exists
#' @param expr A JavaScript function receiving the element, as a string,
#'   e.g. `"el => el.scrollTop > 0"`.
#'
#' @return `ctx`, invisibly.
#' @examplesIf paparazzi:::examples_run()
#' page <- pz_open(pz_example("tasks"))
#'
#' # The predicate receives each matching element
#' page |> pz_expect_js("el => el.scrollHeight > el.clientHeight", target = ".task-list")
#' page |> pz_expect_js("el => el.draggable", target = ".task")
#' pz_close(page)
#'
#' @export
pz_expect_js <- function(
  ctx,
  expr,
  target = NULL,
  ...,
  not = FALSE,
  timeout = NULL
) {
  check_dots_empty()
  check_string(expr)
  expect_impl(
    ctx = ctx,
    target = target,
    not = not,
    timeout = timeout,
    check = check_state(expect_js_predicate(expr), not, "satisfied"),
    description = expect_headline_js(expr, not)
  )
}

#' Expect the page URL
#'
#' @description
#' [pz_expect_url()] passes when the page's URL satisfies `url`. It works
#' from any context, scoped or root: the URL belongs to the page, not to
#' an element.
#'
#' Outside of testthat, a failure aborts with a classed error of class
#' `"paparazzi_expectation_failure"`; inside testthat, the failure is
#' reported as a test failure instead. See [pz_expect_exists()] for the
#' retry, timeout, and bridge behavior shared by all expectations.
#'
#' @inheritParams pz_act_click
#' @param url The expected URL, a single string.
#' @param match How to compare `url`: `"contains"` (substring),
#'   `"exact"`, or `"regex"` (an R regex matched with [grepl()]).
#' @param not Invert the check.
#' @param timeout Seconds to wait for the expectation to pass; `NULL`
#'   (default) uses the session default, `0` checks once.
#'
#' @return `ctx`, invisibly.
#' @examplesIf paparazzi:::examples_run()
#' page <- pz_open(pz_example("tasks"))
#' page |> pz_expect_url("tasks.html")
#'
#' page |>
#'   pz_act_click(pz_loc(".filters a", has_text = "Done")) |>
#'   pz_expect_url("#done$", match = "regex")
#' pz_close(page)
#'
#' @export
pz_expect_url <- function(
  ctx,
  url,
  ...,
  match = c("contains", "exact", "regex"),
  not = FALSE,
  timeout = NULL
) {
  check_dots_empty()
  check_string(url)
  match <- arg_match(match)
  expect_page_impl(
    ctx = ctx,
    values = url,
    match = match,
    not = not,
    timeout = timeout,
    read = function() pz_js(ctx, "location.href"),
    description = expect_headline_text(url, match, not, label = "URL")
  )
}

#' Expect the page title
#'
#' @description
#' [pz_expect_title()] passes when the page's `<title>` satisfies
#' `title`. It works from any context, scoped or root: the title belongs
#' to the page, not to an element.
#'
#' Outside of testthat, a failure aborts with a classed error of class
#' `"paparazzi_expectation_failure"`; inside testthat, the failure is
#' reported as a test failure instead. See [pz_expect_exists()] for the
#' retry, timeout, and bridge behavior shared by all expectations.
#'
#' @inheritParams pz_expect_url
#' @param title The expected page title, a single string.
#'
#' @return `ctx`, invisibly.
#' @examplesIf paparazzi:::examples_run()
#' page <- pz_open(pz_example("tasks"))
#' page |> pz_expect_title("Tasks", match = "exact")
#' pz_close(page)
#'
#' @export
pz_expect_title <- function(
  ctx,
  title,
  ...,
  match = c("contains", "exact", "regex"),
  not = FALSE,
  timeout = NULL
) {
  check_dots_empty()
  check_string(title)
  match <- arg_match(match)
  expect_page_impl(
    ctx = ctx,
    values = title,
    match = match,
    not = not,
    timeout = timeout,
    read = function() pz_js(ctx, "document.title"),
    description = expect_headline_text(title, match, not, label = "title")
  )
}

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

  target_expr <- target_resolver_expr(target, call = call)
  expr <- target_expr$fn
  target_desc <- target_expr$description

  scoped <- scope_top(ctx)

  start <- Sys.time()
  if (is.null(target) && !is.null(scoped)) {
    target_desc <- scoped$description
    result <- expect_retry(
      fn = function() check(scope_root(ctx, call = call)),
      timeout = timeout,
      loop = ctx$page$child_loop
    )
  } else {
    result <- expect_retry(
      fn = function() {
        els <- loc_resolve_once(
          ctx,
          expr,
          target_desc,
          call,
          root = scope_root(ctx, call = call)
        )
        withr::defer(release_elements(els))
        check(els)
      },
      timeout = timeout,
      loop = ctx$page$child_loop
    )
  }
  waited <- round(as.numeric(difftime(Sys.time(), start, units = "secs")), 1)
  expect_report(ctx, result, description, target_desc, waited, call = call)
}

# The failure text carries page-derived content (observed) and
# user-derived content (the headline holds the expected text, which may
# be a regex containing braces). Both are interpolated as cli VALUES,
# never pasted into templates: cli only evaluates the template, so
# braces inside a value stay literal and can't inject markup or code.
expect_report <- function(
  ctx,
  result,
  description,
  target,
  waited,
  call = caller_env()
) {
  headline <- description
  observed <- result$observed
  msg_template <- c(
    "{headline}",
    "Target: {target}",
    "Last seen: {observed}",
    "Waited {waited}s."
  )
  msg <- cli::format_message(msg_template)
  if (isTRUE(result$pass)) {
    expect_bridge(TRUE, msg)
    return(ctx_return(ctx))
  }
  if (expect_bridge(FALSE, msg)) {
    return(ctx_return(ctx))
  }
  cli::cli_abort(
    msg_template,
    class = "paparazzi_expectation_failure",
    call = call
  )
}

expect_page_impl <- function(
  ctx,
  values,
  match,
  not,
  timeout,
  read,
  description,
  call = caller_env()
) {
  check_bool(not, call = call)
  check_context(ctx, call = call)
  timeout <- resolve_timeout(timeout, ctx$page, call = call)
  expected <- collapse_ws(values)
  start <- Sys.time()
  result <- expect_retry(
    fn = function() {
      observed <- read()
      hit <- expect_text_hit(collapse_ws(observed), expected, match)
      list(pass = if (not) !hit else hit, observed = paste0('"', observed, '"'))
    },
    timeout = timeout,
    loop = ctx$page$child_loop
  )
  waited <- round(as.numeric(difftime(Sys.time(), start, units = "secs")), 1)
  expect_report(ctx, result, description, "the page", waited, call = call)
}

expect_bridge <- function(ok, msg) {
  if (
    !requireNamespace("testthat", quietly = TRUE) || !testthat::is_testing()
  ) {
    return(FALSE)
  }
  testthat::expect(ok, paste(msg, collapse = "\n"))
  TRUE
}

els_values <- function(
  els,
  js,
  args = NULL,
  doing = "reading",
  call = caller_env()
) {
  timeout <- els$page$default_timeout
  doing <- paste(doing, "elements matching", els$description)
  res <- cdp_call(
    els$page$session$Runtime$callFunctionOn(
      js,
      objectId = els$object_id,
      arguments = args,
      returnByValue = TRUE,
      timeout_ = timeout
    ),
    timeout,
    doing,
    call = call
  )
  cdp_check_exception(res, doing, call = call)
  res$result$value
}

els_call <- function(els, js, call = caller_env()) {
  unlist(els_values(els, js, call = call))
}

collapse_ws <- function(x) {
  trimws(gsub("\\s+", " ", x))
}

expect_visible_js <- "function() {
  return this.map((el) => el.checkVisibility({ checkVisibilityCSS: true }));
}"

expect_enabled_js <- "function() {
  return this.map((el) => !el.matches(':disabled'));
}"

expect_focused_js <- "function() {
  return this.map((el) => document.activeElement === el);
}"

expect_checked_js <- "function() {
  return this.map((el) => el.matches(':checked'));
}"

expect_viewport_js <- "function() {
  return this.map((el) => {
    const r = el.getBoundingClientRect();
    return r.bottom > 0 && r.right > 0 &&
      r.top < window.innerHeight && r.left < window.innerWidth;
  });
}"

expect_text_js <- "function() {
  return this.map((el) => el.textContent);
}"

expect_attrs_js <- function(names) {
  paste0(
    "function() { const names = ",
    jsonlite::toJSON(names, auto_unbox = FALSE),
    "; return this.map((el) => names.map((name) => el.getAttribute(name))); }"
  )
}

expect_class_js <- function(class) {
  paste0(
    "function() { return this.map((el) => el.classList.contains(",
    jsonlite::toJSON(class, auto_unbox = TRUE),
    ")); }"
  )
}

expect_js_predicate <- function(expr) {
  paste0(
    "function() {\n",
    "  const predicate = ",
    expr,
    ";\n",
    "  return this.map((el) => !!predicate(el));\n",
    "}"
  )
}

expect_seen_count <- function(count) {
  paste0(count, if (count == 1L) " match" else " matches")
}

expect_seen_texts <- function(texts) {
  texts <- ifelse(is.na(texts), "NA", texts)
  expect_truncate(paste0('"', texts, '"', collapse = ", "))
}

expect_truncate <- function(x, width = 80) {
  if (nchar(x) > width) {
    paste0(substr(x, 1, width - 3), "...")
  } else {
    x
  }
}

check_exists <- function(not) {
  function(els) {
    pass <- if (not) els$count == 0L else els$count >= 1L
    list(pass = pass, observed = expect_seen_count(els$count))
  }
}

check_count <- function(min, max, not) {
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

check_state <- function(js, not, seen) {
  function(els) {
    if (els$count == 0L) {
      return(list(pass = not, observed = expect_seen_count(0L)))
    }
    n_ok <- sum(els_call(els, js))
    pass <- if (not) n_ok == 0L else n_ok == els$count
    list(pass = pass, observed = paste0(n_ok, " of ", els$count, " ", seen))
  }
}

check_visible <- function(not) {
  check_state(expect_visible_js, not, "visible")
}

check_text_like <- function(js, values, match, not) {
  function(els) {
    if (els$count == 0L) {
      return(list(pass = not, observed = expect_seen_count(0L)))
    }
    vals <- collapse_ws(chr_or_na(els_values(els, js)))
    if (length(values) == 1L) {
      hits <- map_lgl(
        vals,
        expect_text_hit,
        pattern = values,
        match = match
      )
      pass <- if (not) !any(hits) else all(hits)
    } else {
      hits <- if (els$count == length(values)) {
        vapply(
          seq_along(values),
          function(i) expect_text_hit(vals[[i]], values[[i]], match),
          logical(1)
        )
      } else {
        FALSE
      }
      pass <- if (not) !any(hits) else all(hits)
    }
    list(pass = pass, observed = expect_seen_texts(vals))
  }
}

check_text <- function(text, match, not) {
  check_text_like(expect_text_js, text, match, not)
}

expect_attr_pairs <- function(dots, call = caller_env()) {
  nms <- names(dots)
  if (length(dots) == 0L || is.null(nms) || !all(nzchar(nms))) {
    cli::cli_abort(
      "Provide at least one named attribute/value pair in {.arg ...}.",
      class = "paparazzi_error_input",
      call = call
    )
  }
  if (anyDuplicated(nms)) {
    cli::cli_abort(
      "Attribute names in {.arg ...} must be unique.",
      class = "paparazzi_error_input",
      call = call
    )
  }
  imap(dots, function(value, nm) {
    check_character(value, arg = nm, call = call)
    collapse_ws(value)
  })
}

check_attr_pairs <- function(pairs, match, not) {
  js <- expect_attrs_js(names(pairs))
  function(els) {
    if (els$count == 0L) {
      return(list(pass = not, observed = expect_seen_count(0L)))
    }
    vals <- lapply(els_values(els, js), chr_or_na)
    hits <- matrix(FALSE, nrow = els$count, ncol = length(pairs))
    observed <- character(length(pairs))
    for (p in seq_along(pairs)) {
      actual <- collapse_ws(map_chr(vals, `[[`, p))
      expected <- pairs[[p]]
      if (length(expected) == 1L || length(expected) == els$count) {
        hits[, p] <- vapply(
          seq_along(actual),
          function(i) {
            expect_text_hit(
              actual[[i]],
              expected[[if (length(expected) == 1L) 1L else i]],
              match
            )
          },
          logical(1)
        )
      }
      observed[[p]] <- expect_seen_texts(actual)
    }
    seen <- if (length(pairs) == 1L) {
      observed[[1]]
    } else {
      expect_truncate(paste0(names(pairs), ": ", observed, collapse = "; "))
    }
    list(pass = if (not) !all(hits) else all(hits), observed = seen)
  }
}

expect_headline_attrs <- function(pairs, match, not) {
  if (length(pairs) == 1L) {
    name <- names(pairs)[[1]]
    return(expect_headline_text(
      pairs[[1]],
      match,
      not,
      label = paste0("attribute \"", name, "\""),
      plural = paste0("attributes \"", name, "\"")
    ))
  }
  what <- vapply(
    seq_along(pairs),
    function(i) {
      paste0(names(pairs)[[i]], " = ", expect_seen_texts(pairs[[i]]))
    },
    character(1)
  )
  paste0(
    "Expected attributes",
    if (not) " not",
    " to match ",
    paste(what, collapse = "; ")
  )
}

expect_text_matches <- function(x, pattern, match) {
  switch(
    match,
    contains = grepl(pattern, x, fixed = TRUE),
    exact = identical(x, pattern),
    regex = grepl(pattern, x)
  )
}

expect_text_hit <- function(x, pattern, match) {
  isTRUE(expect_text_matches(x, pattern, match))
}

expect_headline_js <- function(expr, not) {
  paste0(
    "Expected JS predicate (",
    expect_truncate(expr, width = 60),
    ") to hold for ",
    if (not) "no match" else "every match"
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

expect_headline_text <- function(
  text,
  match,
  not,
  label = "text",
  plural = paste0(label, "s")
) {
  what <- switch(
    match,
    contains = paste0('"', text, '"', collapse = ", "),
    exact = paste0('"', text, '"', collapse = ", "),
    regex = paste0("/", text, "/", collapse = ", ")
  )
  verb <- switch(match, contains = "contain", exact = "be", regex = "match")
  label <- if (length(text) == 1L) label else plural
  paste0("Expected ", label, if (not) " not", " to ", verb, " ", what)
}
