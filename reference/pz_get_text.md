# Read the text of matching elements

`pz_get_text()` returns the `textContent` of every element matching
`target`, one entry per match. By default runs of whitespace are
collapsed to single spaces and trimmed, matching
[`pz_expect_text()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_text.md);
`raw = TRUE` returns the text exactly as the browser holds it.

## Usage

``` r
pz_get_text(ctx, target = NULL, ..., raw = FALSE)
```

## Arguments

- ctx:

  A paparazzi context.

- target:

  A CSS selector string, a
  [`pz_loc()`](https://posit-dev.github.io/paparazzi/reference/pz_loc.md)
  spec, or a list of specs and strings (a union matching any of them).
  `NULL` means the current context: the pinned set at a scoped context,
  or the page body at the root.

- ...:

  Checked empty; reserved for future use.

- raw:

  Return the text without collapsing whitespace?

## Value

A character vector, one entry per match.

## Examples

``` r
page <- pz_open(pz_example("tasks"))
pz_get_text(page, target = "h1")
#> [1] "Tasks"

# One string per match
pz_get_text(page, target = ".task[data-priority='high'] .task-title")
#> [1] "Renew passport"  "File tax return"

# Whitespace is collapsed unless raw = TRUE
pz_get_text(page, target = "#help")
#> [1] "Type a task and press Enter to add it. Edit a title, mark a task done, or drag tasks to reorder them. Nothing is saved: reload or Start over resets the list."
pz_get_text(page, target = "#help", raw = TRUE)
#> [1] "\n        Type a task and press Enter to add it. Edit a title, mark a task done, or drag tasks to reorder them.\n        Nothing is saved: reload or Start over resets the list.\n      "
pz_close(page)
```
