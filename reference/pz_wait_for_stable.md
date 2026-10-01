# Wait until an element stops changing

Samples the `prop` property of every element matching `target` (or the
current context) until the sampled value has held still for `for_ms`
milliseconds: text has stopped arriving, or an animation has come to
rest. `prop = "rect"` samples the bounding box instead of a property,
rounded to whole pixels.

## Usage

``` r
pz_wait_for_stable(
  ctx,
  ...,
  target = NULL,
  prop = "textContent",
  for_ms = 500,
  timeout = NULL
)
```

## Arguments

- ctx:

  A paparazzi context.

- ...:

  Checked empty; reserved for future use.

- target:

  A CSS selector string, a
  [`pz_loc()`](https://posit-dev.github.io/paparazzi/reference/pz_loc.md)
  spec, or a list of specs and strings (a union matching any of them).
  `NULL` means the current context: the pinned set at a scoped context,
  the page body at the root.

- prop:

  The element property to sample: any single JavaScript property name
  (`"textContent"`, `"value"`, `"scrollTop"`, ...), or `"rect"` for the
  bounding box.

- for_ms:

  Milliseconds the sampled value must hold still before the wait passes.

- timeout:

  Seconds before giving up; `NULL` uses the session default.

## Value

`ctx`, invisibly.

## Details

The wait first waits (up to `timeout`) for `target` to match, then
samples within a second, separate `timeout` budget of its own: a target
that appears near the locator deadline still gets its full `for_ms`
window.

There is deliberately no element-state wait:
[`pz_expect_visible()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_visible.md),
[`pz_expect_hidden()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_visible.md),
and
[`pz_expect_exists()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_exists.md)
with `not = TRUE` already retry, so they wait.

## See also

[`pz_wait_for_js()`](https://posit-dev.github.io/paparazzi/reference/pz_wait_for_js.md),
[`pz_wait_for_navigation()`](https://posit-dev.github.io/paparazzi/reference/pz_wait_for_navigation.md)

## Examples

``` r
page <- pz_open(pz_example("tasks"))

# The status line reads "Saving..." and then "Saved"; wait for it to settle
page |>
  pz_act_type("Buy milk", target = "#task-title") |>
  pz_act_click("#add-task") |>
  pz_wait_for_stable(target = "#status", for_ms = 500)
pz_get_text(page, target = "#status")
#> [1] "Saved “Buy milk”."
pz_close(page)
```
