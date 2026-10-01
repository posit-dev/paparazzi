# Find elements and push them as the current scope

`pz_find()` resolves `target` (auto-waiting for at least one match),
pins the matched set as the current scope, and returns a new context:
later calls on it operate inside that scope. Explicit targets resolve
lazily among the scope's descendants at use time – re-renders within the
scope are fine – and `target = NULL` means the scope itself for the
calls that accept one.

The pinned set is eager: it is fixed at find time, and a later re-render
that detaches any of its elements aborts with a classed error on the
next use – the scope is never silently re-queried (a lazy, reusable
target is what
[`pz_loc()`](https://posit-dev.github.io/paparazzi/reference/pz_loc.md)
is for). Multi-match targets pin the whole set.

The stack is immutable: `pz_find*()` never mutate the context they are
called on, and contexts derived from the same parent share its pinned
sets.

## Usage

``` r
pz_find(ctx, target, ..., from_root = FALSE)
```

## Arguments

- ctx:

  A paparazzi context.

- target:

  A CSS selector string, a
  [`pz_loc()`](https://posit-dev.github.io/paparazzi/reference/pz_loc.md)
  spec, or a list of specs and strings (a union matching any of them).
  Required: there is nothing to find without a target, so `NULL` is an
  error. To narrow an existing scope, use
  [`pz_find_first()`](https://posit-dev.github.io/paparazzi/reference/pz_find_first.md),
  [`pz_find_last()`](https://posit-dev.github.io/paparazzi/reference/pz_find_last.md),
  or
  [`pz_find_nth()`](https://posit-dev.github.io/paparazzi/reference/pz_find_nth.md)
  without a target.

- ...:

  Checked empty; reserved for future use.

- from_root:

  Resolve the target from the page root instead of the current scope?
  The new scope is still pushed on top of the stack, so
  [`pz_find_pop()`](https://posit-dev.github.io/paparazzi/reference/pz_find_pop.md)
  returns to the previous scope.

## Value

A new context.

## See also

[`pz_find_first()`](https://posit-dev.github.io/paparazzi/reference/pz_find_first.md),
[`pz_find_pop()`](https://posit-dev.github.io/paparazzi/reference/pz_find_pop.md),
[`pz_find_reset()`](https://posit-dev.github.io/paparazzi/reference/pz_find_reset.md)

## Examples

``` r
page <- pz_open(pz_example("tasks"))

# Inside a scope, targets resolve among the scope's descendants
page |>
  pz_find(pz_loc(".task", has_text = "dentist")) |>
  pz_act_click(".task-done")
pz_get_attr(page, "class", target = pz_loc(".task", has_text = "dentist"))
#> [1] "task list-group-item d-flex align-items-center gap-2 done"

# Assign a scoped context to start more than one chain from it
task_list <- pz_find(page, ".task-list")
task_list
#> ── paparazzi scope ─────────────────────────────────────────────────────────────
#> Scope      root › `.task-list` (1)
#> URL        file:///home/runner/work/_temp/Library/paparazzi/examples/tasks.html
#> Device     992 × 1323 @1x · light
#> Recording  off · cursor hidden
pz_get_count(task_list, target = ".task.done")
#> [1] 2

# from_root looks outside the current scope, but still pushes a new scope
task_list |>
  pz_find("#new-task", from_root = TRUE) |>
  pz_act_type("Buy milk", target = "#task-title")
pz_get_value(page, target = "#task-title")
#> [1] "Buy milk"
pz_close(page)
```
