# Stage the default framing

`pz_stage_frame()` stores a default
[`pz_frame()`](https://posit-dev.github.io/paparazzi/reference/pz_frame.md)
on the context: every screenshot and recording started from the staged
context resolves its own `frame =` field by field, and an unset field
takes the staged value if one is set, else the built-in default.
`frame = FALSE` disables framing for a single call. The staged frame
applies to the pipeline the staged context flows through – `pz_find*()`
contexts inherit it – while a fresh pipeline from the original context
starts from the defaults; assign the result
(`page <- page |> pz_stage_frame(...)`) to set page-wide defaults.
`pz_stage_frame(NULL)` clears an inherited staged frame for that
pipeline only, and a new `pz_stage_frame()` call replaces the staged
frame wholesale (unset fields fall back to built-in defaults, they do
not merge with a previously staged frame). Camera shots ignore the
staged frame; see
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
  at the root). A single `NULL` clears the staged frame for this
  pipeline.

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

page <- page |> pz_stage_frame(pad = 24)
# Framed by the default: the form plus 24px of padding
page |> pz_screenshot(path, frame = "#new_task")
# Fields not set here still come from the staged default
page |> pz_screenshot(path, frame = pz_frame("#new_task", ratio = 16/9))
# FALSE turns framing off for one call
page |> pz_screenshot(path, frame = FALSE)
# NULL clears the staged default for this pipeline only
page |> pz_stage_frame(NULL) |> pz_screenshot(path, frame = "#new_task")
pz_close(page)
```
