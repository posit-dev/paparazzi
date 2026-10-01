# Record a block of code

The block form of
[`pz_record_start()`](https://posit-dev.github.io/paparazzi/reference/pz_record_start.md):
starts recording, evaluates the embraced expression `code`, and stops
and encodes on exit – including on error, so a failed run still produces
the video up to the failure. Returns what
[`pz_record_stop()`](https://posit-dev.github.io/paparazzi/reference/pz_record_stop.md)
returns, never the block's value: `ctx` invisibly when a path was given
outside knitting, media while knitting, or a viewer preview when the
path is `NULL` in an interactive session. Write
`pz_record(code = { ... })` to omit the path.

## Usage

``` r
pz_record(ctx, path = NULL, code, ...)
```

## Arguments

- ctx:

  A paparazzi context.

- path:

  Output file path; the extension (`.mp4`, `.webm`, or `.gif`) selects
  the format. An existing file is overwritten. With `NULL` (the default)
  while knitting, a numbered file in the chunk's figure directory is
  used and the recording appears in the document; in an interactive
  session, a temporary file is used and shown in the viewer when
  recording stops. A path is required otherwise.

- code:

  An expression to evaluate while recording.

- ...:

  Passed to
  [`pz_record_start()`](https://posit-dev.github.io/paparazzi/reference/pz_record_start.md).

## Value

`ctx`, invisibly, or printable media; see
[`pz_record_stop()`](https://posit-dev.github.io/paparazzi/reference/pz_record_stop.md).

## Examples

``` r
if (FALSE) { # paparazzi:::examples_run("av")
page <- pz_open(pz_example("tasks"))
path <- file.path(tempdir(), "add-task.mp4")

# The recording stops and is written when the block exits, even on error
page |>
  pz_record(path, {
    page |>
      pz_act_type("Buy milk", target = "#task-title") |>
      pz_act_click("#add-task") |>
      pz_expect_count(8, target = ".task")
  }) |>
  pz_screenshot(file.path(tempdir(), "after.png"))
file.exists(path)
pz_close(page)
}
```
