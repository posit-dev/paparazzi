# Shiny

Use this reference when the page is a Shiny app: start the app process, wait
for reactive work, set bound inputs, and assert what a user sees. All examples
below run in order. The bundled app needs the shiny package and Chromium.

## Open the app and own its process

Supply a Shiny app directory or runnable app file to `pz_open()`. It starts
a separate R process, opens the app, and waits for Shiny readiness. A page
opened this way owns the app process; `pz_close()` stops both.

```r
library(paparazzi)
page <- pz_open(pz_example("tasks-app"), width = 720, height = 640)
page |>
  pz_expect_text("2 tasks", target = "#summary", match = "exact") |>
  pz_expect_count(2, target = ".task")
```

Readiness means the Shiny connection is open, the HTML element is not
`shiny-busy`, and no output is `.recalculating`, continuously for at least
200 milliseconds. App paths and Shiny handles use this wait automatically.
For an already running app's URL, use `pz_open(url, wait = "shiny")` to get
the same initial readiness check.

The separate R process inherits the environment but not objects in the
calling R session. Put app dependencies in its code, and pass configuration
through `envvars` or `shiny_options` when starting the process. Both are
accepted by `pz_open()` for app paths and by `pz_serve_shiny()`.

## Assert the result of reactive work

A button click can trigger output work after the action returns. Assert the
observable result, so the next step runs only once that result is present.
This app deliberately delays list rendering; the expectation handles it.

```r
page |>
  pz_set_value("Buy milk", target = "#title") |>
  pz_act_click("#add") |>
  pz_expect_text("3 tasks", target = "#summary", match = "exact") |>
  pz_expect_visible(pz_loc(".task", has_text = "Buy milk"))
```

For work where there is no particular value to check, wait for Shiny idle,
then read or capture. `pz_wait_for_shiny_idle(timeout = NULL)` uses the page
session timeout. It checks the connection and reactive settling, not just
whether the HTML document has loaded.

```r
page |>
  pz_set_value("Renew library card", target = "#title") |>
  pz_act_click("#add") |>
  pz_wait_for_shiny_idle()
pz_get_text(page, target = "#summary")
```

A value expectation is usually more informative than an idle wait when the
expected output is known. Use idle for general settling and expectations to
state the behavior the script relies on.

## Choose between user actions and direct setters

Use `pz_act_type()` and `pz_act_click()` for the user-facing path, particularly
in recordings where staged typing and pointer motion explain the interaction.
Use `pz_set_value()` for fast setup of standard form controls: it sets the
value and dispatches input/change events. For widget-specific controls such
as selectize and sliders, use `pz_set_shiny_input()` through the registered
Shiny input binding so the visible widget and server input agree.

```r
page |>
  pz_set_shiny_input("priority", "high") |>
  pz_set_value("Water the plants", target = "#title") |>
  pz_act_click("#add") |>
  pz_expect_text("5 tasks", target = "#summary", match = "exact")

plants <- pz_loc(".task", has_text = "Water the plants")
stopifnot(identical(pz_get_attr(page, "data-priority", target = plants), "high"))
```

`pz_set_shiny_input(ctx, id, value)` uses the complete DOM ID, including a
module prefix, and searches within the current scope including its root.
Pass the ID string, such as `"editor-priority"`, rather than a CSS selector.
Values follow the binding's `setValue()` contract; date ranges accept a pair
of ISO date strings, and date-valued sliders accept ISO date strings.
Use actual values of the type expected by the widget.

For buttons, use `pz_act_click()`; for file inputs, use `pz_set_files()` with
local file paths. These operations take the browser control's path rather
than the binding setter path. For text inputs reachable directly,
`pz_set_value()` or `pz_act_type()` exercises DOM events naturally.

## Batch bound-input setup

By default, each `pz_set_shiny_input()` waits for idle. For several setup
changes followed by one observable result, `wait = FALSE` dispatches the
change immediately. End the batch with an idle wait or result expectation.

```r
page |>
  pz_set_shiny_input("title", "Check smoke alarms", wait = FALSE) |>
  pz_set_shiny_input("priority", "normal", wait = FALSE) |>
  pz_wait_for_shiny_idle() |>
  pz_act_click("#add") |>
  pz_expect_text("6 tasks", target = "#summary", match = "exact")
```

## Reacquire scopes around reactive outputs

Store lazy `pz_loc()` descriptions for outputs that Shiny replaces. After
an input change, expect the new content and create a fresh scope for later
operations. `pz_find()` pins specific DOM elements at find time, whereas a
locator is resolved on each use.

```r
smoke <- pz_loc(".task", has_text = "Check smoke alarms")
page |> pz_expect_visible(smoke)
row <- pz_find(page, smoke)
pz_get_text(row)
pz_close(page)
```

See Locators and scopes for immutable contexts and scope transitions.

## Share an app process across pages

Use `pz_serve_shiny()` when several pages need the same running app code.
Pass the handle to each `pz_open()`. The pages get independent Shiny sessions;
closing them leaves the shared app running. The handle owns that process and
provides `$stop()`, `$logs()`, `$is_running()`, `$url` and `$port`.

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

Register process cleanup immediately after startup. Read `$logs()` for app
stdout and stderr while it runs or after stopping it. `shiny_options` is a
list passed to `shiny::runApp()`; paparazzi manages the path, host and port.
`envvars` is a named character vector of child-process overrides.

## Test the user-visible contract

`pz_local_page()` starts the app and binds cleanup to the test frame. Inside
testthat, paparazzi expectations are test expectations. Start a fresh page
for each test so the task state is independent.

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

For suites sharing one app handle, each test can call `pz_local_page(app)`;
register handle cleanup at the suite's teardown scope. See Testing for
assertion choices and diagnostics. paparazzi tests the rendered interface
with CSS and browser actions; shinytest2 is an alternative when the main
contract is saved snapshots of Shiny input and output values.

## Turn a verified script into a demo

Keep the same actions and expectations, set `pz_stage()` options before
recording, and run the script inside `pz_record()`. Staged motion and typing
animate while the recorder runs; the same test steps outside recording run
at full speed. Choose direct setters for test setup and user actions for
interactions the viewer should see. The Recording and staging reference will
cover presentation details in phase 2; the skill overview contains a minimal
working recording example.
