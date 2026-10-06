# Shiny apps

paparazzi works with any web page, and a Shiny app is a web page. But
Shiny apps need a few extra things. The app has to be running before a
browser can open it. The page keeps changing after it loads, as the
server sends outputs. And some inputs, like selectize dropdowns and
sliders, are awkward to set by clicking. This article covers the tools
paparazzi has for each of these, and how to use them in tests.

If you haven’t used paparazzi before, start with the [Get started
article](https://posit-dev.github.io/paparazzi/articles/paparazzi.md),
which introduces actions, expectations, and scopes on a static page.

``` r

library(paparazzi)
```

## Open an app

Give
[`pz_open()`](https://posit-dev.github.io/paparazzi/reference/pz_open.md)
a Shiny app, as a directory or an `app.R` file, and paparazzi does three
things: it starts the app in a background R process, opens it in the
browser, and waits until Shiny is ready. paparazzi’s example app is a
Shiny version of the task tracker from the Get started article:

``` r

page <- pz_open(pz_example("tasks-app"), width = 720, height = 640)
page |> pz_screenshot()
```

![The Shiny task app: a title input, a priority dropdown, an Add button,
and a list of two tasks.](shiny_files/figure-html/unnamed-chunk-2-1.png)

“Ready” means Shiny is **idle**: the browser has connected to the app,
and no outputs are being recalculated, for at least 200 milliseconds in
a row. The task list in this app takes half a second to render, and
[`pz_open()`](https://posit-dev.github.io/paparazzi/reference/pz_open.md)
waited for it, so the list is already in the screenshot.

This page owns its app, so `pz_close(page)` will stop the app too. The
app runs in a separate R process, so it can’t see objects in your
session. If it needs settings, pass them as environment variables with
`envvars`, or as
[`shiny::runApp()`](https://rdrr.io/pkg/shiny/man/runApp.html) options
with `shiny_options`.

## Wait for the server

Shiny apps do their work on the server, so the page changes a little
after each input. Clicking Add sends a message to the server, which
updates the list and re-renders it. Waits and expectations cover this in
two ways.

[`pz_wait_for_shiny_idle()`](https://posit-dev.github.io/paparazzi/reference/pz_wait_for_shiny_idle.md)
waits until Shiny is idle again. It’s the right tool when you don’t care
about a specific value, only that the app has caught up:

``` r

page |>
  pz_set_value("Buy milk", target = "#title") |>
  pz_act_click("#add") |>
  pz_wait_for_shiny_idle()

pz_get_text(page, target = "#summary")
#> [1] "3 tasks"
```

[`pz_set_value()`](https://posit-dev.github.io/paparazzi/reference/pz_set_value.md)
sets the text input the same way for any page: it sets the value and
fires the input’s `input` and `change` events, which is how Shiny learns
about the change.

When you know what the page should show, an expectation is usually
better. It retries until the page shows that value, so it waits for
exactly what you care about, and it says what went wrong if the value
never appears:

``` r

page |>
  pz_set_value("Renew library card", target = "#title") |>
  pz_act_click("#add") |>
  pz_expect_text("4 tasks", target = "#summary")
```

## Set inputs through Shiny

Some Shiny inputs are hard to set by clicking. The priority input in
this app is a selectize input: the `<select>` element is hidden, and the
dropdown you see is built from other elements.
[`pz_set_shiny_input()`](https://posit-dev.github.io/paparazzi/reference/pz_set_shiny_input.md)
sets an input through its Shiny **input binding**, the JavaScript object
Shiny uses to read and update that input. The widget on the page
updates, and the server sees the new value:

``` r

page |>
  pz_set_shiny_input("priority", "high") |>
  pz_screenshot(frame = pz_frame(".selectize-control", pad = 8))
```

![The priority dropdown showing
high.](shiny_files/figure-html/unnamed-chunk-5-1.png)

[`pz_set_shiny_input()`](https://posit-dev.github.io/paparazzi/reference/pz_set_shiny_input.md)
takes the input’s ID and waits for Shiny to go idle afterward, so the
app has reacted by the time the next step runs. It works with inputs
whose binding can set a value, including sliders and date ranges; file
inputs and action buttons aren’t supported, so use
[`pz_set_files()`](https://posit-dev.github.io/paparazzi/reference/pz_set_files.md)
and
[`pz_act_click()`](https://posit-dev.github.io/paparazzi/reference/pz_act_click.md)
for those. For inputs that are easy to reach, like text boxes and
buttons,
[`pz_act_type()`](https://posit-dev.github.io/paparazzi/reference/pz_act_type.md),
[`pz_set_value()`](https://posit-dev.github.io/paparazzi/reference/pz_set_value.md),
and
[`pz_act_click()`](https://posit-dev.github.io/paparazzi/reference/pz_act_click.md)
are closer to what a person does, and those are what you want in a
recording.

## Share one app across pages

Starting an app takes time. To open several pages on the same app, start
it once with
[`pz_serve_shiny()`](https://posit-dev.github.io/paparazzi/reference/pz_serve_shiny.md)
and pass the handle to
[`pz_open()`](https://posit-dev.github.io/paparazzi/reference/pz_open.md).
For example, to compare the desktop and phone layouts side by side:

``` r

app <- pz_serve_shiny(pz_example("tasks-app"))
app
#> <paparazzi app> http://127.0.0.1:5048/ -- running (pid 13468)

desktop <- pz_open(app, width = 1024, height = 640)
phone <- pz_open(app, width = 390, height = 640, mobile = TRUE)
```

Each page gets its own Shiny session, so the two pages have separate
task lists. Pages opened from a handle don’t own the app, so closing
them leaves it running. Stop it yourself when you’re done. `app$logs()`
returns what the app printed, which helps when an app fails to start or
errors partway through:

``` r

pz_close(desktop)
pz_close(phone)

head(app$logs())
#> [1] "Loading required package: shiny"    ""                                  
#> [3] "Listening on http://127.0.0.1:5048"
app$stop()
```

In a script, `withr::defer(app$stop())` makes sure the app stops even if
a later step fails.

## Test an app

When paparazzi’s expectations run inside a testthat test, each one
counts as a testthat expectation, and a failure is reported as a test
failure.
[`pz_local_page()`](https://posit-dev.github.io/paparazzi/reference/pz_with_page.md)
opens a page and closes it when the test ends. Given an app path, the
page starts the app and stops it at the end too. Together, a test for
the task app looks like this:

``` r

test_that("adding a task updates the summary", {
  page <- pz_local_page(pz_example("tasks-app"))

  page |>
    pz_set_value("Buy milk", target = "#title") |>
    pz_act_click("#add") |>
    pz_expect_text("3 tasks", target = "#summary")
})
```

For your own app, point
[`pz_local_page()`](https://posit-dev.github.io/paparazzi/reference/pz_with_page.md)
at the app’s directory. To share one running app between tests, start it
with
[`pz_serve_shiny()`](https://posit-dev.github.io/paparazzi/reference/pz_serve_shiny.md)
and pass the handle instead; you then stop the app yourself, for example
with `withr::defer(app$stop(), testthat::teardown_env())` in a setup
file.

[shinytest2](https://rstudio.github.io/shinytest2/) is also built for
testing Shiny apps, and it works differently. shinytest2 records an
app’s input and output values and compares them against saved snapshots,
which suits regression tests of an app’s reactive logic. paparazzi finds
elements with CSS selectors and interacts with the page as a person
would, which suits testing what a user sees and does. The two can live
in the same test suite.

## Record a demo

Recording works the same way for apps as for any other page. Stage the
page, wrap the steps in
[`pz_record()`](https://posit-dev.github.io/paparazzi/reference/pz_record.md),
and paparazzi animates the cursor and typing while it records:

``` r

page |>
  pz_stage(enter = "left", pause = 0.4) |>
  pz_record(
    code = {
      page |>
        pz_act_type("Water the plants", target = "#title") |>
        pz_act_click("#add") |>
        pz_expect_text("5 tasks", target = "#summary") |>
        pz_cursor_leave()
    },
    format = "gif",
    scale = 0.6
  )
```

![A cursor glides to the title input, types Water the plants, and clicks
Add. The task count changes from 4 to 5 and the new task appears at the
end of the list.](shiny_files/figure-html/unnamed-chunk-8-1.gif)
