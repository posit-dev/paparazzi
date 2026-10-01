# Frame a capture region

`pz_frame()` builds a lazy framing spec for a capture: the region is
computed at capture time, then padded, nudged, grown to an aspect ratio,
and clamped. Every capture takes one: screenshots through
`pz_screenshot(frame =)`, recordings through `pz_record_start(frame =)`,
and camera shots through `pz_camera(frame =)`. Wherever a frame is
accepted, a bare locator (a CSS selector string, a
[`pz_loc()`](https://posit-dev.github.io/paparazzi/reference/pz_loc.md)
spec, or a list of either) is promoted to `pz_frame(<locator>)`.

Every field defaults to `NULL`, meaning "inherit": at capture time an
unset field takes the
[`pz_stage_frame()`](https://posit-dev.github.io/paparazzi/reference/pz_stage_frame.md)
value if one is staged, else the built-in default. The built-in defaults
are `pad = 0`, `offset = c(0, 0)`, `anchor = "center"`, `when = "stop"`,
and `target_box = "element"`, with `ratio`, `bounds`, `zoom`, and
`target` unset. Camera shots never inherit the staged frame; their
built-in defaults are `pad = 24` and `target_box = "element"`.

The framed region is computed in this order:

1.  Union the bounding boxes of the target's matched elements. With
    `target_box = "annotated"`, include their attached annotations.

2.  Expand by `pad`.

3.  With `zoom = NULL`, shift by `offset`, then grow the shorter side to
    reach `ratio` (never shrink), placing the content by `anchor`. With
    a numeric `zoom`, the region is the view divided by `zoom` (the
    viewport for stills and recordings, the recording's home frame for
    camera shots), with `ratio` setting its aspect if given; the padded
    target is placed inside it by `anchor`, then shifted by `offset`.

4.  Clamp to `bounds` and to the page's rendered area.

5.  Round to whole pixels.

## Usage

``` r
pz_frame(
  target = NULL,
  ...,
  ratio = NULL,
  pad = NULL,
  offset = NULL,
  anchor = NULL,
  bounds = NULL,
  when = NULL,
  target_box = NULL,
  zoom = NULL
)
```

## Arguments

- target:

  The element(s) the frame is computed from: a CSS selector string, a
  [`pz_loc()`](https://posit-dev.github.io/paparazzi/reference/pz_loc.md)
  spec, or a list of either (the frame is the union of the matched
  elements' bounding boxes). `NULL` frames the current scope's box, or
  the viewport at the root.

- ...:

  Checked empty; reserved for future use.

- ratio:

  Width/height ratio for the region, e.g. `16/9`. `NULL` disables
  aspect-ratio expansion, keeping the region tight to its content.
  Ignored (with a warning) by camera shots.

- pad:

  Padding in CSS pixels: one number for all sides, or
  `c(top, right, bottom, left)`. Negative values crop inside the content
  box.

- offset:

  Nudge the region by `c(x, y)` pixels, applied after `pad`.

- anchor:

  Where the content sits while the region grows around it: `"center"`, a
  side (`"top"`, `"bottom"`, `"left"`, `"right"`), or a corner
  (`"top left"`, `"top right"`, `"bottom left"`, `"bottom right"`).
  Case-insensitive; `"top right"`, `"right top"`, and `"top-right"` are
  equivalent.

- bounds:

  A target (a CSS selector string, a
  [`pz_loc()`](https://posit-dev.github.io/paparazzi/reference/pz_loc.md)
  spec, or a list of either) whose union box the region is clamped
  within. `NULL` adds no bounds target; the page's rendered area still
  limits the region.

- when:

  When a recording measures the frame: `"stop"` (the default) measures
  against the final layout; `"start"` clips at capture start.
  Screenshots ignore this; camera shots warn.

- target_box:

  `"element"` (the default) measures only matched elements.
  `"annotated"` also includes painted marks, callouts, and spotlight
  cutouts attached to those elements or their descendants; redactions
  and annotations on unrelated elements are excluded. Applies to stills
  and camera shots, not the recording's home frame.

- zoom:

  Magnification relative to the full view (the viewport for stills and
  recordings, the recording's home frame for camera shots). `NULL` fits
  the region to the target plus `pad`, grown to `ratio`. A number fixes
  the region size at the view divided by `zoom`; `anchor` places the
  padded target inside it. Stills crop only, never upscale: a zoomed
  still is a smaller PNG at the page's pixel ratio. The camera caps a
  fitted shot at the capture's pixel density; an explicit `zoom` past it
  warns at encode time.

## Value

An S3 object of class `paparazzi_frame`.

## Examples

``` r
# Frames are specs: nothing is measured until a capture uses them
pz_frame(pad = 32)
#> <paparazzi_frame> target: <scope>, pad: 32 32 32 32
pz_frame(ratio = 16/9, pad = 24, anchor = "top")
#> <paparazzi_frame> target: <scope>, ratio: 1.77777777777778, pad: 24 24 24 24, anchor: top
pz_frame(".task-list", ratio = 4/3, bounds = "main")
#> <paparazzi_frame> target: `.task-list`, ratio: 1.33333333333333, bounds: `main`

page <- pz_open(pz_example("tasks"))
path <- file.path(tempdir(), "tasks.png")

# A locator target frames the union of its boxes
page |> pz_screenshot(path, frame = pz_frame(list("h1", ".filters"), pad = 16))

# Unset fields inherit the staged framing
page |>
  pz_stage_frame(pad = 16) |>
  pz_screenshot(path, frame = pz_frame("#new-task", ratio = 16/9))
pz_screenshot(page, frame = pz_frame("#new-task", ratio = 16/9))
pz_close(page)
```
