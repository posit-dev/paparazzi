# Take a screenshot

Captures a PNG of the page. With an explicit `path`, returns the context
invisibly so screenshots slot into `|>` chains. Without a path, the
capture is a terminal step: a figure in a knitted document or a
printable preview in an interactive session.

The captured region comes from `frame`:

- `NULL` (the default): the page's staged framing set with
  [`pz_stage_frame()`](https://posit-dev.github.io/paparazzi/reference/pz_stage_frame.md),
  or, with none staged, the current scope's box (the viewport at the
  root), unframed.

- A
  [`pz_frame()`](https://posit-dev.github.io/paparazzi/reference/pz_frame.md)
  spec, or a bare locator promoted to one: a CSS selector string, a
  [`pz_loc()`](https://posit-dev.github.io/paparazzi/reference/pz_loc.md)
  spec, or a list of either, framing the union of the matched elements'
  bounding boxes. A selector matching several elements is a union, not
  an error. Fields the spec leaves unset inherit the staged value, then
  the built-in default.

- `FALSE`: the scope's box or viewport, unframed.

What a frame without its own target measures resolves by precedence: the
scope (scoped contexts), then the staged frame's target, then the
viewport.

Screenshots are captured at the page's current device pixel ratio: the
PNG's pixel dimensions are the captured CSS size multiplied by the dpr.

A screen-space caption set with
[`pz_annotate_caption()`](https://posit-dev.github.io/paparazzi/reference/pz_annotate_caption.md)
is composited onto the captured PNG after framing; captioned stills
require png.

## Usage

``` r
pz_screenshot(ctx, path = NULL, ..., frame = NULL)
```

## Arguments

- ctx:

  A paparazzi context.

- path:

  File path the PNG is written to; an existing file is overwritten. With
  `NULL` (the default) while knitting, a numbered file in the chunk's
  figure directory is used and included in the document; in an
  interactive session, a temporary PNG is shown when the result is
  printed. In pkgdown examples, the temporary PNG is embedded in the
  reference page. A path is required otherwise. In a document, end the
  pipe with `pz_screenshot()` to include it; give intermediate
  screenshots a path to keep chaining.

- ...:

  Checked empty; reserved for future use.

- frame:

  What to capture and how to frame it: a
  [`pz_frame()`](https://posit-dev.github.io/paparazzi/reference/pz_frame.md)
  spec or a bare locator (a CSS selector string, a
  [`pz_loc()`](https://posit-dev.github.io/paparazzi/reference/pz_loc.md)
  spec, or a list of either) promoted to one; `NULL` (the default) uses
  the staged framing, if any; `FALSE` captures the scope's box or
  viewport unframed.

## Value

With an explicit path, `ctx`, invisibly. Without a path while knitting,
a knitr image; without a path in an interactive session or in pkgdown
examples, an image preview. These image results are terminal, not
contexts.

## See also

[`pz_frame()`](https://posit-dev.github.io/paparazzi/reference/pz_frame.md),
[`pz_stage_frame()`](https://posit-dev.github.io/paparazzi/reference/pz_stage_frame.md)

## Examples

``` r
page <- pz_open(pz_example("tasks"))
path <- file.path(tempdir(), "tasks.png")

# At the root, frame = NULL captures the viewport
page |> pz_screenshot(path)

# A locator captures its box; a list captures the union of the boxes
page |> pz_screenshot(path, frame = ".task-list")
page |> pz_screenshot(path, frame = list("#new-task", ".filters"))

# Padding, aspect ratio and anchoring come from pz_frame()
page |> pz_screenshot(path, frame = pz_frame("#new-task", pad = 16))
file.exists(path)
#> [1] TRUE
pz_screenshot(page, frame = pz_frame("#new-task", pad = 16))
pz_close(page)
```
