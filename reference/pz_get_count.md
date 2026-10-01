# Count matching elements

`pz_get_count()` returns the number of elements matching `target`,
counted inside the current scope. Unlike the other getters it doesn't
wait for a match: `0` is a valid answer, so it resolves once and returns
immediately. One exception: on a scope whose pinned elements have left
the page it raises `paparazzi_error_detached` instead of returning `0`,
because the pinned set promises a live set and is never silently
re-queried.

## Usage

``` r
pz_get_count(ctx, target = NULL, ...)
```

## Arguments

- ctx:

  A paparazzi context.

- target:

  A CSS selector string, a
  [`pz_loc()`](https://posit-dev.github.io/paparazzi/reference/pz_loc.md)
  spec, or a list of specs and strings (a union matching any of them).
  `NULL` means the current context: the pinned set at a scoped context,
  whose count comes back without a re-query, or the page body at the
  root.

- ...:

  Checked empty; reserved for future use.

## Value

An integer.

## Examples

``` r
page <- pz_open(pz_example("tasks"))
pz_get_count(page, target = ".task")
#> [1] 7

# Zero is an answer, so pz_get_count() never waits
pz_get_count(page, target = ".error-message")
#> [1] 0

# Counts are relative to the current scope
page |>
  pz_find(".task-list") |>
  pz_get_count(target = ".task.done")
#> [1] 1
pz_close(page)
```
