# Stop a recording and write the video

Ends the recording started with
[`pz_record_start()`](https://posit-dev.github.io/paparazzi/reference/pz_record_start.md),
encodes the captured frames, and writes the file given to
[`pz_record_start()`](https://posit-dev.github.io/paparazzi/reference/pz_record_start.md).

## Usage

``` r
pz_record_stop(ctx)
```

## Arguments

- ctx:

  A paparazzi context.

## Value

`ctx`, invisibly, when the path was supplied outside knitting. While
knitting, returns a printable image for GIF, HTML video for MP4/WebM, or
a video link in non-HTML output, even when the path was supplied
explicitly. Without a path in an interactive session, returns a preview
that shows the recording in the viewer when printed.

## Examples

``` r
if (FALSE) { # paparazzi:::examples_run("av")
page <- pz_open(pz_example("tasks"))
path <- file.path(tempdir(), "done.gif")
page |>
  pz_record_start(path, frame = pz_frame(".task-list", pad = 8)) |>
  pz_act_click(pz_loc(".task-done", which = "first")) |>
  pz_record_stop()
file.exists(path)
pz_close(page)
}
```
