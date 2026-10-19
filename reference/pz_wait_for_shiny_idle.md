# Wait until a Shiny page is idle

Waits for the Shiny connection and for `<html>` to lose `shiny-busy`,
both holding continuously for at least 200ms, including brief busy
transitions. These track Shiny's own busy signal – the same contract
shinytest2 uses. An output suspended on a hidden tab keeps its
`.recalculating` class until the tab shows, because the server reports
it invalidated but never recomputes it; the wait deliberately does not
inspect per-output recalculating state, so such apps settle.

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

## Details

Idle means the server finished its reactive flush; it does not prove a
particular output was delivered or is ready to capture. Expect the
content you rely on (e.g.
[`pz_expect_text()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_text.md))
before reading or capturing it.

A page without the Shiny global errors instead of waiting; a page whose
Shiny app never connects times out.

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
