# Evaluate JavaScript in the page

Evaluates `expr` in the page, optionally awaiting a returned promise,
and returns the resulting value. This is the primitive all element work
uses, and an escape hatch for one-off scripts. Unlike most `pz_*()`
functions it **ends the chain**: it returns the value, not the context.

## Usage

``` r
pz_js(ctx, expr, ..., await = TRUE, timeout = NULL)
```

## Arguments

- ctx:

  A paparazzi context.

- expr:

  A string of JavaScript to evaluate.

- ...:

  Checked empty; reserved for future use.

- await:

  Await a promise returned by `expr` before returning its value.

- timeout:

  Seconds before the evaluation fails; `NULL` uses the session default.

## Value

The value produced by `expr` (converted to R), or `NULL`.

## Examples

``` r
page <- pz_open(pz_example("tasks"))
pz_js(page, "document.querySelectorAll('.task').length")
#> [1] 7

# Arrays come back as lists
pz_js(page, "[...document.querySelectorAll('.task-priority')].map(el => el.textContent)")
#> [[1]]
#> [1] "high"
#> 
#> [[2]]
#> [1] "high"
#> 
#> [[3]]
#> [1] "normal"
#> 
#> [[4]]
#> [1] "low"
#> 
#> [[5]]
#> [1] "normal"
#> 
#> [[6]]
#> [1] "low"
#> 
#> [[7]]
#> [1] "normal"
#> 

# Returned promises are awaited
pz_js(page, "new Promise(resolve => setTimeout(() => resolve('done'), 100))")
#> [1] "done"
pz_close(page)
```
