# Add a screen-space caption

A caption stays on the page until replaced or cleared with
[pz_annotate_clear(id =
"caption")](https://posit-dev.github.io/paparazzi/reference/pz_annotate_clear.md).
It persists through navigation and across recordings, and appears on
stills. In a recording, a caption fades out when it is cleared or
replaced; one that is still showing at
[`pz_record_stop()`](https://posit-dev.github.io/paparazzi/reference/pz_record_stop.md)
stays on through the last frame.

## Usage

``` r
pz_annotate_caption(
  ctx,
  text,
  ...,
  side = NULL,
  color = "white",
  font_family = NULL,
  font_size = 20
)
```

## Arguments

- ctx:

  A paparazzi context.

- text:

  Nonempty caption text. Newlines are preserved.

- ...:

  Checked empty.

- side:

  Placement: `"top"` or `"bottom"` (the default). `NULL` (the default)
  uses the staged `caption_side` from
  [`pz_stage_annotate()`](https://posit-dev.github.io/paparazzi/reference/pz_stage_annotate.md)
  (initially `"bottom"`).

- color:

  Text color; defaults to `"white"`, independent of the staged
  annotation accent.

- font_family:

  CSS font family. `NULL` uses the page's `font_family` setting in
  [`pz_stage_annotate()`](https://posit-dev.github.io/paparazzi/reference/pz_stage_annotate.md)
  (initially sans-serif). A font object staged with
  [`pz_stage_fonts()`](https://posit-dev.github.io/paparazzi/reference/pz_stage_fonts.md)
  is also accepted and resolves to its family with a sans-serif
  fallback.

- font_size:

  Font size in CSS pixels; defaults to 20, independent of the annotation
  badge size. Captions scale with the output.

## Value

`ctx`, invisibly.

## See also

[`pz_annotate_clear()`](https://posit-dev.github.io/paparazzi/reference/pz_annotate_clear.md),
[`pz_record_start()`](https://posit-dev.github.io/paparazzi/reference/pz_record_start.md),
[`pz_screenshot()`](https://posit-dev.github.io/paparazzi/reference/pz_screenshot.md)
