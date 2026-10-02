# Read the HTML of matching elements

`pz_get_html()` returns the outer HTML of every element matching
`target`, one entry per match.

## Usage

``` r
pz_get_html(ctx, target = NULL, ...)
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

## Value

A character vector, one entry per match.

## Examples

``` r
page <- pz_open(pz_example("tasks"))
pz_get_html(page, target = pz_loc(".task", which = "first"))
#> [1] "<li class=\"task list-group-item d-flex align-items-center gap-2\" draggable=\"true\" data-priority=\"high\" data-id=\"1\">\n          <span class=\"task-drag-handle\" aria-hidden=\"true\">⠿</span>\n          <div class=\"flex-grow-1 overflow-hidden\"><span class=\"task-title d-block\">Renew passport</span></div>\n          <button type=\"button\" class=\"task-edit btn btn-sm btn-outline-secondary\">Edit</button>\n          <span class=\"task-priority badge text-bg-danger\">high</span>\n          <button type=\"button\" class=\"task-done btn btn-sm btn-outline-secondary\">Done</button>\n        </li>"
pz_close(page)
```
