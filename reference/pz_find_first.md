# Find the first match and push it as the current scope

`pz_find_first()` is
[`pz_find()`](https://posit-dev.github.io/paparazzi/reference/pz_find.md)
with `which = "first"`. With a `target`, it pins the spec's first match.
Without a `target`, it narrows the current scope to its first element:
one eager slice of the pinned set, with no re-query and no waiting.

## Usage

``` r
pz_find_first(ctx, target = NULL, ..., from_root = FALSE)
```

## Arguments

- ctx:

  A paparazzi context.

- target:

  A CSS selector string or a
  [`pz_loc()`](https://posit-dev.github.io/paparazzi/reference/pz_loc.md)
  spec. `NULL` narrows the current scope; a union can't pick one match
  by position, and a spec that already carries `which` is an error.

- ...:

  Checked empty; reserved for future use.

- from_root:

  Resolve the target from the page root instead of the current scope?
  Requires a `target`.

## Value

A new context.

## See also

[`pz_find()`](https://posit-dev.github.io/paparazzi/reference/pz_find.md),
[`pz_find_last()`](https://posit-dev.github.io/paparazzi/reference/pz_find_last.md),
[`pz_find_nth()`](https://posit-dev.github.io/paparazzi/reference/pz_find_nth.md)

## Examples

``` r
page <- pz_open(pz_example("tasks"))
page |>
  pz_find_first(".task") |>
  pz_get_text(target = ".task-title")
#> [1] "Renew passport"

# Without a target, narrow the current scope to its first element
page |>
  pz_find(".task[data-priority='normal']") |>
  pz_find_first() |>
  pz_get_text(target = ".task-title")
#> [1] "Book dentist appointment"
pz_close(page)
```
