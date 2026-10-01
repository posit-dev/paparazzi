# Wait while pumping the page's event loop

Pauses for `seconds`, driving chromote's child event loop so timers
scheduled on it (e.g. recording capture) keep firing during the wait.
Never sleeps without pumping the loop.

## Usage

``` r
pz_wait(ctx, seconds)
```

## Arguments

- ctx:

  A paparazzi context.

- seconds:

  Number of seconds to wait.

## Value

`ctx`, invisibly.

## Examples

``` r
if (FALSE) { # paparazzi:::examples_run()
page <- pz_open(pz_example("tasks"))

# A fixed pause; prefer an expectation or wait_for function when you
# know what you're waiting for
page |>
  pz_act_click("#toggle-help") |>
  pz_wait(0.5)
pz_close(page)
}
```
