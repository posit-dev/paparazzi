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
#'   pz_act_type("Buy milk", target = "#task_title") |>
#'   pz_act_click("#add_task") |>
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
#'   pz_act_click("#toggle_help") |>
#'   pz_expect_visible(target = "#help")
#'
#' # Every match must pass, so check one task or narrow the target
#' page |>
#'   pz_expect_visible(target = pz_loc(".task", match = pz_regex("passport")))
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
#' [pz_expect_text()] passes when at least one element matches and the text of
#' every match satisfies `text`. Whitespace collapses on both sides before
#' comparing, so `"Save   now"` matches text reading "Save now".
#'
#' A length-1 `text` applies to every match. A length-`n` `text` requires
#' exactly `n` matches and compares pairwise, in order. With `not = TRUE`, the
#' expectation passes when no match satisfies `text`, including when nothing
#' matches.
#'
#' A string checks the complete text, with the same capitalization. Pass
#' [pz_regex()] to check a pattern instead: `pz_regex("^Save")` checks whether
#' the text begins with "Save". For a literal substring, use `pz_regex("Save
#' (draft)", fixed = TRUE)`; the parentheses then match themselves rather than
#' having their regex meanings.
#'
#' The same regex checks every selected element. paparazzi collapses and trims
#' whitespace in the text without changing your regex pattern. Missing text
#' never matches, even with an empty pattern. See [pz_regex()] for pattern
#' syntax and options.
#'
#' Outside of testthat, a failure aborts with a classed error of class
#' `"paparazzi_expectation_failure"`; inside testthat, the failure is reported
#' as a test failure instead. See [pz_expect_exists()] for the retry, timeout,
#' and bridge behavior shared by all expectations.
#'
#' @inheritParams pz_act_click
#' @param text A character vector of expected text: length 1 applies to every
#'   match, length `n` is compared pairwise in order. Or a single [pz_regex()]
#'   value to check the same pattern against every element.
#' @inheritParams pz_expect_exists
#' @param target A CSS selector string, a [pz_loc()] spec, or a list of specs
#'   and strings (a union matching any of them). `NULL` means the current
#'   context: the pinned set at a scoped context, or the page body at the root,
#'   so `pz_expect_text(page, "Welcome")` checks the page text.
#'
#' @return `ctx`, invisibly.
#' @examplesIf paparazzi:::examples_run()
#' page <- pz_open(pz_example("tasks"))
#' page |> pz_expect_text("Tasks", target = "h1")
#'
#' # Substring matching uses pz_regex() with fixed = TRUE
#' page |>
#'   pz_expect_text(
#'     pz_regex("passport", fixed = TRUE),
#'     target = pz_loc(".task", which = "first")
#'   )
#'
#' # A vector compares pairwise with the matches, in order
#' page |> pz_expect_text(c("All", "Open", "Done"), target = ".filters a")
#'
#' # Regular expressions use the browser's JavaScript dialect
#' page |> pz_expect_text(pz_regex("^[A-Z]"), target = ".task-title")
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
  not = FALSE,
  timeout = NULL
) {
  check_dots_empty()
  if (!is_regex(text)) {
    check_character(text)
  }
  expect_impl(
    ctx = ctx,
    target = target,
    not = not,
    timeout = timeout,
    check = check_text(text, not),
    description = expect_headline_text(text, not)
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
#' page |> pz_expect_enabled(target = "#add_task", not = TRUE)
#' page |>
#'   pz_act_type("Buy milk", target = "#task_title") |>
#'   pz_expect_enabled(target = "#add_task")
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
#'   pz_act_click("#task_title") |>
#'   pz_expect_focused(target = "#task_title")
#'
#' page |>
#'   pz_act_press("Tab") |>
#'   pz_expect_focused(target = "#task_priority")
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
#' page |> pz_expect_checked(target = "#task_urgent", not = TRUE)
#' page |>
#'   pz_act_click("#task_urgent") |>
#'   pz_expect_checked(target = "#task_urgent")
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
#' A string checks the complete value; [pz_regex()] checks a pattern.
#' Whitespace and patterns follow the same rules as [pz_expect_text()].
#' A missing value never matches, not even an empty pattern.
#'
#' Outside of testthat, a failure aborts with a classed error of class
#' `"paparazzi_expectation_failure"`; inside testthat, the failure is
#' reported as a test failure instead. See [pz_expect_exists()] for the
#' retry, timeout, and bridge behavior shared by all expectations.
#'
#' @inheritParams pz_expect_text
#' @param value A character vector of expected values: length 1 applies
#'   to every match, length `n` is compared pairwise in order. Strings
#'   compare by exact equality after whitespace normalization. Or a
#'   single [pz_regex()] value to check the same pattern against every element.
#'
#' @return `ctx`, invisibly.
#' @examplesIf paparazzi:::examples_run()
#' page <- pz_open(pz_example("tasks"))
#' page |> pz_expect_value("normal", target = "#task_priority")
#' page |>
#'   pz_expect_value(pz_regex("^(low|normal|high)$"), target = "#task_priority")
#'
#' page |>
#'   pz_act_type("Buy milk", target = "#task_title") |>
#'   pz_expect_value(pz_regex("milk"), target = "#task_title")
#' pz_close(page)
#'
#' @export
pz_expect_value <- function(
  ctx,
  value,
  target = NULL,
  ...,
  not = FALSE,
  timeout = NULL
) {
  check_dots_empty()
  if (!is_regex(value)) {
    check_character(value)
  }
  expect_impl(
    ctx = ctx,
    target = target,
    not = not,
    timeout = timeout,
    check = check_value(value, not),
    description = expect_headline_text(value, not, label = "value")
  )
}

#' Expect attributes
#'
#' @description
#' [pz_expect_attr()] passes when at least one element matches and every
#' matched element satisfies every named attribute/value pair in `...`.
#' Missing attributes satisfy no pair. String values compare by exact
#' equality after whitespace normalization.
#'
#' Use [pz_regex()] as a pair's value to check a pattern instead of the
#' complete attribute. You can mix strings and regexes in one call.
#' Whitespace and patterns follow the same rules as [pz_expect_text()];
#' a missing attribute never matches, not even an empty pattern.
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
#' @param ... Named attribute/value pairs. Values are character vectors
#'   or single [pz_regex()] values; use backticks for names such as
#'   `aria-expanded`. Dynamic dots support splicing a named list with
#'   `!!!`.
#' @param .not Invert the combined expectation?
#' @param .timeout Seconds to wait; `NULL` uses the session default.
#'
#' @return `ctx`, invisibly.
#' @examplesIf paparazzi:::examples_run()
#' page <- pz_open(pz_example("tasks"))
#' page |> pz_expect_attr(
#'   pz_loc(".task", match = pz_regex("tax")),
#'   `data-priority` = "high"
#' )
#'
#' page |>
#'   pz_act_click("#toggle_help") |>
#'   pz_expect_attr("#toggle_help", `aria-expanded` = "true") |>
#'   pz_expect_attr("#toggle_help", `aria-expanded` = pz_regex("^true$"))
#' pz_close(page)
#'
#' @export
pz_expect_attr <- function(
  ctx,
  .target = NULL,
  ...,
  .not = FALSE,
  .timeout = NULL
) {
  pairs <- expect_attr_pairs(list2(...), call = environment())
  expect_impl(
    ctx = ctx,
    target = .target,
    not = .not,
    timeout = .timeout,
    check = check_attr_pairs(pairs, .not),
    description = expect_headline_attrs(pairs, .not)
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
#' water <- pz_loc(".task", match = pz_regex("Water"))
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
#' @param url The expected complete URL as a single string, or a single
#'   [pz_regex()] pattern. Strings compare exactly after whitespace
#'   normalization. Use `pz_regex(..., fixed = TRUE)` for a literal
#'   substring, so punctuation such as `.` matches itself.
#' @param not Invert the check.
#' @param timeout Seconds to wait for the expectation to pass; `NULL`
#'   (default) uses the session default, `0` checks once.
#'
#' @return `ctx`, invisibly.
#' @examplesIf paparazzi:::examples_run()
#' page <- pz_open(pz_example("tasks"))
#' page |> pz_expect_url(pz_regex("tasks.html", fixed = TRUE))
#'
#' page |>
#'   pz_act_click(pz_loc(".filters a", match = "Done")) |>
#'   pz_expect_url(pz_regex("#done$"))
#' pz_close(page)
#'
#' @export
pz_expect_url <- function(
  ctx,
  url,
  ...,
  not = FALSE,
  timeout = NULL
) {
  check_dots_empty()
  if (!is_regex(url)) {
    check_string(url)
  }
  expect_page_impl(
    ctx = ctx,
    x = url,
    not = not,
    timeout = timeout,
    read = "location.href",
    description = expect_headline_text(url, not, label = "URL")
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
#' @param title The expected complete page title as a single string, or a
#'   single [pz_regex()] pattern. Strings compare exactly after whitespace
#'   normalization.
#'
#' @return `ctx`, invisibly.
#' @examplesIf paparazzi:::examples_run()
#' page <- pz_open(pz_example("tasks"))
#' page |> pz_expect_title("Tasks")
#' page |> pz_expect_title(pz_regex("^tasks$", ignore_case = TRUE))
#' pz_close(page)
#'
#' @export
pz_expect_title <- function(
  ctx,
  title,
  ...,
  not = FALSE,
  timeout = NULL
) {
  check_dots_empty()
  if (!is_regex(title)) {
    check_string(title)
  }
  expect_page_impl(
    ctx = ctx,
    x = title,
    not = not,
    timeout = timeout,
    read = "document.title",
    description = expect_headline_text(title, not, label = "title")
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

  target_expr <- target_resolver(target, call = call)
  expr <- target_expr$fn
  target_desc <- target_expr$description

  scoped <- scope_top(ctx)

  start <- Sys.time()
  if (is.null(target) && !is.null(scoped)) {
    target_desc <- scoped$description
    result <- expect_retry(
      fn = function() check(scope_connected(ctx, call = call)),
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
          root = scope_connected(ctx, call = call)
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
    report_to_testthat(TRUE, msg)
    return(ctx_return(ctx))
  }
  if (report_to_testthat(FALSE, msg)) {
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
  x,
  not,
  timeout,
  read,
  description,
  call = caller_env()
) {
  check_bool(not, call = call)
  check_context(ctx, call = call)
  timeout <- resolve_timeout(timeout, ctx$page, call = call)
  js <- expect_page_js(x, read)
  start <- Sys.time()
  result <- expect_retry(
    fn = function() {
      res <- pz_evaluate(ctx, js)
      hit <- isTRUE(res$hit)
      list(
        pass = if (not) !hit else hit,
        observed = paste0('"', res$value, '"')
      )
    },
    timeout = timeout,
    loop = ctx$page$child_loop
  )
  waited <- round(as.numeric(difftime(Sys.time(), start, units = "secs")), 1)
  expect_report(ctx, result, description, "the page", waited, call = call)
}

report_to_testthat <- function(ok, msg) {
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

els_values_flat <- function(els, js, call = caller_env()) {
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

# Expected values travel as JSON inside the function text (the
# expect_class_js pattern): Chrome receives string and regex specs
# verbatim, and no CDP argument serialization choices apply.
expect_attrs_js <- function(pairs) {
  specs <- vapply(
    pairs,
    function(value) {
      if (is_regex(value)) {
        js_literal(regex_spec_fields(value))
      } else {
        js_literal(list(type = "exact", values = as.list(unname(value))))
      }
    },
    character(1)
  )
  paste0(
    "function() {\n",
    regex_js_helpers,
    "  const names = ",
    js_literal(names(pairs), auto_unbox = FALSE),
    ";\n  const matchers = [",
    paste(specs, collapse = ", "),
    "].map((spec) => {\n",
    "    if (spec.type === 'regex') {\n",
    "      const regex = compileRegex(spec);\n",
    "      return (value) => matchesRegex(value, regex);\n",
    "    }\n",
    "    return (value, i) => {\n",
    "      if (spec.values.length !== 1 && spec.values.length !== this.length) return false;\n",
    "      const expected = spec.values[spec.values.length === 1 ? 0 : i];\n",
    "      return expected !== undefined && matchesExact(value, expected);\n",
    "    };\n",
    "  });\n",
    "  return this.map((el, i) => names.map((name, p) => {\n",
    "    const value = el.getAttribute(name);\n",
    "    return { value: value, hit: matchers[p](value, i) };\n",
    "  }));\n}"
  )
}

expect_class_js <- function(class) {
  paste0(
    "function() { return this.map((el) => el.classList.contains(",
    js_literal(class),
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

# Strings and pz_regex() values share one comparison path: the
# expected values ship as tagged specs, and Chrome collapses, trims and
# matches while raw values come back for diagnostics. A length-1 spec
# list broadcasts over every element; length n compares pairwise.
expect_values_js <- function(values, read) {
  if (is_regex(values)) {
    values <- list(values)
  }
  specs <- lapply(values, function(value) {
    if (is_regex(value)) {
      regex_spec_fields(value)
    } else {
      list(type = "exact", value = value)
    }
  })
  paste0(
    "function() {\n",
    regex_js_helpers,
    "  const matchers = ",
    js_literal(specs),
    ".map((spec) => {\n",
    "    if (spec.type === 'regex') {\n",
    "      const regex = compileRegex(spec);\n",
    "      return (value) => matchesRegex(value, regex);\n",
    "    }\n",
    "    return (value) => matchesExact(value, spec.value);\n",
    "  });\n",
    "  const values = this.map((el) => ",
    read,
    ");\n",
    "  const hits = values.map((value, i) => {\n",
    "    const matcher = matchers[matchers.length === 1 ? 0 : i];\n",
    "    return matcher === undefined ? false : matcher(value);\n",
    "  });\n",
    "  return { values: values, hits: hits };\n}"
  )
}

expect_page_js <- function(x, read) {
  spec <- if (is_regex(x)) {
    js_literal(regex_spec_fields(x))
  } else {
    js_literal(list(type = "exact", value = x))
  }
  paste0(
    "(() => {\n",
    regex_js_helpers,
    "  const spec = ",
    spec,
    ";\n  const value = ",
    read,
    ";\n  const hit = spec.type === 'regex' ?",
    " matchesRegex(value, compileRegex(spec)) : matchesExact(value, spec.value);\n",
    "  return { value: value, hit: hit };\n})()"
  )
}

regex_compile_js <- function(specs) {
  paste0(
    "(() => {\n",
    regex_js_helpers,
    "  [",
    paste(vapply(specs, js_literal, character(1)), collapse = ", "),
    "].forEach(compileRegex);\n})()"
  )
}

# Chrome validates pattern syntax at use time, so every attempt compiles
# each regex even when no elements match: an invalid pattern must error
# rather than let a negated expectation pass vacuously.
regex_compile_attempt <- function(els, specs, call = caller_env()) {
  timeout <- els$page$default_timeout
  doing <- "compiling the regular expression"
  res <- cdp_call(
    els$page$session$Runtime$evaluate(
      regex_compile_js(specs),
      awaitPromise = FALSE,
      returnByValue = TRUE,
      timeout_ = timeout
    ),
    timeout,
    doing,
    call = call
  )
  cdp_check_exception(res, doing, call = call)
  invisible(TRUE)
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
    n_ok <- sum(els_values_flat(els, js))
    pass <- if (not) n_ok == 0L else n_ok == els$count
    list(pass = pass, observed = paste0(n_ok, " of ", els$count, " ", seen))
  }
}

check_visible <- function(not) {
  check_state(expect_visible_js, not, "visible")
}

# One value applies to every match; vectors require an exact count and
# pairwise matches. Negation requires no matching pair.
check_text_like <- function(js, values, not) {
  n <- if (is_regex(values)) 1L else length(values)
  function(els) {
    if (els$count == 0L) {
      regex_specs_attempt(els, values)
      return(list(pass = not, observed = expect_seen_count(0L)))
    }
    res <- els_values(els, js)
    vals <- chr_or_na(res$values)
    observed <- expect_seen_texts(vals)
    if (n > 1L && els$count != n) {
      return(list(pass = not, observed = observed))
    }
    hits <- map_lgl(res$hits, isTRUE)
    pass <- if (not) !any(hits) else all(hits)
    list(pass = pass, observed = observed)
  }
}

check_text <- function(text, not) {
  check_text_like(expect_values_js(text, "el.textContent"), text, not)
}

check_value <- function(value, not) {
  check_text_like(
    expect_values_js(value, "el.value == null ? null : String(el.value)"),
    value,
    not
  )
}

regex_specs_attempt <- function(els, values, call = caller_env()) {
  if (is_regex(values)) {
    values <- list(values)
  }
  specs <- lapply(values, function(value) {
    if (is_regex(value)) regex_spec_fields(value)
  })
  specs <- Filter(Negate(is.null), specs)
  if (length(specs) > 0L) {
    regex_compile_attempt(els, specs, call = call)
  }
  invisible(TRUE)
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
  if (".match" %in% nms) {
    cli::cli_abort(
      c(
        "{.arg .match} was removed from {.fn pz_expect_attr}.",
        i = "String pairs compare exactly; use {.fn pz_regex} with {.code fixed = TRUE} for substring matching."
      ),
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
    if (is_regex(value)) {
      return(value)
    }
    check_character(value, arg = nm, call = call)
    value
  })
}

# Mixed string/regex calls keep the legacy combined condition (all
# pairs hold, or under .not not all hold). Chrome computes every hit;
# diagnostics report the raw attributes.
check_attr_pairs <- function(pairs, not) {
  js <- expect_attrs_js(pairs)
  function(els) {
    if (els$count == 0L) {
      regex_specs_attempt(els, pairs)
      return(list(pass = not, observed = expect_seen_count(0L)))
    }
    res <- els_values(els, js)
    hits <- matrix(FALSE, nrow = els$count, ncol = length(pairs))
    observed <- character(length(pairs))
    for (p in seq_along(pairs)) {
      raw <- chr_or_na(lapply(res, function(el) el[[p]]$value))
      hits[, p] <- map_lgl(res, function(el) isTRUE(el[[p]]$hit))
      observed[[p]] <- expect_seen_texts(raw)
    }
    seen <- if (length(pairs) == 1L) {
      observed[[1]]
    } else {
      expect_truncate(paste0(names(pairs), ": ", observed, collapse = "; "))
    }
    list(pass = if (not) !all(hits) else all(hits), observed = seen)
  }
}

expect_headline_attrs <- function(pairs, not) {
  if (length(pairs) == 1L) {
    name <- names(pairs)[[1]]
    return(expect_headline_text(
      pairs[[1]],
      not,
      label = paste0("attribute \"", name, "\""),
      plural = paste0("attributes \"", name, "\"")
    ))
  }
  what <- vapply(
    seq_along(pairs),
    function(i) {
      value <- pairs[[i]]
      shown <- if (is_regex(value)) {
        format_regex(value)
      } else {
        expect_seen_texts(value)
      }
      paste0(names(pairs)[[i]], " = ", shown)
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

expect_headline_js <- function(expr, not) {
  paste0(
    "Expected JS predicate (",
    expect_truncate(expr, width = 60),
    ") to hold for ",
    if (not) "no match" else "every match"
  )
}

expect_headline_regex <- function(x, not, label = "text") {
  paste0(
    "Expected ",
    label,
    if (not) " not",
    " to match ",
    format_regex(x)
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
  not,
  label = "text",
  plural = paste0(label, "s")
) {
  if (is_regex(text)) {
    return(expect_headline_regex(text, not, label = label))
  }
  what <- paste0('"', text, '"', collapse = ", ")
  label <- if (length(text) == 1L) label else plural
  paste0("Expected ", label, if (not) " not", " to be ", what)
}
