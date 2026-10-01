# Recording and staging

A recording is a browser script captured as MP4, WebM, or GIF. The script
still uses the same actions and expectations as a test; recording adds a video
timeline, staged motion, framing, and annotations around those steps.

## Record a complete task

This example records adding a task: the home frame holds the heading and list
while the camera visits the form and returns after the new row appears.

```r
library(paparazzi)

page <- pz_open(
  pz_example("tasks"),
  width = 1000,
  height = 720,
  color_scheme = "light"
)
pz_stage(page, enter = "bottom", pause = 0.25, cursor_speed = 480)
video <- tempfile(fileext = ".mp4")
basil <- pz_loc(".task", has_text = "Water the basil")

page |>
  pz_record_start(
    video,
    frame = pz_frame(
      list("h1", ".task-list"),
      pad = 24,
      ratio = 16 / 9,
      when = "start"
    ),
    fps = 12,
    scale = 0.75,
    hold = c(0.3, 0.8)
  ) |>
  pz_annotate_caption("Add a task") |>
  pz_camera(pz_frame("#new-task", zoom = 2), wait = TRUE) |>
  pz_act_type("Water the basil", target = "#task-title") |>
  pz_act_click(
    "#add-task",
    effect = "ripple",
    effect_color = "#2563eb"
  ) |>
  pz_expect_visible(basil) |>
  pz_camera_reset() |>
  pz_annotate_caption("Water the basil was added", side = "top") |>
  pz_record_hold(0.6) |>
  pz_record_stop()

page |> pz_annotate_clear(id = "caption")
```

`pz_record_start()` returns a recording context. `pz_record_stop()` encodes
its frames and writes the output. `pz_record()` writes the video on normal
completion or after a `code` error, then rethrows that error.

The first caption labels the form; the second replaces it after the task
appears, fading the outgoing caption during recording. Captions use screen
space at the top or bottom; color, font family, and size are configurable.
They persist across navigation and recordings, appear in stills, and remain
through the last frame. `pz_annotate_clear(id = "caption")` clears one;
clearing it here leaves later examples uncaptioned.

The start frame is the **home frame**. `pz_camera()` moves to a shot within
it, applied when the video is encoded: here `zoom = 2` frames the form at
twice the home zoom, and `pz_camera_reset()` goes back to the home frame. The
camera changes the video, not the browser viewport. With `wait = TRUE` the
next action starts after the move finishes; the default, `FALSE`, overlaps
them.

Frames accept a `pz_frame()` spec or locator. `when = "start"` measures the
recording crop at capture start; the default uses the final layout. Numeric
`zoom` sizes a portion of the viewport for the home frame or a portion of the
home frame for a camera shot. `camera_follow = TRUE` pans a zoomed camera to
keep pointer and typing targets in view.

## Choose a format and pace

A path extension selects its output format. MP4 and WebM need the av package;
GIF needs gifski. A framed GIF also needs png, and GIFs with camera movement or
burned-in captions need `av`. `fps` sets the output frame rate, and `scale`
controls output size.

```r
formats <- c("mp4", "webm", "gif")
outputs <- setNames(
  file.path(tempdir(), paste0("tasks-demo.", formats)),
  formats
)

for (format in formats) {
  page |> pz_nav_reload()
  pz_record(
    page,
    outputs[[format]],
    fps = 8,
    scale = 0.5,
    code = {
      page |>
        pz_act_click("#toggle-help") |>
        pz_expect_visible(target = "#help")
    }
  )
}
```

`scale = 0.5` halves each dimension; a value above 4 sets the output width in
pixels (`scale = 800`), and `NULL` keeps the captured size. `fps` defaults to
15. The default capture method polls at that rate, repeating the previous
frame when nothing changed; `method = "screencast"` captures on visual
changes instead and can catch more of an animation's in-between states.

The `hold` argument to `pz_record_start()` adds seconds to the first and last
frames; its default is `c(0.5, 1)`. `pz_record_hold(seconds)` adds a hold at a
chosen point in the script. It changes the video timeline, not how long
the R script waits.

## Pause and resume a recording

Use `pz_record_pause()` and `pz_record_resume()` to leave a stretch of browser
work out of the video while keeping it in the same script. The recording
clock excludes the paused interval. This example opens the help panel, pauses
while it is open, closes it during the pause, then resumes on the closed state.

```r
page |> pz_nav_reload()
paused_video <- tempfile(fileext = ".webm")
recording <- pz_record_start(page, paused_video, fps = 10, scale = 0.5)
recording |>
  pz_act_click("#toggle-help") |>
  pz_expect_visible(target = "#help") |>
  pz_record_hold(0.4) |>
  pz_record_pause()

page |> pz_act_click("#toggle-help")
recording |>
  pz_record_resume() |>
  pz_expect_hidden(target = "#help") |>
  pz_record_hold(0.4) |>
  pz_record_stop()
```

`pz_record_pause()` and `pz_record_resume()` return the recording context,
so the chain can continue on either side of the pause. The second click still
changes the live page; the recording resumes with the panel closed. A
`pz_record_hold()` in an active recording adds a hold, while the same call
outside a recording returns the page context without waiting.

For a short script, `pz_record()` owns the start/stop pair and forwards
recording options to `pz_record_start()`:

```r
page |> pz_nav_reload()
block_video <- tempfile(fileext = ".gif")
pz_record(
  page,
  block_video,
  fps = 8,
  scale = 0.5,
  code = {
    page |>
      pz_act_click("#toggle-help") |>
      pz_expect_visible(target = "#help") |>
      pz_record_hold(0.5)
  }
)
```

## Stage pointer and typing actions

`pz_stage()` stores presentation settings on the page. They animate actions
only during an active, unpaused recording; outside one, the same actions run
at full speed. Settings last across recordings. An omitted argument leaves
its setting alone, and an explicit `NULL` restores its default.

```r
page |>
  pz_stage(
    cursor_speed = 460,
    cursor_scale = 1.5,
    enter = "bottom",
    typing = "natural",
    typing_speed = 18,
    pause = 0.2,
    camera_follow = TRUE,
    show_keys = "mac",
    click_effect = "ripple",
    click_effect_color = "#2563eb"
  )
```

By default the cursor shows only while recording; `cursor = TRUE` also
draws it in stills, and `FALSE` hides it. `cursor_speed` is the glide and
scroll speed in pixels per second, and `cursor_scale` sizes the cursor
relative to its original artwork. `enter` picks where the cursor first
appears, a side or corner such as `"bottom"` or `"top left"`.

`typing = "natural"` types one character at a time with randomized delays,
and `"instant"` enters the whole string at once. `typing_speed` is in
characters per second. `pause` holds for that many seconds after each action
while recording. `camera_follow` decides whether a zoomed camera pans to
follow pointer and typing targets.

`show_keys` sets how `pz_act_press()` displays keys: `"none"`, `"words"`,
`"mac"` or `"both"`. `click_effect` sets the click feedback for
`pz_act_click()`: `"press"` (the default) shrinks the cursor while pressed,
`"ripple"` draws a fading ring instead, and `"none"` shows nothing.
`click_effect_color` is the ripple's CSS color. Override them for a single
call with `pz_act_click(effect =, effect_color =)` and
`pz_act_press(show_keys =)`:

```r
page |>
  pz_stage(pause = NULL, typing = NULL, show_keys = NULL, click_effect = NULL)

per_call_video <- tempfile(fileext = ".mp4")
pz_record(
  page,
  per_call_video,
  fps = 10,
  scale = 0.5,
  code = {
    page |>
      pz_act_type("Review the garden", target = "#task-title") |>
      pz_act_click(
        "#add-task",
        effect = "ripple",
        effect_color = "#16a34a"
      ) |>
      pz_expect_visible(
        pz_loc(".task", has_text = "Review the garden")
      ) |>
      pz_act_type("Plant the mint", target = "#task-title") |>
      pz_act_press("Enter", show_keys = "mac") |>
      pz_expect_visible(pz_loc(".task", has_text = "Plant the mint"))
  }
)
```

The `NULL` values put typing, pause, key display and click feedback back to
their defaults. The click then asks for a green ripple just for that action, and
the Enter press shows a Mac keycap while it submits the second task. Each
`pz_act_press()` replaces the previous key callout.

## Turn a tested script into a demo

Write the steps once as a function with its expectations, run it as a check,
then stage the page and record the same function. This example needs shiny.

```r
app <- pz_open(
  pz_example("tasks-app"),
  width = 900,
  height = 700,
  color_scheme = "light"
)

add_task <- function(ctx, title) {
  ctx |>
    pz_act_type(title, target = "#title") |>
    pz_act_click("#add") |>
    pz_wait_for_shiny_idle() |>
    pz_expect_visible(pz_loc(".task", has_text = title))
}

add_task(app, "Check the seedlings")
app |> pz_expect_count(3, target = ".task")

pz_stage(app, typing = "natural", typing_speed = 20, pause = 0.25)
shiny_demo <- tempfile(fileext = ".mp4")
pz_record(
  app,
  shiny_demo,
  fps = 12,
  scale = 0.6,
  code = add_task(app, "Prepare the garden")
)

app |> pz_expect_count(4, target = ".task")
pz_close(app)
```

Staging only animates while recording, so the check runs at full speed, and
the expectations that stay in the recorded function confirm that the demo
reached the state it shows.

```r
pz_close(page)
unlink(c(video, outputs, paused_video, block_video, per_call_video, shiny_demo))
```
