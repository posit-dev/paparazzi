# Wait until a Shiny page is idle

Waits for the Shiny connection, for `<html>` to lose `shiny-busy`, and
for every `.recalculating` output to finish. All three conditions must
hold continuously for at least 200ms, including brief busy/recalculating
transitions. A page without the Shiny global errors instead of waiting;
a page whose Shiny app never connects times out.

## Usage

``` r
pz_wait_for_shiny_idle(ctx, ..., timeout = NULL)
```

## Arguments

- ctx:

  A paparazzi context.

- ...:

  Checked empty; reserved for future use.

- timeout:

  Seconds before giving up; `NULL` uses the session default.

## Value

`ctx`, invisibly.

## See also

[`pz_open()`](https://posit-dev.github.io/paparazzi/reference/pz_open.md)

## Examples

``` r
if (FALSE) { # paparazzi:::examples_run("shiny")
page <- pz_open(pz_example("tasks-app"))

# Clicking Add makes the server re-render the task list, which takes a moment
page |>
  pz_set_value("Buy milk", target = "#title") |>
  pz_act_click("#add") |>
  pz_wait_for_shiny_idle()
pz_get_text(page, target = "#summary")
pz_close(page)
}
```
