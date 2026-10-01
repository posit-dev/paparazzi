# Record a page interaction

`pz_record_start()` begins recording the page to a video or GIF;
[`pz_record_stop()`](https://posit-dev.github.io/paparazzi/reference/pz_record_stop.md)
ends the recording, encodes it, and writes the file.
[`pz_record_pause()`](https://posit-dev.github.io/paparazzi/reference/pz_record_pause.md)/[`pz_record_resume()`](https://posit-dev.github.io/paparazzi/reference/pz_record_pause.md)
cut stretches out of the recording, and
[`pz_record_hold()`](https://posit-dev.github.io/paparazzi/reference/pz_record_hold.md)
lingers on the current frame.
[`pz_record()`](https://posit-dev.github.io/paparazzi/reference/pz_record.md)
is the block form: it records for the duration of an expression and
stops on exit, including on error.

The output format comes from the `path` extension: `.mp4` (h264),
`.webm`, or `.gif`. Both methods produce a video at the requested `fps`;
when a new frame is not available, the previous frame is repeated.

## Usage

``` r
pz_record_start(
  ctx,
  path = NULL,
  ...,
  method = c("poll", "screencast"),
  frame = NULL,
  fps = 15,
  scale = NULL,
  hold = c(0.5, 1),
  keep_frames = FALSE,
  captions = c("burn", "vtt", "both"),
  format = c("auto", "mp4", "webm", "gif")
)
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

- ...:

  Checked empty; reserved for future use.

- method:

  Capture method: `"poll"` (the default) for regular, higher-resolution
  captures, or `"screencast"` for captures driven by visual changes. See
  *Choosing a capture method* for tradeoffs.

- frame:

  Area to show in the finished recording: a
  [`pz_frame()`](https://posit-dev.github.io/paparazzi/reference/pz_frame.md)
  spec, or a bare locator (a CSS selector string, a
  [`pz_loc()`](https://posit-dev.github.io/paparazzi/reference/pz_loc.md)
  spec, or a list of either) promoted to one; `NULL` uses the page
  default set with
  [`pz_stage_frame()`](https://posit-dev.github.io/paparazzi/reference/pz_stage_frame.md),
  if any, or shows the full viewport; `FALSE` ignores the default. Unset
  fields inherit the staged value, then the built-in default. A frame
  with `target_box = "annotated"` set explicitly is invalid for the home
  frame; an annotated box inherited from the staged frame silently
  measures element boxes only for recording.

- fps:

  Frames per second in the finished recording. Poll aims to capture at
  this rate; screencast capture depends on visual changes.

- scale:

  Output size: `NULL` (the default) disables resizing, keeping the
  captured size; a number up to 4 is a scale factor; a larger number is
  the output width in pixels (height scales proportionally).

- hold:

  Seconds to hold the first and last frame, `c(first, last)`.

- keep_frames:

  Keep the captured PNG frames in a `<name>_frames/` directory next to
  `path`. Otherwise frames are written to a temporary directory and
  deleted after encoding.

- captions:

  `"burn"` (the default) draws captions on the recording; `"vtt"` writes
  a WebVTT sidecar without drawing captions; `"both"` does both. WebVTT
  needs an MP4 or WebM recording, not a GIF.

- format:

  The format when `path` is `NULL`: `"auto"` (the default) records MP4,
  or GIF when knitting to a non-HTML format, where video can only be
  linked. With a `path`, the extension decides and `format` must be
  `"auto"`.

## Value

A context in the recording chain, invisibly.

## Choosing a capture method

`"poll"` (the default) takes screenshots at roughly the requested `fps`.
Choose it when resolution matters: it captures at the page's full pixel
density. `"screencast"` records when the page changes, which can capture
more intermediate states of an animation. It does not guarantee a
capture rate and may have lower resolution. For example, with a
640-by-480 viewport on a 2x display, poll frames are 1280-by-960 pixels
while screencast frames may be 640-by-480 pixels. The `scale` argument
sets output size, but enlarging a lower-resolution frame does not add
detail.

Both methods record while paparazzi runs browser actions or
[`pz_wait()`](https://posit-dev.github.io/paparazzi/reference/pz_wait.md).
Long-running R code between browser actions, including
[`Sys.sleep()`](https://rdrr.io/r/base/Sys.sleep.html), can cause
intermediate changes to be missed; use
[`pz_wait()`](https://posit-dev.github.io/paparazzi/reference/pz_wait.md)
when you want a visible wait in the video.

## Output and framing

Stopping always captures one final frame of the page state at
[`pz_record_stop()`](https://posit-dev.github.io/paparazzi/reference/pz_record_stop.md),
so a change made just before the stop still appears; the last-frame hold
repeats that final frame.

Use
[`pz_frame()`](https://posit-dev.github.io/paparazzi/reference/pz_frame.md)
(or the page default set with
[`pz_stage_frame()`](https://posit-dev.github.io/paparazzi/reference/pz_stage_frame.md))
to crop the finished recording. By default the frame follows the layout
at stop; `pz_frame(when = "start")` fixes it to the layout at start. If
the page navigates, a frame tied to the previous page falls back to the
full viewport unless it was fixed at the start. MP4 dimensions are
rounded down to multiples of 4 and WebM to even pixels; GIF keeps whole
pixels. Set the viewport size before `pz_record_start()`; resizing
during a framed or camera recording is not supported.

WebVTT captions (when requested) are written as a `.vtt` file next to
the MP4 or WebM. Cue times include the first/last holds and explicit
[`pz_record_hold()`](https://posit-dev.github.io/paparazzi/reference/pz_record_hold.md)
intervals but exclude pauses. Caption burn and VTT use the current
caption set by
[`pz_annotate_caption()`](https://posit-dev.github.io/paparazzi/reference/pz_annotate_caption.md).

MP4 and WebM recordings require av; GIF recordings require gifski.
Simple GIFs need only gifski, but two features call in extra packages:
framed GIFs require png, and GIFs with camera movement or burned-in
captions require av. Packages are checked at `pz_record_start()`, or
during a GIF recording at the first camera move or caption.

## Recording chains

`pz_record_start()` returns a context that belongs to the new recording.
Chainable functions return it (and contexts derived from it with
[`pz_find()`](https://posit-dev.github.io/paparazzi/reference/pz_find.md))
visibly while the recording runs, and printing it stops the recording.
So a chain that starts with `pz_record_start()` needs no
[`pz_record_stop()`](https://posit-dev.github.io/paparazzi/reference/pz_record_stop.md)
when it is printed: at the end of a knitted chunk expression the
recording appears in the document, and in the console it is shown in the
viewer. Assign the chain or call
[`pz_record_stop()`](https://posit-dev.github.io/paparazzi/reference/pz_record_stop.md)
to record across several statements. Chains that don't come from
`pz_record_start()`, such as `page |> pz_act_click()`, keep returning
invisibly and never stop a recording.

## See also

[`pz_record()`](https://posit-dev.github.io/paparazzi/reference/pz_record.md),
[`pz_record_hold()`](https://posit-dev.github.io/paparazzi/reference/pz_record_hold.md),
[`pz_frame()`](https://posit-dev.github.io/paparazzi/reference/pz_frame.md),
[`pz_stage_frame()`](https://posit-dev.github.io/paparazzi/reference/pz_stage_frame.md)

## Examples

``` r
if (FALSE) { # paparazzi:::examples_run("av")
page <- pz_open(pz_example("tasks"), width = 800, height = 600)
path <- file.path(tempdir(), "help.mp4")

# Record the help panel opening, cropped to the page's card
page |>
  pz_record_start(path, frame = pz_frame("main")) |>
  pz_act_click("#toggle-help") |>
  pz_expect_visible(target = "#help") |>
  pz_record_stop()
file.exists(path)
pz_close(page)
}
```
