# paparazzi 0.0.0.9000

* `pz_stage_annotate()` gains `caption_side`, the page default for the side
  of new `pz_annotate_caption()` captions. `"bottom"` remains the default
  and a per-call `side` still overrides it; `pz_annotate_caption()`'s `side`
  argument now defaults to `NULL`, meaning the staged value.

* `pz_serve_static()` gains `root`, the directory to serve as the server
  root for an `.html` file. Use it when the page references assets outside
  its own directory, such as `../deps/styles.css`; the handle URL points at
  the file relative to `root`.

* `pz_open()` serves `.html` files over HTTP with `pz_serve_static()` when
  httpuv is installed, so pages get HTTP-only behavior such as the browser's
  back/forward cache; `pz_close()` stops the one-off server. The file's
  directory is the server root, so pages referencing assets outside it need
  an explicit `file://` URL. Without httpuv, `.html` files still open as
  `file://`.

* `pz_act_drag()` gains named-only `preview = TRUE`: recorded HTML5 drags with
  a visible cursor carry a static source image and briefly settle to the same
  surviving source after drop. Unsafe or uncertain paparazzi redactions and
  optional preview failures warn and preserve the drag. `preview = FALSE`
  disables both the image and settling.

* Persistent captions remain visible on the last GIF frame when recordings
  repeat captured frames, such as during `pz_record_hold()`.

* Breaking: `pz_annotate_callout()`'s `arrow` argument is renamed `leader`.
  `TRUE` (the default) draws a shaft with an arrow at the target, `FALSE`
  leaves a tooltip-style bubble, and a named character vector sets a
  decoration per end (`c(start = "dot", end = "bar")`; `"none"`, `"arrow"`,
  `"dot"`, `"bar"`).

* Callouts are themeable and measurable: `pz_annotate_callout()` and
  `pz_stage_annotate()` gain `fill` and `text_color` for the bubble chrome
  (defaults keep the dark bubble with white text), `stroke_width` (one width
  shared with `pz_annotate()` marks, replacing the old 2-vs-3 split, with
  decoration sizes scaled to it) and `distance` (the bubble-to-target gap,
  default 24 CSS px with a leader and 8 without, replacing the hardcoded 8px
  so leaders read as arrows).
  `pz_annotate()` badges follow their mark's color and gain per-call
  `label_fill`/`label_text_color` overrides.

* Cursor overlays now use bundled SVG artwork for the full set of CSS cursor
  keywords, including `wait`, `zoom-in`, directional resize, and `none`. CSS
  cursor URLs use their fallback keyword; custom URL images are not drawn.

* First development version. paparazzi drives a headless Chrome browser from R
  through chromote, with one `|>` chain per script: open pages and Shiny apps
  (`pz_open()`, `pz_serve_shiny()`), find elements (`pz_loc()`, `pz_find()`), act on
  them (`pz_act_click()`, `pz_act_type()`, `pz_set_shiny_input()`, ...), check the page
  with retrying expectations (`pz_expect_*()`), and capture screenshots and
  recordings (`pz_screenshot()`, `pz_record()`).

* paparazzi requires R 4.1.0 or later, which added the native pipe `|>`. The
  pipe appears throughout the examples and documentation.
