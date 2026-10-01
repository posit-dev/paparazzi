# Clear all scope, back to the root

`pz_find_reset()` returns a context with an empty scope stack. No pinned
set is released – contexts derived before the reset may still hold them
– and resetting never mutates the context it was called on. At the root
it is a no-op returning `ctx` unchanged.

## Usage

``` r
pz_find_reset(ctx)
```

## Arguments

- ctx:

  A paparazzi context.

## Value

A new root context, or `ctx` itself at the root.

## See also

[`pz_find()`](https://posit-dev.github.io/paparazzi/reference/pz_find.md),
[`pz_find_pop()`](https://posit-dev.github.io/paparazzi/reference/pz_find_pop.md)

## Examples

``` r
page <- pz_open(pz_example("tasks"))
page |>
  pz_find(".task-list") |>
  pz_find_first(".task") |>
  pz_act_click(".task-done") |>
  # The help toggle is outside the list, so start again from the root
  pz_find_reset() |>
  pz_act_click("#toggle-help") |>
  pz_expect_visible(target = "#help") |>
  pz_get_text(target = "#help")
#> [1] "Type a task and press Enter to add it. Edit a title, mark a task done, or drag tasks to reorder them. Nothing is saved: reload or Start over resets the list."
pz_close(page)
```
