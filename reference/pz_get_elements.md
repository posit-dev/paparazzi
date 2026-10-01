# Describe matching elements

`pz_get_elements()` returns a summary of every element matching
`target`, one row per match in match order: the lowercased tag name, the
`id` and `class` attributes, and the whitespace-collapsed text. `id` and
`class` are `NA` when the attribute is absent.

## Usage

``` r
pz_get_elements(ctx, target = NULL, ...)
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

A tibble with columns `tag`, `id`, `class`, `text`, one row per match,
plus an `element` list-column of contexts scoped to each match, pinned
at get time (see
[`pz_get_rect()`](https://posit-dev.github.io/paparazzi/reference/pz_get_rect.md)).

## Examples

``` r
page <- pz_open(pz_example("tasks"))
pz_get_elements(page, target = "#new-task > *")
#> # A tibble: 4 × 5
#>   tag   id              class                                     text  element 
#>   <chr> <chr>           <chr>                                     <chr> <list>  
#> 1 label NA              form-label                                New … <pz_ctx>
#> 2 div   NA              d-flex gap-2 mb-2                         Add   <pz_ctx>
#> 3 div   NA              d-flex align-items-center flex-wrap gap-… Low … <pz_ctx>
#> 4 p     attachment-name form-text text-body-secondary small mb-0  No f… <pz_ctx>
pz_close(page)
```
