# Open a page that closes when a block or calling frame exits

`pz_with_page()` evaluates `code` with the page open and closes it on
exit, including on error. `pz_local_page()` opens a page and closes it
when the calling frame (e.g. a test) exits, via
[`withr::defer()`](https://withr.r-lib.org/reference/defer.html). Both
accept an already-open page or anything
[`pz_open()`](https://posit-dev.github.io/paparazzi/reference/pz_open.md)
accepts, and always close on exit: the block owns the resource.

## Usage

``` r
pz_with_page(x, code, ...)

pz_local_page(x, ..., .env = caller_env())
```

## Arguments

- x:

  An open page, or anything
  [`pz_open()`](https://posit-dev.github.io/paparazzi/reference/pz_open.md)
  accepts.

- code:

  Code to run while the page is open. An expression (evaluated as-is;
  useful when `x` is an already-open page the code can reference) or a
  function, called with the page as its only argument. A braced
  [`{ }`](https://rdrr.io/r/base/Paren.html) block is always treated as
  an expression, even if it returns a function.

- ...:

  Passed to
  [`pz_open()`](https://posit-dev.github.io/paparazzi/reference/pz_open.md)
  when `x` is not already a page.

- .env:

  The frame whose exit closes the page.

## Value

`pz_with_page()` returns the page invisibly; `pz_local_page()` returns
it visibly.

## Examples

``` r
path <- file.path(tempdir(), "task-list.png")

# The page closes when the function returns, even if it errors
pz_with_page(pz_example("tasks"), function(page) {
  pz_screenshot(page, path, frame = ".task-list")
})
file.exists(path)
#> [1] TRUE

# pz_local_page() ties the page to the calling function, e.g. a test
count_tasks <- function() {
  page <- pz_local_page(pz_example("tasks"))
  pz_get_count(page, target = ".task")
}
count_tasks()
#> [1] 7
```
