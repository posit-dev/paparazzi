# Mark page elements

Draws an annotation for each element matched by `target`. Annotations
follow their elements as the page scrolls or changes layout, and appear
in screenshots and recordings until cleared with
[`pz_annotate_clear()`](https://posit-dev.github.io/paparazzi/reference/pz_annotate_clear.md).
Annotations belong to the current document; navigating away removes
them. Marks and their badges are clipped by the target's overflow
containers (axis-aligned clipping only, not a custom
`overflow-clip-margin`). On sides where the target is not cut off, the
clip leaves room for the mark's `pad` so its outline stays intact. A
mark hides while its target is disconnected, not rendered,
`visibility: hidden` with no visible descendants, or entirely clipped,
even if its padding would reach into view. Zero-size targets on a
clipping edge also stay hidden.

## Usage

``` r
pz_annotate(
  ctx,
  target = NULL,
  ...,
  type = "box",
  label = NULL,
  pad = 0,
  reveal = c("auto", "fade", "draw", "pop", "slide", "wipe", "none"),
  id = NULL,
  color = NULL,
  label_fill = NULL,
  label_text_color = NULL,
  stroke_width = NULL,
  font_family = NULL,
  font_size = NULL
)
```

## Arguments

- ctx:

  A paparazzi context.

- target:

  A selector,
  [`pz_loc()`](https://posit-dev.github.io/paparazzi/reference/pz_loc.md)
  spec, or list of targets. `NULL` uses the current scope, or
  `document.body` at the root.

- ...:

  Checked empty; reserved for future use.

- type:

  `"box"` (outline), `"circle"` (ellipse), `"underline"` (bottom
  stroke), or `"highlight"` (translucent fill blended over the page).

- label:

  Optional badge. `TRUE` numbers the matches 1, 2, ...; one string or
  number repeats on each match. `NULL` omits the badge.

- pad:

  Extra CSS pixels around each element: one number or
  `c(top, right, bottom, left)`. Defaults to zero.

- reveal:

  `"auto"` (the default) uses `"fade"` for boxes and `"draw"` for other
  types. Other choices are `"fade"`, `"draw"`, `"pop"`, `"slide"`,
  `"wipe"`, or `"none"`. Reveals animate only during an active, unpaused
  recording; clearing reverses the reveal. Wipe sweeps clockwise from 12
  o'clock.

- id:

  Optional nonempty id. Reusing it replaces its annotations; `NULL`
  generates a unique id, so calls accumulate annotations. `"spotlight"`
  and `"caption"` are reserved for other types.

- color:

  CSS accent color for the mark outline, or `NULL` for the page default
  from
  [`pz_stage_annotate()`](https://posit-dev.github.io/paparazzi/reference/pz_stage_annotate.md).

- label_fill, label_text_color:

  CSS colors for the badge background and text. `NULL` (the default)
  fills the badge with the mark's `color` and uses white text. The
  `fill` and `text_color` set by
  [`pz_stage_annotate()`](https://posit-dev.github.io/paparazzi/reference/pz_stage_annotate.md)
  style callouts, not mark badges.

- stroke_width:

  Mark stroke width in CSS pixels, or `NULL` for the staged
  `stroke_width` from
  [`pz_stage_annotate()`](https://posit-dev.github.io/paparazzi/reference/pz_stage_annotate.md).

- font_family:

  CSS font family for the badge, or `NULL` for the page default. A font
  object staged with
  [`pz_stage_fonts()`](https://posit-dev.github.io/paparazzi/reference/pz_stage_fonts.md)
  is also accepted and resolves to its family with a sans-serif
  fallback.

- font_size:

  Badge font size in CSS pixels, or `NULL` for the page default.

## Value

`ctx`, invisibly.

## See also

[`pz_annotate_clear()`](https://posit-dev.github.io/paparazzi/reference/pz_annotate_clear.md),
[`pz_stage_annotate()`](https://posit-dev.github.io/paparazzi/reference/pz_stage_annotate.md)
