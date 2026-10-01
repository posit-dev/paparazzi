# Move the recording camera

Moves an encode-time camera over a recording. The shot comes from
`frame`: a
[`pz_frame()`](https://posit-dev.github.io/paparazzi/reference/pz_frame.md)
spec, or a bare locator (a CSS selector string, a
[`pz_loc()`](https://posit-dev.github.io/paparazzi/reference/pz_loc.md)
spec, or a list of either) promoted to one, whose union is the shot. In
a scoped context `frame` may be omitted or `NULL` to shoot the scope's
box; at the root it is required
([`pz_camera_reset()`](https://posit-dev.github.io/paparazzi/reference/pz_camera_reset.md)
returns to the home view). `frame = FALSE` shoots the scope's box, or
the viewport at the root, unframed. The camera does not change the live
page or still screenshots. Outside a recording it does nothing, and each
[`pz_record_start()`](https://posit-dev.github.io/paparazzi/reference/pz_record_start.md)
begins at the recording frame.

## Usage

``` r
pz_camera(ctx, frame, ..., duration = NULL, wait = FALSE)
```

## Arguments

- ctx:

  A paparazzi context.

- frame:

  The shot's what-and-how: a
  [`pz_frame()`](https://posit-dev.github.io/paparazzi/reference/pz_frame.md)
  spec or a bare locator promoted to one. Camera shots never inherit the
  staged frame: unset fields use the camera defaults (`pad = 24`,
  `target_box = "element"`, everything else as in
  [`pz_frame()`](https://posit-dev.github.io/paparazzi/reference/pz_frame.md)).
  `ratio` and `when` are ignored, with a warning when set. `zoom` is
  magnification relative to the recording frame: `NULL` fits the padded
  target, capped at the capture's pixel density; a number fixes the shot
  at the home frame divided by `zoom`. `anchor` places the padded target
  in the shot.

  `frame` is required at the root. In a scoped context, leaving it out
  (or `NULL`) shoots the scope's box. A spec without a target also
  frames the scope's box, or the viewport at the root, so
  `pz_frame(zoom = 2)` zooms in on the middle of the view. `FALSE`
  shoots the scope's box or the viewport with no padding.

- ...:

  Checked empty; reserved for future use.

- duration:

  Movement duration in seconds. `NULL` chooses a duration based on the
  pan and zoom distance. When the move wouldn't change the view, `NULL`
  takes the new shot instantly, adding no video time, so the camera
  follows the new target if the page scrolls later. A number holds the
  camera still for that long.

- wait:

  Whether to wait for the move to finish before the next step. `FALSE`
  (the default) lets the next step run while the camera moves, so a
  cursor glide can happen during a zoom. Either way, a camera call first
  lets an earlier camera move finish, so calling `pz_camera()` on the
  same target again settles the camera there.
  [`pz_record_hold()`](https://posit-dev.github.io/paparazzi/reference/pz_record_hold.md),
  [`pz_record_pause()`](https://posit-dev.github.io/paparazzi/reference/pz_record_pause.md)
  and
  [`pz_record_stop()`](https://posit-dev.github.io/paparazzi/reference/pz_record_stop.md)
  always let a move finish first.

## Value

`ctx`, invisibly.
