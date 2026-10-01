# Move the overlay cursor to an element

Moves the cursor over `target`, showing it first if hidden. While
recording the move is a glide whose duration scales with distance (see
[`pz_stage()`](https://posit-dev.github.io/paparazzi/reference/pz_stage.md));
pass `duration` to override it. Without a recording the cursor jumps.

## Usage

``` r
pz_cursor_move(
  ctx,
  target,
  ...,
  duration = NULL,
  icon = NULL,
  offset = c(0, 0)
)
```

## Arguments

- ctx:

  A paparazzi context.

- target:

  A CSS selector string, a
  [`pz_loc()`](https://posit-dev.github.io/paparazzi/reference/pz_loc.md)
  spec, or a list of specs. The cursor centers on the match.

- ...:

  Checked empty; reserved for future use.

- duration:

  Glide duration in seconds; `NULL` computes one from the distance and
  the `cursor_speed` staging setting.

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

- offset:

  Landing offset in viewport CSS pixels, `c(x, y)` with positive x to
  the right and positive y downward. A single number is recycled to both
  axes; the default `c(0, 0)` adds no offset. It applies only to this
  call and only to the drawn overlay, not to page pointer events. The
  cursor may land outside the viewport without clamping.

## Value

`ctx`, invisibly.

## See also

[`pz_cursor_show()`](https://posit-dev.github.io/paparazzi/reference/pz_cursor_show.md),
[`pz_cursor_leave()`](https://posit-dev.github.io/paparazzi/reference/pz_cursor_leave.md)

## Examples

``` r
if (FALSE) { # paparazzi:::examples_run("av")
page <- pz_open(pz_example("tasks"))
path <- file.path(tempdir(), "tour.mp4")

# While recording, the cursor glides between elements
page |>
  pz_record(path, {
    page |>
      pz_cursor_show(".filters", from = "left") |>
      pz_cursor_move("#toggle-help", duration = 1) |>
      pz_cursor_move("#add-task", icon = "crosshair")
  })
pz_close(page)
}
```
