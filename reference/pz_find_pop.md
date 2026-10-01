# Pop the current scope

`pz_find_pop()` returns a context one scope level up the stack. The
popped pinned set is NOT released – a context derived before the pop may
still hold it – and popping never mutates the context it was called on.
At the root it is a no-op returning `ctx` unchanged.

## Usage

``` r
pz_find_pop(ctx)
```

## Arguments

- ctx:

  A paparazzi context.

## Value

A new context one level up, or `ctx` itself at the root.

## See also

[`pz_find()`](https://posit-dev.github.io/paparazzi/reference/pz_find.md),
[`pz_find_reset()`](https://posit-dev.github.io/paparazzi/reference/pz_find_reset.md)

## Examples

``` r
page <- pz_open(pz_example("tasks"))
page |>
  pz_find(".task-list") |>
  pz_find_last(".task") |>
  pz_act_click(".task-done") |>
  # Back to the whole list, to check the result
  pz_find_pop() |>
  pz_expect_count(2, target = ".task.done") |>
  pz_get_count(target = ".task.done")
#> [1] 2
pz_close(page)
```
