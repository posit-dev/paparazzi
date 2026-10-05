# Navigate the page

`pz_nav_goto()` navigates to `url`; `pz_nav_reload()` reloads the page;
`pz_nav_back()`/`pz_nav_forward()` step through the history.

Every navigation resets the scope to the root: the returned context has
an empty scope stack, and the pinned scope objects are released, so a
context scoped **before** the navigation raises a detach error if used
afterwards – re-scope with
[`pz_find()`](https://posit-dev.github.io/paparazzi/reference/pz_find.md)
on the returned root context. Session-level state (timeout, staging, and
recording) is untouched.

## Usage

``` r
pz_nav_goto(ctx, url, ..., wait = c("auto", "load", "shiny", "none"))

pz_nav_reload(ctx, ..., wait = c("auto", "load", "shiny", "none"))

pz_nav_back(ctx, ...)

pz_nav_forward(ctx, ...)
```

## Arguments

- ctx:

  A paparazzi context.

- url:

  The URL to navigate to (any scheme, including `file://`).

- ...:

  Checked empty; reserved for future use.

- wait:

  What to wait for before returning: `"load"` waits for the document to
  finish loading; `"shiny"` also waits for Shiny idle. `"auto"` (the
  default) uses `"shiny"` when the page was opened on an app handle or
  app path and lands on that app's origin, `"load"` otherwise. `"none"`
  returns without settling. `pz_nav_back()` and `pz_nav_forward()` take
  no `wait`: they wait for load only, and return at once at a history
  boundary, where nothing navigates. A Shiny page restored from the
  back/forward cache may not reconnect, so they don't wait for Shiny;
  call
  [`pz_wait_for_shiny_idle()`](https://posit-dev.github.io/paparazzi/reference/pz_wait_for_shiny_idle.md)
  if you need it.

## Value

The root context, invisibly.

## See also

[`pz_find_reset()`](https://posit-dev.github.io/paparazzi/reference/pz_find_reset.md)
for scope-only resets (no navigation).

## Examples

``` r
page <- pz_open(pz_example("tasks"))
url <- pz_get_url(page)

# The filter links change the URL fragment, so each filter is a history entry
page |> pz_nav_goto(paste0(url, "#done"))
pz_get_count(page, target = ".task:not(.hidden)")
#> [1] 1

page |> pz_nav_back()
pz_get_count(page, target = ".task:not(.hidden)")
#> [1] 7

page |> pz_nav_forward()
pz_get_url(page)
#> [1] "http://127.0.0.1:4896/tasks.html#done"

# Reloading keeps the URL, fragment included
page |> pz_nav_reload()
pz_get_url(page)
#> [1] "http://127.0.0.1:4896/tasks.html#done"
pz_close(page)
```
