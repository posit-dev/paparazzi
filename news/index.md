# Changelog

## paparazzi 0.0.0.9000

- Breaking:
  [`pz_annotate_callout()`](https://posit-dev.github.io/paparazzi/reference/pz_annotate_callout.md)’s
  `arrow` argument is renamed `leader`. `TRUE` (the default) draws a
  shaft with an arrow at the target, `FALSE` leaves a tooltip-style
  bubble, and a named character vector sets a decoration per end
  (`c(start = "dot", end = "bar")`; `"none"`, `"arrow"`, `"dot"`,
  `"bar"`).

- Callouts are themeable and measurable:
  [`pz_annotate_callout()`](https://posit-dev.github.io/paparazzi/reference/pz_annotate_callout.md)
  and
  [`pz_stage_annotate()`](https://posit-dev.github.io/paparazzi/reference/pz_stage_annotate.md)
  gain `fill` and `text_color` for the bubble chrome (defaults keep the
  dark bubble with white text), `stroke_width` (one width shared with
  [`pz_annotate()`](https://posit-dev.github.io/paparazzi/reference/pz_annotate.md)
  marks, replacing the old 2-vs-3 split, with decoration sizes scaled to
  it) and `distance` (the bubble-to-target gap, default 24 CSS px with a
  leader and 8 without, replacing the hardcoded 8px so leaders read as
  arrows).
  [`pz_annotate()`](https://posit-dev.github.io/paparazzi/reference/pz_annotate.md)
  badges follow their mark’s color and gain per-call
  `label_fill`/`label_text_color` overrides.

- Cursor overlays now use bundled SVG artwork for the full set of CSS
  cursor keywords, including `wait`, `zoom-in`, directional resize, and
  `none`. CSS cursor URLs use their fallback keyword; custom URL images
  are not drawn.

- First development version. paparazzi drives a headless Chrome browser
  from R through chromote, with one `|>` chain per script: open pages
  and Shiny apps
  ([`pz_open()`](https://posit-dev.github.io/paparazzi/reference/pz_open.md),
  [`pz_serve_shiny()`](https://posit-dev.github.io/paparazzi/reference/pz_serve_shiny.md)),
  find elements
  ([`pz_loc()`](https://posit-dev.github.io/paparazzi/reference/pz_loc.md),
  [`pz_find()`](https://posit-dev.github.io/paparazzi/reference/pz_find.md)),
  act on them
  ([`pz_act_click()`](https://posit-dev.github.io/paparazzi/reference/pz_act_click.md),
  [`pz_act_type()`](https://posit-dev.github.io/paparazzi/reference/pz_act_type.md),
  [`pz_set_shiny_input()`](https://posit-dev.github.io/paparazzi/reference/pz_set_shiny_input.md),
  …), check the page with retrying expectations (`pz_expect_*()`), and
  capture screenshots and recordings
  ([`pz_screenshot()`](https://posit-dev.github.io/paparazzi/reference/pz_screenshot.md),
  [`pz_record()`](https://posit-dev.github.io/paparazzi/reference/pz_record.md)).

- paparazzi requires R 4.1.0 or later, which added the native pipe `|>`.
  The pipe appears throughout the examples and documentation.
