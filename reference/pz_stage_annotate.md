# Set the page's annotation style defaults

Sets persistent page defaults for new annotations in screenshots and
recordings. An omitted argument leaves its setting alone, an explicit
`NULL` restores its default, and a value sets it. Per-call annotation
style arguments override these defaults; note the per-call names on
[`pz_annotate()`](https://posit-dev.github.io/paparazzi/reference/pz_annotate.md)
differ (`label_fill`/`label_text_color`) from the staged names
(`fill`/`text_color`), and the staged fill and text color style callout
chrome only, not mark badges.

## Usage

``` r
pz_stage_annotate(
  ctx,
  ...,
  color = NULL,
  fill = NULL,
  text_color = NULL,
  stroke_width = NULL,
  distance = NULL,
  font_family = NULL,
  font_size = NULL,
  caption_side = NULL
)
```

## Arguments

- ctx:

  A paparazzi context.

- ...:

  Checked empty; reserved for future use.

- color:

  CSS accent color for new annotations: mark outlines, callout bubble
  borders, leader lines and decorations. The default is `"#e11d48"`.
  Supply `NULL` to restore the default.

- fill:

  CSS background color for new callout bubbles and their badges. The
  default is `"#171717"`. Supply `NULL` to restore the default. Callout
  chrome only:
  [`pz_annotate()`](https://posit-dev.github.io/paparazzi/reference/pz_annotate.md)
  mark badges follow their mark's `color` unless overridden per call
  with `label_fill`.

- text_color:

  CSS text color for new callout bubbles and their badges. The default
  is `"white"`. Supply `NULL` to restore the default. Callout chrome
  only, like `fill`.

- stroke_width:

  Stroke width in CSS pixels for new annotation marks and callout leader
  lines; decoration sizes scale with it. The default is 3. Supply `NULL`
  to restore the default.

- distance:

  Bubble-to-target gap in CSS pixels for new callouts, with or without a
  leader. By default the gap is 24 with a leader and 8 without one.
  Supply `NULL` to restore the default.

- font_family:

  CSS font family for new annotation badges and key callouts. The
  default is `"sans-serif"`. Supply `NULL` to restore the default. A
  font object staged with
  [`pz_stage_fonts()`](https://posit-dev.github.io/paparazzi/reference/pz_stage_fonts.md)
  is also accepted and resolves to its family with a sans-serif
  fallback.

- font_size:

  Badge font size in CSS pixels. The default is 14. Supply `NULL` to
  restore the default.

- caption_side:

  Default side for new
  [`pz_annotate_caption()`](https://posit-dev.github.io/paparazzi/reference/pz_annotate_caption.md)
  captions: `"bottom"` (the default) or `"top"`. Supply `NULL` to
  restore the default.

## Value

`ctx`, invisibly.

## See also

[`pz_stage()`](https://posit-dev.github.io/paparazzi/reference/pz_stage.md),
[`pz_stage_frame()`](https://posit-dev.github.io/paparazzi/reference/pz_stage_frame.md),
[`pz_annotate()`](https://posit-dev.github.io/paparazzi/reference/pz_annotate.md)

## Examples

``` r
page <- pz_open(pz_example("tasks"))
path <- file.path(tempdir(), "tasks.png")

page |>
  # New annotations on this page use these styles
  pz_stage_annotate(color = "#2563eb", font_size = 16) |>
  pz_annotate("#add-task", label = TRUE) |>
  pz_screenshot(path) |>
  # NULL restores a default
  pz_stage_annotate(color = NULL)
pz_screenshot(page, frame = pz_frame("#new-task", pad = 16, target_box = "annotated"))
pz_close(page)
```
