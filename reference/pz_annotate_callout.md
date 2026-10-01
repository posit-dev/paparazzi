# Add text callouts to page elements

Draws one callout per matching element, repeating `text` for every
match. Callouts follow their targets during scrolling and layout
changes, and appear in screenshots and recordings until cleared with
[`pz_annotate_clear()`](https://posit-dev.github.io/paparazzi/reference/pz_annotate_clear.md).
They belong to the current document and disappear on navigation. A
bubble is kept within the viewport even if this moves it away from the
requested side; text that cannot fit a tiny viewport is clipped. A
viewport resize does not rewrap an existing callout. A callout hides
while its target isn't rendered, is `visibility: hidden` with no visible
descendants, or is entirely clipped by an overflow container. When the
target is partly clipped, the leader points at its visible part; the
bubble itself is never clipped.

## Usage

``` r
pz_annotate_callout(
  ctx,
  text,
  ...,
  target = NULL,
  side = NULL,
  leader = TRUE,
  label = NULL,
  reveal = c("pop", "fade", "draw", "slide", "wipe", "none"),
  id = NULL,
  color = NULL,
  fill = NULL,
  text_color = NULL,
  stroke_width = NULL,
  distance = NULL,
  font_family = NULL,
  font_size = NULL
)
```

## Arguments

- ctx:

  A paparazzi context.

- text:

  One nonempty string of literal text (not HTML).

- ...:

  Checked empty; reserved for future use.

- target:

  A selector,
  [`pz_loc()`](https://posit-dev.github.io/paparazzi/reference/pz_loc.md)
  spec, or list of targets. `NULL` uses the current scope, or
  `document.body` at the root.

- side:

  A side (`"top"`, `"right"`, `"bottom"`, `"left"`) or a diagonal corner
  such as `"top right"`. `NULL` chooses the cardinal side with the most
  room when drawn. The chosen side stays fixed.

- leader:

  The line between the bubble and the target. `TRUE` (the default) draws
  a line with an arrow at the target, equal to
  `c(start = "none", end = "arrow")`; `FALSE` draws no line, leaving a
  tooltip-style bubble. A named character vector sets a decoration for
  each end: `start` is the bubble side, `end` is the target side, and an
  omitted name defaults to `"none"`. Decoration values are `"none"`,
  `"arrow"` (a filled triangle), `"dot"`, or `"bar"` (a perpendicular
  tick). The shaft stops at each decoration's base, and short leaders
  shrink the decorations.

- label:

  Optional badge; `TRUE` numbers the matches, while one string or number
  repeats for each match. `NULL` omits the badge.

- reveal:

  `"pop"` (the default), `"fade"`, `"draw"`, `"slide"`, `"wipe"`, or
  `"none"`. Animates only during an active, unpaused recording; clearing
  plays the reverse. `"draw"` draws the leader's shaft, then shows its
  decorations.

- id:

  Optional nonempty id. Reusing it replaces its annotations; `NULL`
  generates a unique id, so calls accumulate annotations. `"spotlight"`
  and `"caption"` are reserved for other types.

- color:

  Accent color for the bubble border, leader line and decorations;
  `NULL` uses the staged annotation color.

- fill, text_color:

  CSS colors for the bubble background and text (and the callout's
  badge); `NULL` uses the staged `fill`/`text_color` from
  [`pz_stage_annotate()`](https://posit-dev.github.io/paparazzi/reference/pz_stage_annotate.md),
  falling back to `"#171717"` on `"white"`.
  [`pz_annotate()`](https://posit-dev.github.io/paparazzi/reference/pz_annotate.md)
  mark badges do not use these; they follow their mark's `color` unless
  overridden per call with `label_fill`/`label_text_color`.

- stroke_width:

  Leader line width in CSS pixels, or `NULL` for the staged
  `stroke_width` from
  [`pz_stage_annotate()`](https://posit-dev.github.io/paparazzi/reference/pz_stage_annotate.md).
  Decoration sizes scale with it. Shared with
  [`pz_annotate()`](https://posit-dev.github.io/paparazzi/reference/pz_annotate.md)
  marks.

- distance:

  Bubble-to-target gap in CSS pixels, or `NULL` for the staged
  `distance` from
  [`pz_stage_annotate()`](https://posit-dev.github.io/paparazzi/reference/pz_stage_annotate.md).
  Without either, the gap is 24 with a leader and 8 without one.

- font_family:

  CSS font family; `NULL` uses the staged default. A font object staged
  with
  [`pz_stage_fonts()`](https://posit-dev.github.io/paparazzi/reference/pz_stage_fonts.md)
  is also accepted and resolves to its family with a sans-serif
  fallback.

- font_size:

  Font size in CSS pixels; `NULL` uses the staged default.

## Value

`ctx`, invisibly.

## See also

[`pz_annotate()`](https://posit-dev.github.io/paparazzi/reference/pz_annotate.md),
[`pz_annotate_clear()`](https://posit-dev.github.io/paparazzi/reference/pz_annotate_clear.md)
