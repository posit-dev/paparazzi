# Agent guide: Testing

paparazzi tests check what a user sees in a real browser. A test runs
the same actions a screenshot or recording would, and its expectations
wait for each step’s result before the next one starts.

## Test the action and its result

Inside
[`testthat::test_that()`](https://testthat.r-lib.org/reference/test_that.html),
every `pz_expect_*()` call is a testthat expectation, and a failure
fails the test. Outside testthat, a failure is an error of class
`paparazzi_expectation_failure` that reports the target, the last value
seen and how long it waited. A passing expectation returns the context
invisibly, so it sits in the middle of a chain.

Open the page with
[`pz_local_page()`](https://posit-dev.github.io/paparazzi/reference/pz_with_page.md)
so it closes when the test ends, pass or fail. Pages opened from an app
path stop their server too.

``` r

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

The click waits until the Add button can be clicked; the text
expectation waits for the save to finish. Those are two different
conditions, so expect each step’s result before starting the next.

## Choose the expectation that states the behavior

Choose the expectation that states the behavior precisely:

| Intended result | Expectation |
|----|----|
| DOM element appears or is removed | [`pz_expect_exists()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_exists.md) with `not` as needed |
| All matched elements are shown | [`pz_expect_visible()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_visible.md) |
| No match is visible | [`pz_expect_hidden()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_visible.md) |
| Collection has a size or range | `pz_expect_count(n)` or `min` / `max` |
| Displayed text changes | [`pz_expect_text()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_text.md) |
| Input value changes | [`pz_expect_value()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_value.md) |
| CSS class marks state | [`pz_expect_class()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_class.md) |
| Checkbox or radio is checked | [`pz_expect_checked()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_checked.md) |
| Control is enabled | [`pz_expect_enabled()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_enabled.md) |
| Focus or viewport placement matters | [`pz_expect_focused()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_focused.md), [`pz_expect_in_viewport()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_in_viewport.md) |
| Navigation reaches the destination | [`pz_expect_url()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_url.md), [`pz_expect_title()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_title.md) |
| App-specific DOM predicate holds | [`pz_expect_js()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_js.md) |

Most element expectations need at least one match, and every match must
pass;
[`pz_expect_exists()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_exists.md)
needs just one. To check one row, target it with `has_text` or `within`.
[`pz_expect_hidden()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_visible.md)
also passes when the element is absent, so pair it with
[`pz_expect_exists()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_exists.md)
when presence matters.

``` r

testthat::test_that("help starts hidden and can be opened", {
  page <- pz_local_page(pz_example("tasks"))
  page |>
    pz_expect_exists(target = "#help") |>
    pz_expect_hidden(target = "#help") |>
    pz_act_click("#toggle-help") |>
    pz_expect_visible(target = "#help")
})
```

## Match text and values

[`pz_expect_text()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_text.md)
collapses whitespace on both sides. `match = "contains"` (the default)
checks for a substring, `"exact"` for equality and `"regex"` for an R
regular expression. One expected string applies to every match; a vector
needs exactly that many matches and compares them in document order.

``` r

testthat::test_that("text entry updates the input value", {
  page <- pz_local_page(pz_example("tasks"))
  page |>
    pz_act_type("Buy milk", target = "#task-title") |>
    pz_expect_value("Buy milk", target = "#task-title", match = "exact")
  testthat::expect_identical(pz_get_value(page, target = "#task-title"), "Buy milk")
})
```

Getters return plain values and end the chain, so compare them with
ordinary testthat expectations.
[`pz_get_count()`](https://posit-dev.github.io/paparazzi/reference/pz_get_count.md)
reads once and can return zero; use
[`pz_expect_count()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_count.md)
when the count is about to change.

## Wait on conditions, not time

Expectations retry until they pass or time out. `timeout = NULL` uses
the page’s default, set with `pz_open(timeout = )` or through
[`pz_local_page()`](https://posit-dev.github.io/paparazzi/reference/pz_with_page.md).
`timeout = 0` checks once, for when an earlier step already waited.

When there’s no particular value to expect, wait on a condition instead:
[`pz_wait_for_shiny_idle()`](https://posit-dev.github.io/paparazzi/reference/pz_wait_for_shiny_idle.md)
for reactive work,
[`pz_wait_for_stable()`](https://posit-dev.github.io/paparazzi/reference/pz_wait_for_stable.md)
for settled layout or text, or
[`pz_wait_for_js()`](https://posit-dev.github.io/paparazzi/reference/pz_wait_for_js.md)
for a JavaScript predicate.
[`pz_wait()`](https://posit-dev.github.io/paparazzi/reference/pz_wait.md)
is a fixed wait that keeps the browser running, recordings included.

``` r

pz_with_page(pz_example("tasks"), function(page) {
  page |>
    pz_wait_for_js("document.readyState === 'complete'") |>
    pz_wait_for_stable(target = ".task-list", prop = "rect", for_ms = 200) |>
    pz_expect_count(7, target = ".task", timeout = 0)
})
```

The default page timeout is ten seconds. For a slow app, raise the
timeout rather than adding fixed pauses.

## Test navigation between documents

Serve test pages over HTTP so links and history behave as they do on a
real site. This example writes two small pages joined by a link, then
tests the click, the destination and the way back. It needs httpuv. The
function owns the server and the test owns the page.

``` r

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

Navigation resets scopes to the root, so find the destination’s elements
again (see Locators and scopes).

## Inspect state when a test fails

[`pz_inspect()`](https://posit-dev.github.io/paparazzi/reference/pz_inspect.md)
prints the page’s state, and getters return specific values to R. A
screenshot with an explicit path saves evidence without opening a
viewer, and the chain continues.

``` r

pz_with_page(pz_example("tasks"), function(page) {
  page |> pz_expect_visible(target = "#new-task")
  pz_inspect(page)
  pz_get_elements(page, target = "#new-task input")
  pz_get_attr(page, "type", target = "#task-title")
  pz_get_style(page, "display", target = "#new-task")
  page |> pz_screenshot(tempfile(fileext = ".png"), frame = "#new-task")
})
```

For checks no built-in expectation covers,
[`pz_expect_js()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_js.md)
takes a JavaScript function that receives each matched element and
returns `true` or `false`. At the root, the target defaults to the page
body.

``` r

pz_with_page(pz_example("tasks"), function(page) {
  page |>
    pz_expect_js("el => el.querySelectorAll('.task').length === 7")
})
```

Browser tests need Chrome or Chromium where chromote can find it. Open a
new page in each test so tests don’t share state. A shared Shiny server
can save startup time while each page still gets its own app session
(see Shiny).
