# Wait until a JavaScript condition holds

Polls `expr` until it evaluates truthy, then returns `ctx` invisibly.
Each poll awaits a promise `expr` returns, so async conditions work;
JavaScript truthiness applies (a non-empty string or a non-zero number
counts). An `expr` that throws is a JavaScript error, not a failed poll.

## Usage

``` r
pz_wait_for_js(ctx, expr, ..., timeout = NULL)
```

## Arguments

- ctx:

  A paparazzi context.

- expr:

  A string of JavaScript that evaluates truthy when the condition holds.
  A returned promise is awaited first.

- ...:

  Checked empty; reserved for future use.

- timeout:

  Seconds before giving up; `NULL` uses the session default.

## Value

`ctx`, invisibly.

## Details

There is deliberately no element-state wait
(`pz_wait_for(target, state =)`):
[`pz_expect_visible()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_visible.md),
[`pz_expect_hidden()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_visible.md),
and
[`pz_expect_exists()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_exists.md)
with `not = TRUE` already retry, so they wait.

## See also

[`pz_wait_for_stable()`](https://posit-dev.github.io/paparazzi/reference/pz_wait_for_stable.md),
[`pz_wait_for_navigation()`](https://posit-dev.github.io/paparazzi/reference/pz_wait_for_navigation.md)

## Examples

``` r
page <- pz_open(pz_example("tasks"))
page |>
  pz_act_type("Buy milk", target = "#task-title") |>
  pz_act_press("Enter") |>
  pz_wait_for_js("document.querySelectorAll('.task').length === 8")
pz_get_text(page, target = pz_loc(".task-title", which = "first"))
#> [1] "Buy milk"
pz_close(page)
```
