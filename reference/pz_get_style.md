# Read computed styles of matching elements

`pz_get_style()` returns the **computed** styles of every element
matching `target` – what the browser actually applied, the same values
Playwright's `toHaveCSS()` and jQuery's `.css()` read – one row per
match in match order. Like all getters it auto-waits for at least one
match.

## Usage

``` r
pz_get_style(ctx, props = NULL, target = NULL, ...)
```

## Arguments

- ctx:

  A paparazzi context.

- props:

  A character vector of CSS property names, or `NULL` for all computed
  properties. With `NULL` the columns are the union of property names
  across matches, first-seen order (standard computed properties are the
  same for every element, but custom properties vary); a match that
  doesn't report a property reads as `""` (empty string).

- target:

  A CSS selector string, a
  [`pz_loc()`](https://posit-dev.github.io/paparazzi/reference/pz_loc.md)
  spec, or a list of specs and strings (a union matching any of them).
  `NULL` means the current context: the pinned set at a scoped context,
  or the page body at the root.

- ...:

  Checked empty; reserved for future use.

## Value

A tibble with one row per match, one character column per property, plus
an `element` list-column: each entry is a context scoped to that one
match, pinned at get time, so a chain can continue from it (see
[`pz_get_rect()`](https://posit-dev.github.io/paparazzi/reference/pz_get_rect.md)).

## Details

Property names accept snake_case, converted to the CSS kebab-case
spelling (`font_size` becomes `font-size`, also the column name, so
select it with `` df$`font-size`  ``); custom properties
(`"--bs-primary"`) pass through unchanged. `props = NULL` returns every
computed property the browser reports (longhands only).

## See also

[`pz_expect_style()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_style.md)

## Examples

``` r
page <- pz_open(pz_example("tasks"))
pz_get_style(page, c("font-size", "font_weight"), target = "h1")
#> # A tibble: 1 × 3
#>   `font-size` `font-weight` element 
#>   <chr>       <chr>         <list>  
#> 1 24px        500           <pz_ctx>

# One row per match
pz_get_style(page, "text-decoration-line", target = ".task-title")
#> # A tibble: 7 × 2
#>   `text-decoration-line` element 
#>   <chr>                  <list>  
#> 1 none                   <pz_ctx>
#> 2 none                   <pz_ctx>
#> 3 none                   <pz_ctx>
#> 4 line-through           <pz_ctx>
#> 5 none                   <pz_ctx>
#> 6 none                   <pz_ctx>
#> 7 none                   <pz_ctx>
pz_close(page)
```
