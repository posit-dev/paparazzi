# Move the overlay cursor out of the frame

Sends the cursor out of the frame through `side`: while recording it
glides out, otherwise it leaves immediately. The cursor is still visible
(just off-frame); the next pointer action or cursor call glides it back
in from that side.

## Usage

``` r
pz_cursor_leave(ctx, side = "right", icon = NULL)
```

## Arguments

- ctx:

  A paparazzi context.

- side:

  A side (`"top"`, `"bottom"`, `"left"`, `"right"`) or corner
  (`"top left"`, `"bottom right"`, ...) of the frame to leave through.
  Defaults to `"right"`.

- icon:

  CSS cursor keyword to show during the exit. `NULL` (the default) keeps
  the icon already on the cursor: there is nothing to infer at the
  off-frame exit point. The exit icon becomes the last visible icon, so
  the next entrance starts with it.

## Value

`ctx`, invisibly.

## See also

[`pz_cursor_show()`](https://posit-dev.github.io/paparazzi/reference/pz_cursor_show.md)

## Examples

``` r
if (FALSE) { # paparazzi:::examples_run("av")
page <- pz_open(pz_example("tasks"))
path <- file.path(tempdir(), "help.mp4")
page |>
  pz_record(path, {
    page |>
      pz_act_click("#toggle-help") |>
      # Move the cursor out of the way so the help text is unobstructed
      pz_cursor_leave("right", icon = "default") |>
      pz_record_hold(1)
  })
pz_close(page)
}
```
