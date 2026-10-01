# Set a bound Shiny input

Uses the input's registered Shiny binding to update the visible control
and notify the server. The `id` is the complete DOM ID, including any
module prefix (for example, `"mod-text"`); it is searched only in the
current scope, including the scope element itself. This does not set
unbound inputs, action buttons, or file inputs.

## Usage

``` r
pz_set_shiny_input(ctx, id, value, ..., wait = TRUE)
```

## Arguments

- ctx:

  A paparazzi context.

- id:

  Full DOM ID of a bound Shiny input.

- value:

  Value accepted by the binding's `setValue()`. Date ranges accept
  `c(start, end)` or `list(start = ..., end = ...)`, with ISO date
  strings. Date-valued sliders accept ISO date strings, converted to
  JavaScript timestamps. Top-level `NULL` and atomic `NA` are rejected.

- ...:

  Checked empty; reserved for future use.

- wait:

  If `TRUE`, call
  [`pz_wait_for_shiny_idle()`](https://posit-dev.github.io/paparazzi/reference/pz_wait_for_shiny_idle.md)
  after the change. If `FALSE`, return immediately after dispatching the
  change.

## Value

`ctx`, invisibly.

## Examples

``` r
if (FALSE) { # paparazzi:::examples_run("shiny")
page <- pz_open(pz_example("tasks-app"))

# Each call waits for Shiny to go idle, so the server has seen the value
page |>
  pz_set_shiny_input("title", "Buy milk") |>
  pz_set_shiny_input("priority", "high") |>
  pz_act_click("#add") |>
  pz_expect_text("3 tasks", target = "#summary")
pz_get_attr(page, "data-priority", target = ".task")
pz_close(page)
}
```
