# Show the overlay cursor

Shows paparazzi's overlay cursor, optionally over a `target` element.
While recording, the cursor appears with staging: it glides from its
last position, fades in on the target when it has never been shown, or
glides in from `from` (or the `enter` side set with
[`pz_stage()`](https://posit-dev.github.io/paparazzi/reference/pz_stage.md))
when entering the frame. Without a recording the cursor appears
statically, which is how a cursor lands in a screenshot. Its default
size is 1.75 times the original artwork; set `cursor_scale` with
[`pz_stage()`](https://posit-dev.github.io/paparazzi/reference/pz_stage.md)
to change the size in videos and stills.

## Usage

``` r
pz_cursor_show(ctx, target = NULL, ..., from = NULL, icon = NULL)
```

## Arguments

- ctx:

  A paparazzi context.

- target:

  A CSS selector string, a
  [`pz_loc()`](https://posit-dev.github.io/paparazzi/reference/pz_loc.md)
  spec, or a list of specs. The cursor centers on the match. `NULL` uses
  the current scope's element or, at the root context, shows the cursor
  at its last position (or the viewport center the first time).

- ...:

  Checked empty; reserved for future use.

- from:

  A side (`"top"`, `"bottom"`, `"left"`, `"right"`) or corner
  (`"top left"`, `"bottom right"`, ...) of the frame to enter from.
  `NULL` (the default) re-enters from the direction the cursor last left
  through (see
  [`pz_cursor_leave()`](https://posit-dev.github.io/paparazzi/reference/pz_cursor_leave.md));
  a cursor that has never been shown uses the `enter` setting of
  [`pz_stage()`](https://posit-dev.github.io/paparazzi/reference/pz_stage.md).
  Otherwise the cursor glides from its current position.

- icon:

  CSS cursor keyword to show for this call. `NULL` (the default) infers
  the icon at the actual landing point: the first computed `cursor`
  other than `auto` on the element under the point or an ancestor. Every
  CSS cursor keyword is supported: for example, `default`, `pointer`,
  `text`, `crosshair`, `wait`, `zoom-in`, and the resize keywords.
  `none` hides the artwork without changing the overlay's position; an
  explicit `auto` shows the default arrow. A bare
  [`url()`](https://rdrr.io/r/base/connections.html) uses `default`; a
  [`url()`](https://rdrr.io/r/base/connections.html) with a supported
  keyword fallback uses that keyword. Custom URL images are not drawn.
  An explicit icon lasts through this call's landing but does not
  override the next call's automatic inference. The selected icon stays
  on the cursor until the next destination; the first off-frame entrance
  starts with `default` unless overridden. While recording, an automatic
  move keeps the icon already visible until it enters the destination
  and switches there; an explicit `icon` applies from the start of the
  glide and stays through its landing and any press. The artwork tracks
  CSS zoom and the device pixel ratio internally, and a navigation
  re-injects the overlay with its last icon.

## Value

`ctx`, invisibly.

## See also

[`pz_stage()`](https://posit-dev.github.io/paparazzi/reference/pz_stage.md)
for cursor settings,
[`pz_cursor_hide()`](https://posit-dev.github.io/paparazzi/reference/pz_cursor_hide.md),
[`pz_cursor_move()`](https://posit-dev.github.io/paparazzi/reference/pz_cursor_move.md),
[`pz_cursor_leave()`](https://posit-dev.github.io/paparazzi/reference/pz_cursor_leave.md)

## Examples

``` r
page <- pz_open(pz_example("tasks"))
path <- file.path(tempdir(), "add-button.png")

# Outside a recording the cursor appears at once, ready for a still
page |>
  pz_cursor_show("#add-task", icon = "pointer") |>
  pz_screenshot(path, frame = pz_frame("#new-task", pad = 24))
pz_screenshot(page, frame = pz_frame("#new-task", pad = 24))
pz_close(page)
```
