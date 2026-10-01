# Stage the page for recording

Sets the staging options that animate pointer actions, typing, and
scrolling while the page is recording. Only supplied arguments change –
an omitted argument leaves its setting alone, an explicit `NULL`
restores the default, and a value sets it (so `pz_stage(cursor = FALSE)`
can be undone with `pz_stage(cursor = NULL)`). Settings live on the page
and persist across recordings, so
[`pz_record_start()`](https://posit-dev.github.io/paparazzi/reference/pz_record_start.md)
never repeats them. Without a recording, staging is skipped and the
chain runs straight to its final state – except `cursor = TRUE`, which
shows a static cursor in screenshots too.

## Usage

``` r
pz_stage(
  ctx,
  ...,
  cursor = NULL,
  cursor_speed = NULL,
  cursor_scale = NULL,
  enter = NULL,
  typing = NULL,
  typing_speed = NULL,
  pause = NULL,
  camera_follow = NULL,
  show_keys = NULL,
  click_effect = NULL,
  click_effect_color = NULL
)
```

## Arguments

- ctx:

  A paparazzi context.

- ...:

  Checked empty; reserved for future use.

- cursor:

  Cursor visibility: `NULL` (the default) shows the cursor only while
  recording, `TRUE` shows it always (stills too), `FALSE` never shows
  it. Supply `NULL` to restore the default.

- cursor_speed:

  Staging speed in pixels per second for cursor glides and recorded
  scrolls. The default, 500 px/s, gives viewers time to follow the
  movement; 400-600 px/s is a useful range for deliberate actions. Each
  glide uses its straight-line distance; each scroll uses the largest
  axis delta. Duration is
  `clamp(0.25 + distance / cursor_speed, 0.5, 2)` seconds: the 0.25s
  base makes short moves less sensitive to speed, and the 0.5-2s limits
  mean extreme speeds have little effect. Supply `NULL` to restore the
  default.

- cursor_scale:

  Cursor size relative to the original 20px overlay artwork, from
  greater than 0 to 5. The default is 1.75 (about 35px); use 1 for the
  original size. Applies to recordings and stills. Supply `NULL` to
  restore the default.

- enter:

  Where a cursor that has never been shown first appears: `NULL` (the
  default) fades in on the target; a side (`"top"`, `"bottom"`,
  `"left"`, `"right"`) or corner (`"top left"`, `"bottom right"`, ...)
  starts off-frame past that edge and glides in. Supply `NULL` to
  restore the default.

- typing:

  Typing style while recording: `"natural"` (the default) inserts one
  character at a time with randomized delays; `"instant"` inserts the
  whole string at once. Supply `NULL` to restore the default.

- typing_speed:

  Natural typing speed in characters per second. The default is 16.
  Supply `NULL` to restore the default.

- pause:

  Seconds to hold after each action while recording. The default is 0.
  Supply `NULL` to restore the default.

- camera_follow:

  Whether pointer and typing actions automatically pan a zoomed
  recording camera to keep their target in view. Defaults to `TRUE`;
  `FALSE` disables it and `NULL` restores the default.

- show_keys:

  Keystroke callouts for
  [`pz_act_press()`](https://posit-dev.github.io/paparazzi/reference/pz_act_press.md):
  `"none"` (default), `"words"`, `"mac"`, or `"both"`. Supply `NULL` to
  restore the default. Callouts appear only in recordings.

- click_effect:

  Click feedback shown by
  [`pz_act_click()`](https://posit-dev.github.io/paparazzi/reference/pz_act_click.md)
  while recording: `"press"` (the default) scales the cursor down while
  pressed, `"ring"` draws an expanding ring that fades out at the click
  point instead of scaling, and `"none"` shows nothing. Supply `NULL` to
  restore the default.

- click_effect_color:

  CSS color of the `"ring"` click effect. The default is `"#e11d48"`.
  Supply `NULL` to restore the default.

## Value

`ctx`, invisibly.

## See also

[`pz_stage_frame()`](https://posit-dev.github.io/paparazzi/reference/pz_stage_frame.md),
[`pz_stage_annotate()`](https://posit-dev.github.io/paparazzi/reference/pz_stage_annotate.md),
[`pz_cursor_show()`](https://posit-dev.github.io/paparazzi/reference/pz_cursor_show.md),
[`pz_record_start()`](https://posit-dev.github.io/paparazzi/reference/pz_record_start.md)

## Examples

``` r
if (FALSE) { # paparazzi:::examples_run("av")
page <- pz_open(pz_example("tasks"))

# Staging settings stay on the page until you change them
page |> pz_stage(enter = "left", cursor_speed = 500, typing_speed = 20, pause = 0.3)

# Recorded clicks show a custom-colored ring
page |> pz_stage(click_effect = "ring", click_effect_color = "#2563eb")

path <- file.path(tempdir(), "add-task.mp4")
page |>
  pz_record(path, {
    page |>
      pz_act_type("Buy milk", target = "#task-title") |>
      pz_act_click("#add-task")
  })

# NULL restores a setting's default
page |> pz_stage(pause = NULL)

# cursor = TRUE shows the cursor in screenshots too
page |>
  pz_stage(cursor = TRUE) |>
  pz_act_hover("#task-title") |>
  pz_screenshot(file.path(tempdir(), "cursor.png"), frame = "#new-task")
pz_close(page)
}
```
