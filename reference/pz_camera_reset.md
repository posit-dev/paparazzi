# Reset the recording camera

Returns the camera to the recording frame (or the full viewport).
Outside a recording it does nothing.

## Usage

``` r
pz_camera_reset(ctx, ..., wait = FALSE)
```

## Arguments

- ctx:

  A paparazzi context.

- ...:

  Checked empty; reserved for future use.

- wait:

  Whether to wait for the move to finish before the next step. `FALSE`
  (the default) lets the next step run while the camera moves, so a
  cursor glide can happen during a zoom. Either way, a camera call first
  lets an earlier camera move finish, so calling
  [`pz_camera()`](https://posit-dev.github.io/paparazzi/reference/pz_camera.md)
  on the same target again settles the camera there.
  [`pz_record_hold()`](https://posit-dev.github.io/paparazzi/reference/pz_record_hold.md),
  [`pz_record_pause()`](https://posit-dev.github.io/paparazzi/reference/pz_record_pause.md)
  and
  [`pz_record_stop()`](https://posit-dev.github.io/paparazzi/reference/pz_record_stop.md)
  always let a move finish first.

## Value

`ctx`, invisibly.
