# Make a three-part app walkthrough

Suppose you want to show someone how to add a task, finish it, and find
the task tracker’s help. One long recording makes each step hard to find
later. We’ll make three short videos instead, using the task tracker
bundled with paparazzi. Play them in order: each part starts where the
previous part left the app, but each video can be replayed on its own.

You’ll need a Chromium-based browser and the av package to encode MP4
files. The [Get started
article](https://posit-dev.github.io/paparazzi/articles/paparazzi.md)
covers selectors and browser actions; here we’ll use those actions to
record the three parts.

``` r

library(paparazzi)
page <- pz_open(
  pz_example("tasks"),
  width = 800,
  height = 900,
  color_scheme = "light"
)
page |> pz_stage(enter = "top", pause = 0.2, camera_follow = TRUE)
card <- pz_frame("main", pad = 12, when = "start")
```

[`pz_stage()`](https://posit-dev.github.io/paparazzi/reference/pz_stage.md)
makes the cursor glide and types a character at a time **during
recording**. Outside a recording, the same actions run without that
animation. `card` is the area each video shows: the task-tracker card,
measured when each recording starts.

## Part 1: Add a task

We want the viewer to see both the form and the result.
[`pz_record_start()`](https://posit-dev.github.io/paparazzi/reference/pz_record_start.md)
begins a recording, and the chain that follows it is what gets recorded.
There’s no need to stop it: when the chain ends, the recording stops and
the video appears below the chunk. The camera can move *inside* that
frame while recording, without scrolling or zooming the live page. Here
it zooms in on the title field while the cursor glides over to click it,
since
[`pz_act_type()`](https://posit-dev.github.io/paparazzi/reference/pz_act_type.md)
clicks its target before typing.

``` r

page |>
  pz_record_start(frame = card, fps = 8, scale = 0.6) |>
  pz_annotate_caption("Add a task for the release") |>
  pz_camera("#task-title") |>
  pz_act_type("Prepare release notes", target = "#task-title") |>
  pz_act_click("#add-task") |>
  pz_expect_text(
    "Prepare release notes",
    target = pz_loc(".task-title", which = "first")
  ) |>
  pz_camera_reset() |>
  pz_record_hold(0.7)
```

[Download
recording](https://posit-dev.github.io/paparazzi/articles/walkthrough_files/figure-html/part-add-1.mp4)

Camera moves don’t hold up the next step, so the zoom and the cursor’s
glide happen together. Use `pz_camera(wait = TRUE)` when the camera
should arrive first. While the text is typed, the cursor fades out so it
doesn’t cover the field, and it fades back in as it glides to Add. The
camera fits the title field with padding during typing, then follows the
click toward Add. It returns to the card, where the new task appears at
the top of the list. The expectation matters because the page briefly
says “Saving…” before it inserts the task.

The caption is a page setting, not a label attached to one file. Clear
it between parts so the next video doesn’t inherit it:

``` r

page |> pz_annotate_clear(id = "caption")
```

## Part 2: Finish the task

The second recording uses the same browser page, so “Prepare release
notes” is still there. This time we’ll mark that row for the viewer,
then click its Done button and switch to the Done filter. The callout
remains until we clear it;
[`pz_record_hold()`](https://posit-dev.github.io/paparazzi/reference/pz_record_hold.md)
gives the viewer time to read it without slowing down a run outside
recording.

``` r

page |>
  pz_record_start(frame = card, fps = 8, scale = 0.6) |>
  pz_annotate_caption("Finish the task, then check the Done list") |>
  pz_camera(".task-list", wait = TRUE) |>
  pz_annotate_callout(
    "The new task",
    target = pz_loc(".task", has_text = "Prepare release notes"),
    side = "bottom",
    id = "new-task"
  ) |>
  pz_record_hold(0.9) |>
  pz_annotate_clear(id = "new-task") |>
  pz_find(pz_loc(".task", has_text = "Prepare release notes")) |>
  pz_act_click(".task-done") |>
  pz_find_reset() |>
  pz_act_click(".filters a[href='#done']") |>
  pz_expect_visible(pz_loc(".task", has_text = "Prepare release notes")) |>
  pz_camera_reset() |>
  pz_record_hold(0.6)
```

[Download
recording](https://posit-dev.github.io/paparazzi/articles/walkthrough_files/figure-html/part-finish-1.mp4)

The callout draws attention to one row, then leaves before the click.
This time the camera waits to settle on the list before the callout
appears.
[`pz_find()`](https://posit-dev.github.io/paparazzi/reference/pz_find.md)
narrows the chain to that row so `.task-done` means its button, and
[`pz_find_reset()`](https://posit-dev.github.io/paparazzi/reference/pz_find_reset.md)
widens it again for the filter link. While the camera is zoomed in,
`camera_follow = TRUE` lets an action pan the shot when its target falls
outside the view. The switch to the Done filter is still a real click;
camera movement doesn’t change the page or its scroll position.

``` r

page |> pz_annotate_clear(id = "caption")
```

## Part 3: Hide high-priority tasks before showing help

Two high-priority tasks sit near the top of the list. We’ll treat their
titles as private to show where redactions belong in a recording script.
After switching back to All, wait until “File tax return” is visible:
the filter changes after the URL fragment changes. Cover both titles
**before** starting the recorder, since earlier frames can already
contain them. Use the opaque fill, not blur, when content must be
unreadable.

``` r

page |>
  pz_act_click(".filters a[href='#all']") |>
  pz_expect_visible(pz_loc(".task", has_text = "File tax return")) |>
  pz_act_scroll("#toggle-help") |>
  pz_annotate_redact(
    "[data-priority=\"high\"] .task-title",
    method = "fill",
    id = "private-tasks"
  )
```

Now record the help panel opening. The redactions follow the two task
titles while the page moves; the caption stays at the top of the video,
leaving the help panel visible.

``` r

page |>
  pz_record_start(frame = card, fps = 8, scale = 0.6) |>
  pz_annotate_caption(
    "Open help without showing high-priority tasks",
    side = "top"
  ) |>
  pz_act_click("#toggle-help") |>
  pz_expect_visible(target = "#help") |>
  pz_record_hold(1)
```

[Download
recording](https://posit-dev.github.io/paparazzi/articles/walkthrough_files/figure-html/part-help-1.mp4)

The solid covers remain over both titles for the whole clip, including
its first frame. Once we’ve finished the tour, remove the overlays and
close the browser:

``` r

page |> pz_annotate_clear()
pz_close(page)
```

Each part has its own MP4, named after its chunk, but shares the task
tracker’s state with the next part. Camera shots reset at the start of
each recording; annotations and captions do not, so clear or replace
them deliberately. To record across several statements, assign the chain
or end it with
[`pz_record_stop()`](https://posit-dev.github.io/paparazzi/reference/pz_record_stop.md);
[`pz_record()`](https://posit-dev.github.io/paparazzi/reference/pz_record.md)
records a block of code. For other ways to direct attention, see
[`pz_annotate()`](https://posit-dev.github.io/paparazzi/reference/pz_annotate.md)
for marks and reveals and
[`pz_annotate_spotlight()`](https://posit-dev.github.io/paparazzi/reference/pz_annotate_spotlight.md)
for a dimmed page.
[`pz_act_press(show_keys = ...)`](https://posit-dev.github.io/paparazzi/reference/pz_act_press.md)
can display a shortcut during a recording;
[`pz_record_start(captions = "both")`](https://posit-dev.github.io/paparazzi/reference/pz_record_start.md)
can write a WebVTT file alongside an MP4. For a tour of the bundled
Shiny app, start with the [Shiny apps
article](https://posit-dev.github.io/paparazzi/articles/shiny.md).
