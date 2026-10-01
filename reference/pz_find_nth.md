# Find the nth match and push it as the current scope

`pz_find_nth()` is
[`pz_find()`](https://posit-dev.github.io/paparazzi/reference/pz_find.md)
with `which = n`. With a `target`, it pins the spec's `n`th match; an
out-of-range `n` means no match, so the call keeps auto-waiting like any
[`pz_loc()`](https://posit-dev.github.io/paparazzi/reference/pz_loc.md)
resolution. Without a `target`, it narrows the current scope to its
`n`th element: one eager slice of the pinned set, and an out-of-range
`n` errors immediately – the set was fixed at pin time, so there is
nothing to wait for.

## Usage

``` r
pz_find_nth(ctx, n, target = NULL, ..., from_root = FALSE)
```

## Arguments

- ctx:

  A paparazzi context.

- n:

  The match to pick, 1-based (`"first"`/`"last"` are the
  [`pz_find_first()`](https://posit-dev.github.io/paparazzi/reference/pz_find_first.md)/[`pz_find_last()`](https://posit-dev.github.io/paparazzi/reference/pz_find_last.md)
  wrappers, not values here).

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
[`pz_find_first()`](https://posit-dev.github.io/paparazzi/reference/pz_find_first.md),
[`pz_find_last()`](https://posit-dev.github.io/paparazzi/reference/pz_find_last.md)

## Examples

``` r
page <- pz_open(pz_example("tasks"))

# Mark the second task as done
page |>
  pz_find_nth(2, target = ".task") |>
  pz_act_click(".task-done")
pz_get_text(page, target = pz_loc(".task.done .task-title"))
#> [1] "File tax return"      "Return library books"
pz_close(page)
```
