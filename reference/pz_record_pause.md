# Pause and resume a recording

`pz_record_pause()` cuts the stretch up to the next `pz_record_resume()`
out of the recording: no frames are captured and the video clock stops,
so the pause leaves no trace in the output.

## Usage

``` r
pz_record_pause(ctx)

pz_record_resume(ctx)
```

## Arguments

- ctx:

  A paparazzi context.

## Value

`ctx`, invisibly.

## Examples

``` r
if (FALSE) { # paparazzi:::examples_run("av")
page <- pz_open(pz_example("tasks"))
path <- file.path(tempdir(), "add-task.mp4")
page |>
  pz_record_start(path) |>
  pz_act_click("#task-title") |>
  pz_record_pause() |>
  # Filling in the form is cut from the video
  pz_set_value("Buy milk", target = "#task-title") |>
  pz_set_value("high", target = "#task-priority") |>
  pz_record_resume() |>
  pz_act_click("#add-task") |>
  pz_expect_count(8, target = ".task") |>
  pz_record_stop()
pz_close(page)
}
```
