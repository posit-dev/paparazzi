# Shiny

This reference covers Shiny apps: starting the app process, waiting for
reactive work, setting bound inputs and checking what the user sees. The
examples run in order and need the shiny package.

## Open the app

Give `pz_open()` a Shiny app directory or app file. It starts the app in a
separate R process, opens it and waits until Shiny is ready. The page owns
that process, so `pz_close()` stops both.

```r
library(paparazzi)
page <- pz_open(pz_example("tasks-app"), width = 720, height = 640)
page |>
  pz_expect_text("2 tasks", target = "#summary", match = "exact") |>
  pz_expect_count(2, target = ".task")
```

"Ready" means the Shiny connection is open, the page isn't `shiny-busy`, and
no output is `.recalculating`, all holding for at least 200 milliseconds.
App paths and Shiny handles wait for this automatically; for an app that's
already running, use `pz_open(url, wait = "shiny")`.

The app process inherits environment variables but none of your R session's
objects. Load what the app needs in its own code, and pass configuration
with `envvars` or `shiny_options`, which both `pz_open()` and
`pz_serve_shiny()` accept.

## Expect the result of reactive work

A click can start output work that finishes after the action returns.
Expect the visible result so the next step waits for it. This app delays
rendering the list on purpose, and the expectation absorbs the delay.

```r
page |>
  pz_set_value("Buy milk", target = "#title") |>
  pz_act_click("#add") |>
  pz_expect_text("3 tasks", target = "#summary", match = "exact") |>
  pz_expect_visible(pz_loc(".task", has_text = "Buy milk"))
```

When there's no particular value to expect, wait for Shiny to go idle, then
read or capture. `pz_wait_for_shiny_idle()` checks the connection and
reactive work, not just whether the page has loaded.

```r
page |>
  pz_set_value("Renew library card", target = "#title") |>
  pz_act_click("#add") |>
  pz_wait_for_shiny_idle()
pz_get_text(page, target = "#summary")
```

When you know the expected output, an expectation is the better check: it
states what the script relies on, and its failure says what was missing.

## Choose user actions or direct setters

`pz_act_type()` and `pz_act_click()` go through the page the way a user does,
which is what a recording should show. `pz_set_value()` sets a standard form
control and fires its input and change events, which is faster for setup.
For widgets such as selectize inputs and sliders, `pz_set_shiny_input()` goes
through the Shiny input binding, so the widget and the server agree.

```r
page |>
  pz_set_shiny_input("priority", "high") |>
  pz_set_value("Water the plants", target = "#title") |>
  pz_act_click("#add") |>
  pz_expect_text("5 tasks", target = "#summary", match = "exact")

plants <- pz_loc(".task", has_text = "Water the plants")
stopifnot(identical(pz_get_attr(page, "data-priority", target = plants), "high"))
```

`pz_set_shiny_input(ctx, id, value)` takes the input's full DOM ID, including
any module prefix (`"editor-priority"`), not a CSS selector. It looks inside
the current scope, the scope element included. Values follow the binding's
`setValue()`: date ranges take a pair of ISO date strings, as do date
sliders.

Click buttons with `pz_act_click()` and fill file inputs with
`pz_set_files()`.

## Set several inputs at once

Each `pz_set_shiny_input()` waits for Shiny to go idle. To set several inputs
before one result, pass `wait = FALSE` and end with an idle wait or an
expectation.

```r
page |>
  pz_set_shiny_input("title", "Check smoke alarms", wait = FALSE) |>
  pz_set_shiny_input("priority", "normal", wait = FALSE) |>
  pz_wait_for_shiny_idle() |>
  pz_act_click("#add") |>
  pz_expect_text("6 tasks", target = "#summary", match = "exact")
```

## Refind scopes around outputs

Shiny replaces output elements when it re-renders them, and a scope pins the
element it found. Keep a `pz_loc()` spec for the output, expect the new
content, then find it again (see Locators and scopes).

```r
smoke <- pz_loc(".task", has_text = "Check smoke alarms")
page |> pz_expect_visible(smoke)
row <- pz_find(page, smoke)
pz_get_text(row)
pz_close(page)
```

See Locators and scopes for immutable contexts and scope transitions.

## Share one app across pages

`pz_serve_shiny()` starts the app once for several pages. Each page opened
from the handle gets its own Shiny session, and closing the pages leaves the
app running. The handle owns the process and has `$stop()`, `$logs()`,
`$is_running()`, `$url` and `$port`.

```r
compare_layouts <- function() {
  app <- pz_serve_shiny(
    pz_example("tasks-app"),
    shiny_options = list(test.mode = TRUE),
    envvars = c(PAPARAZZI_DEMO = "true"),
    timeout = 20
  )
  withr::defer(app$stop())
  pz_with_page(app, function(desktop) {
    desktop |> pz_expect_text("2 tasks", target = "#summary", match = "exact")
    pz_with_page(app, function(phone) {
      phone |> pz_expect_text("2 tasks", target = "#summary", match = "exact")
      phone |> pz_screenshot(tempfile(fileext = ".png"))
    }, width = 390, height = 844, mobile = TRUE)
  }, width = 1024, height = 768)
  head(app$logs())
}
compare_layouts()
```

Call `withr::defer(app$stop())` right after starting the app. `$logs()`
returns the app's stdout and stderr, during or after the run.
`shiny_options` is passed to `shiny::runApp()` (paparazzi sets the path, host
and port), and `envvars` is a named character vector for the app process.

## Test what the user sees

`pz_local_page()` starts the app and closes it when the test ends. Open a
fresh page in each test so tests don't share task state.

```r
testthat::test_that("a high-priority task is shown in the list", {
  page <- pz_local_page(pz_example("tasks-app"), timeout = 20)
  page |>
    pz_set_shiny_input("priority", "high") |>
    pz_act_type("Book dentist", target = "#title") |>
    pz_act_click("#add") |>
    pz_expect_text("3 tasks", target = "#summary", match = "exact") |>
    pz_expect_visible(pz_loc(".task[data-priority='high']", has_text = "Book dentist"))
})
```

When tests share one app handle, call `pz_local_page(app)` in each test and
stop the handle in the suite's teardown. paparazzi tests the rendered page
through the browser; shinytest2 suits tests built on snapshots of Shiny input
and output values.

## Turn a tested script into a demo

The same actions and expectations make a recording: call `pz_stage()`, then
run the steps inside `pz_record()`. Staged cursor motion and typing only
animate while recording, so the test still runs at full speed. Use direct
setters for setup the viewer doesn't need to see, and user actions for the
steps they should watch. The Recording and staging reference shows the
pattern.
