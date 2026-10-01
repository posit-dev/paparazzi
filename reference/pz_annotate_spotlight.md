# Spotlight page elements

Dims the page except for a rounded cutout around each matched element.
The scrim covers the document, including below-fold areas captured in
screenshots. The spotlight follows its elements through scrolling and
layout changes. Disconnected or zero-size elements lose their cutouts,
and so do `visibility: hidden` elements with no visible descendants.
Cutouts are clipped by the target's overflow containers (axis-aligned
clipping only, not a custom `overflow-clip-margin`), so a target
scrolled out of a scrolling container gets no cutout. It appears in
screenshots and recordings until cleared, and is lost on navigation.
Only one spotlight exists per page: a new call replaces the previous
one, and
[`pz_annotate_clear()`](https://posit-dev.github.io/paparazzi/reference/pz_annotate_clear.md)
removes it by the reserved id `"spotlight"` or with a clear-all call.
The cutout covers each target's padded border box; overflowing
descendants and top-layer dialogs/popovers are not covered.

## Usage

``` r
pz_annotate_spotlight(
  ctx,
  target = NULL,
  ...,
  pad = 0,
  dim = 0.6,
  reveal = c("fade", "none")
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

- pad:

  Extra CSS pixels around each element: one number or
  `c(top, right, bottom, left)`. Defaults to zero.

- dim:

  Opacity of the black overlay outside the cutouts, from 0 (transparent)
  to 1 (black). Defaults to 0.6.

- reveal:

  `"fade"` (default) or `"none"`. A fade plays only during an active,
  unpaused recording, and reverses on clear. Otherwise drawing and
  clearing are instant.

## Value

`ctx`, invisibly.

## See also

[`pz_annotate()`](https://posit-dev.github.io/paparazzi/reference/pz_annotate.md),
[`pz_annotate_clear()`](https://posit-dev.github.io/paparazzi/reference/pz_annotate_clear.md)
