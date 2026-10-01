# Set or clear the page's default framing

`pz_stage_frame()` stores a default
[`pz_frame()`](https://posit-dev.github.io/paparazzi/reference/pz_frame.md)
on the page. Every screenshot and recording resolves its own `frame =`
field by field: an unset field takes the staged value if one is set,
else the built-in default. `frame = FALSE` disables framing for a single
call. Camera shots ignore the staged frame; see
[`pz_camera()`](https://posit-dev.github.io/paparazzi/reference/pz_camera.md).

Unlike
[`pz_stage()`](https://posit-dev.github.io/paparazzi/reference/pz_stage.md)'s
animation settings, framing (like
[`pz_stage_annotate()`](https://posit-dev.github.io/paparazzi/reference/pz_stage_annotate.md)'s
styles) applies to screenshots as well as recordings. An annotated
staged frame measures attached annotations in stills; recordings use
only its element boxes for the home frame.

## Usage

``` r
pz_stage_frame(
  ctx,
  ...,
  ratio = NULL,
  pad = NULL,
  offset = NULL,
  anchor = NULL,
  bounds = NULL,
  target_box = NULL,
  zoom = NULL
)
```

## Arguments

- ctx:

  A paparazzi context.

- ...:

  The default frame's target: a CSS selector string, a
  [`pz_loc()`](https://posit-dev.github.io/paparazzi/reference/pz_loc.md)
  spec, or a list of either. Several unnamed arguments are unioned. With
  no target, framed captures use the current scope's box (the viewport
  at the root). A single `NULL` clears the default.

- ratio, pad, offset, anchor, bounds, target_box, zoom:

  Framing settings, as in
  [`pz_frame()`](https://posit-dev.github.io/paparazzi/reference/pz_frame.md);
  `NULL` leaves the field unset, so captures fall back to the built-in
  default for it.

## Value

`ctx`, invisibly.

## See also

[`pz_stage()`](https://posit-dev.github.io/paparazzi/reference/pz_stage.md),
[`pz_stage_annotate()`](https://posit-dev.github.io/paparazzi/reference/pz_stage_annotate.md),
[`pz_frame()`](https://posit-dev.github.io/paparazzi/reference/pz_frame.md),
[`pz_screenshot()`](https://posit-dev.github.io/paparazzi/reference/pz_screenshot.md)

## Examples

``` r
page <- pz_open(pz_example("tasks"))
path <- file.path(tempdir(), "tasks.png")

page |>
  pz_stage_frame(pad = 24) |>
  # Framed by the default: the form plus 24px of padding
  pz_screenshot(path, frame = "#new-task") |>
  # Fields not set here still come from the staged default
  pz_screenshot(path, frame = pz_frame("#new-task", ratio = 16/9)) |>
  # FALSE turns framing off for one call
  pz_screenshot(path, frame = FALSE) |>
  # NULL clears the default
  pz_stage_frame(NULL)
pz_screenshot(page, frame = pz_frame("#new-task", pad = 24, ratio = 16/9))
pz_close(page)
```
