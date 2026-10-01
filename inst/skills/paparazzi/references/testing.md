# Testing

Use paparazzi to verify user-visible behavior in a Chromium browser. Tests
script the same actions used by screenshots and recordings; expectations
synchronize each transition with the state that matters to the user.

## Test the action and its result

Inside `testthat::test_that()`, each `pz_expect_*()` call counts as a testthat
expectation. A failed expectation becomes a test failure. Outside testthat,
it raises a `paparazzi_expectation_failure` with the target, last observed
value and elapsed wait. Passing expectations return the context invisibly,
so they belong directly in the action chain.

Use `pz_local_page()` inside the test. It closes the page when the test frame
exits, including when a step fails. App paths also get server cleanup.

```r
library(paparazzi)

testthat::test_that("adding a task inserts its title first", {
  page <- pz_local_page(pz_example("tasks"), width = 1000, height = 720)
  page |>
    pz_act_type("Repot the fern", target = "#task-title") |>
    pz_act_click("#add-task") |>
    pz_expect_text(
      "Repot the fern",
      target = pz_loc(".task-title", which = "first"),
      match = "exact"
    ) |>
    pz_expect_count(8, target = ".task")
})
```

The click waits for the Add button to be actionable. The text expectation
waits for the asynchronous save to finish. These are separate readiness
conditions: assert the resulting state before starting the next operation.

## Pick the observable contract

Choose the expectation that states the behavior precisely:

| Intended result | Expectation |
| --- | --- |
| DOM element appears or is removed | `pz_expect_exists()` with `not` as needed |
| All matched elements are shown | `pz_expect_visible()` |
| No match is visible | `pz_expect_hidden()` |
| Collection has a size or range | `pz_expect_count(n)` or `min` / `max` |
| Displayed text changes | `pz_expect_text()` |
| Input value changes | `pz_expect_value()` |
| CSS class marks state | `pz_expect_class()` |
| Checkbox or radio is checked | `pz_expect_checked()` |
| Control is enabled | `pz_expect_enabled()` |
| Focus or viewport placement matters | `pz_expect_focused()`, `pz_expect_in_viewport()` |
| Navigation reaches the destination | `pz_expect_url()`, `pz_expect_title()` |
| App-specific DOM predicate holds | `pz_expect_js()` |

Most element expectations require at least one match and every match to pass.
`pz_expect_exists()` needs only one match. For a specific row, use `pz_loc()`
with `has_text` or `within` rather than asserting a condition on all rows.
Negative visibility includes an absent target; use existence to distinguish
presence from visibility when that distinction is the contract.

```r
testthat::test_that("help starts hidden and can be opened", {
  page <- pz_local_page(pz_example("tasks"))
  page |>
    pz_expect_exists(target = "#help") |>
    pz_expect_hidden(target = "#help") |>
    pz_act_click("#toggle-help") |>
    pz_expect_visible(target = "#help")
})
```

## Match text and values intentionally

`pz_expect_text()` collapses whitespace on the observed and expected sides.
The default `match = "contains"` checks substrings; `"exact"` checks equality;
`"regex"` uses an R regular expression. A length-one expected string applies
to every match. A vector of expected strings requires that many matches and
compares them pairwise in document order.

```r
testthat::test_that("text entry updates the input value", {
  page <- pz_local_page(pz_example("tasks"))
  page |>
    pz_act_type("Buy milk", target = "#task-title") |>
    pz_expect_value("Buy milk", target = "#task-title", match = "exact")
  testthat::expect_identical(pz_get_value(page, target = "#task-title"), "Buy milk")
})
```

Getters end the context chain and return values: use normal testthat
expectations for R-side comparisons. `pz_get_count()` reads once, including
zero; a retrying `pz_expect_count()` is the synchronization step for a count
that will change.

## Use condition-based waits

Expectations retry until they pass or the timeout expires. `timeout = NULL`
uses the page default, configured with `pz_open(timeout = ...)` or forwarded
through `pz_local_page()`. `timeout = 0` checks once when the prior step has
already established readiness.

When there is no specific value to assert, use `pz_wait_for_shiny_idle()` for
reactive work, `pz_wait_for_stable()` for stable geometry or text, or
`pz_wait_for_js()` for a browser predicate. `pz_wait()` pumps the browser's
event loop during a deliberate fixed wait, including during recording.

```r
pz_with_page(pz_example("tasks"), function(page) {
  page |>
    pz_wait_for_js("document.readyState === 'complete'") |>
    pz_wait_for_stable(target = ".task-list", prop = "rect", for_ms = 200) |>
    pz_expect_count(7, target = ".task", timeout = 0)
})
```

Use a timeout appropriate to the operation. The default page timeout is ten
seconds; increasing it for a slow application is more useful than adding
fixed pauses after every action. For a specific outcome, write the expectation
on that outcome rather than waiting for unrelated page activity.

## Test full-document navigation over HTTP

Serve fixtures over HTTP so browser navigation and history use normal web
semantics. This example creates two tiny pages with a real link and tests the
click, settled navigation, destination content and return trip. It requires
httpuv. The function owns the server; the test owns the browser page.

```r
check_navigation <- function() {
  site <- tempfile("paparazzi-site-")
  dir.create(site)
  withr::defer(unlink(site, recursive = TRUE))
  writeLines(
    '<title>Start</title><a id="next" href="next.html">Continue</a>',
    file.path(site, "index.html")
  )
  writeLines('<title>Next</title><h1>Arrived</h1>', file.path(site, "next.html"))
  server <- pz_serve_static(site)
  withr::defer(server$stop())

  testthat::test_that("the link opens the next document", {
    page <- pz_local_page(server)
    page |>
      pz_act_click("#next") |>
      pz_wait_for_navigation() |>
      pz_expect_url("/next.html", match = "contains") |>
      pz_expect_text("Arrived", target = "h1", match = "exact") |>
      pz_nav_back() |>
      pz_expect_title("Start", match = "exact")
  })
}
check_navigation()
```

Navigation resets scopes to the root. Reuse specs, then find fresh contexts
for the destination. See Locators and scopes for that distinction.

## Inspect failures with values and captures

`pz_inspect()` reports page state. Getters make focused diagnostics available
as R values. After reaching the expected state, an explicit screenshot path
captures evidence without opening a viewer and leaves the context chainable.

```r
pz_with_page(pz_example("tasks"), function(page) {
  page |> pz_expect_visible(target = "#new-task")
  pz_inspect(page)
  pz_get_elements(page, target = "#new-task input")
  pz_get_attr(page, "type", target = "#task-title")
  pz_get_style(page, "display", target = "#new-task")
  page |> pz_screenshot(tempfile(fileext = ".png"), frame = "#new-task")
})
```

For app-specific predicates, `pz_expect_js()` takes a JavaScript function
receiving each matching DOM element as its argument. At the root its target
is the page body by default. Use a function that returns a boolean.

```r
pz_with_page(pz_example("tasks"), function(page) {
  page |>
    pz_expect_js("el => el.querySelectorAll('.task').length === 7")
})
```

Run browser tests in an environment with Chrome or Chromium available to
chromote. Keep each test's starting state independent by opening a new page.
Shared Shiny server processes can save startup time while each page retains
its own app session; see Shiny. Configure deterministic viewport and device
preferences as described in Pages and serving.
