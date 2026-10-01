# Hide the overlay cursor

Hides the cursor set up by
[`pz_cursor_show()`](https://posit-dev.github.io/paparazzi/reference/pz_cursor_show.md)
or shown implicitly while recording. The cursor keeps its last position;
showing it again returns it there. The hide is explicit and sticky: the
cursor stays hidden until
[`pz_cursor_show()`](https://posit-dev.github.io/paparazzi/reference/pz_cursor_show.md)
or
[`pz_cursor_move()`](https://posit-dev.github.io/paparazzi/reference/pz_cursor_move.md)
shows it again – neither a recorded pointer action nor the `cursor`
staging setting brings it back. That is what distinguishes
`pz_cursor_hide()` from
[`pz_cursor_leave()`](https://posit-dev.github.io/paparazzi/reference/pz_cursor_leave.md),
which keeps the cursor visible and glides back in on the next action.

## Usage

``` r
pz_cursor_hide(ctx, ...)
```

## Arguments

- ctx:

  A paparazzi context.

- ...:

  Checked empty; reserved for future use.

## Value

`ctx`, invisibly.

## See also

[`pz_cursor_show()`](https://posit-dev.github.io/paparazzi/reference/pz_cursor_show.md),
[`pz_cursor_leave()`](https://posit-dev.github.io/paparazzi/reference/pz_cursor_leave.md)

## Examples

``` r
page <- pz_open(pz_example("tasks"))
page |>
  pz_cursor_show("#add-task") |>
  pz_cursor_hide() |>
  pz_screenshot(file.path(tempdir(), "no-cursor.png"))
pz_screenshot(page, frame = pz_frame("#new-task", pad = 24))
pz_close(page)
```
