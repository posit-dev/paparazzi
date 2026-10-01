# Wait for a navigation to finish

The explicit wait after an action that navigates – a clicked link, a
submitted form, a JS redirect. Paparazzi never detects navigations on
its own, so a wait marks exactly where one is expected. Call it
immediately after the action. It waits for the new document to finish
loading and then hold still for a moment. Three cases pass:

## Usage

``` r
pz_wait_for_navigation(
  ctx,
  ...,
  wait = c("auto", "load", "shiny", "none"),
  timeout = NULL
)
```

## Arguments

- ctx:

  A paparazzi context.

- ...:

  Checked empty; reserved for future use.

- wait:

  What to wait for: `"load"` settles the navigation; `"shiny"` also
  waits for Shiny idle after load. `"auto"` uses `"shiny"` only when the
  page was opened on an app handle or app path and lands on that app's
  origin; otherwise it uses `"load"`. `"none"` skips settling and only
  resets the scope.

- timeout:

  Seconds before giving up; `NULL` uses the session default.

## Value

`ctx`, invisibly, with the scope reset to the root.

## Details

- the navigation finished before the wait started: the current document
  differs from the document where the preceding action began (including
  a page restored from the back/forward cache);

- the navigation is in flight when the wait starts, and is waited out;

- the navigation begins while the wait is running. One scheduled beyond
  the timeout can't be caught – block on its trigger with
  [`pz_wait_for_js()`](https://posit-dev.github.io/paparazzi/reference/pz_wait_for_js.md)
  first.

A page where nothing navigates times out with a classed error rather
than passing, and so does a second wait after the same action: a
successful wait uses up the action's navigation.

On success the wait resets the scope to the root and releases every
pinned scope object: contexts scoped before the navigation error on
their next use instead of acting on a stale set.

## See also

[`pz_find_reset()`](https://posit-dev.github.io/paparazzi/reference/pz_find_reset.md),
[`pz_wait_for_js()`](https://posit-dev.github.io/paparazzi/reference/pz_wait_for_js.md),
[`pz_wait_for_stable()`](https://posit-dev.github.io/paparazzi/reference/pz_wait_for_stable.md)

## Examples

``` r
page <- pz_open(pz_example("tasks"))
page |> pz_act_click(pz_loc(".task-done", within = pz_loc(".task", has_text = "bank")))
pz_get_count(page, target = ".task.done")
#> [1] 2

# "Start over" is a link to a new copy of the page
page |>
  pz_act_click("#start-over") |>
  pz_wait_for_navigation()
pz_get_count(page, target = ".task.done")
#> [1] 1
pz_close(page)
```
