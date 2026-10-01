# Hold the current frame while recording

Lingers on the current frame for `seconds` in the output video. Unlike
[`pz_wait()`](https://posit-dev.github.io/paparazzi/reference/pz_wait.md),
no real time passes: the hold is inserted into the video timeline at
encode time. When the page is not recording this is a no-op, so
debugging a chain with the recording commented out doesn't pay for
video-only pauses. A camera move still in progress (see
[`pz_camera()`](https://posit-dev.github.io/paparazzi/reference/pz_camera.md))
finishes before the hold begins.

## Usage

``` r
pz_record_hold(ctx, seconds)
```

## Arguments

- ctx:

  A paparazzi context.

- seconds:

  Seconds to hold the frame in the output.

## Value

`ctx`, invisibly.

## Examples

``` r
if (FALSE) { # paparazzi:::examples_run("av")
page <- pz_open(pz_example("tasks"))

# Without a recording, pz_record_hold() returns straight away
system.time(pz_record_hold(page, 2))

path <- file.path(tempdir(), "help.mp4")
page |>
  pz_record_start(path) |>
  pz_act_click("#toggle-help") |>
  # Give viewers a second to read the help text
  pz_record_hold(1) |>
  pz_record_stop()
pz_close(page)
}
```
