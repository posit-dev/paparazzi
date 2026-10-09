# Record an in-depth app walkthrough

In this article, we’ll record an in-depth walkthrough of the task
tracker bundled with paparazzi. It’s a video that takes the viewer
through many steps of using the app, the kind you might put at the top
of an app’s documentation.

We’ll record the walkthrough in three sections, walking through the code
at each step. Each section picks up where the last one left the app. The
three sections could be three videos on a landing page, or you could
combine them into a single demo video, as [the last
section](#from-sections-to-one-video) shows.

The [Get started
article](https://posit-dev.github.io/paparazzi/articles/paparazzi.md)
introduces each tool we’ll use, and it’s a good place to start to learn
about actions, expectations, frames, staging, the camera, and
annotations. Here we’ll focus on putting them together and pacing a
longer video. You’ll need a Chromium-based browser and the av package to
encode MP4 files.

## Plan the demo

A longer video needs a plan before it needs a script. For each section,
we decide what the person watching should learn, what they need to
notice, and which tools will point it out:

| Section | The viewer learns | We direct attention with |
|----|----|----|
| [Add an urgent task](#add-an-urgent-task) | Urgent tasks are high priority, and Enter adds a task | A [camera](https://posit-dev.github.io/paparazzi/reference/pz_camera.md) zoom, a [callout](https://posit-dev.github.io/paparazzi/reference/pz_annotate_callout.md), a [keystroke callout](https://posit-dev.github.io/paparazzi/reference/pz_act_press.md), and a [box](https://posit-dev.github.io/paparazzi/reference/pz_annotate.md) around the result |
| [Organize the list](#organize-the-list) | Tasks can be renamed, reordered, and finished | A [caption](https://posit-dev.github.io/paparazzi/reference/pz_annotate_caption.md) for each step and a [spotlight](https://posit-dev.github.io/paparazzi/reference/pz_annotate_spotlight.md) on the list |
| [Hide private details](#hide-private-details) | The help panel explains the app | [Redactions](https://posit-dev.github.io/paparazzi/reference/pz_annotate_redact.md) that hide private titles before the viewer sees them |

Some aspects of our recording will be the same in all three videos, so
we’ll set those shared choices up front:

``` r

library(paparazzi)

page <- # [1] Open the task tracker
  pz_open(
    pz_example("tasks"),
    width = 800,
    height = 900,
    color_scheme = "light"
  ) |>
  pz_stage(enter = "top", pause = 0.2) # [2] Stage every step


card <- pz_frame("main", pad = 12, when = "start") # [3] Frame the card
```

1.  [`pz_open()`](https://posit-dev.github.io/paparazzi/reference/pz_open.md)
    starts a headless browser and opens the page, and
    [`pz_example()`](https://posit-dev.github.io/paparazzi/reference/pz_example.md)
    returns the path to the task tracker that comes with paparazzi.

    The viewport is 800 by 900 pixels with the light color scheme, and
    each section records at the same frame rate and size, so the three
    videos match.

2.  [`pz_stage()`](https://posit-dev.github.io/paparazzi/reference/pz_stage.md)
    sets how paparazzi stages every step on this page: the cursor glides
    in from the top when it first appears, and each step pauses for 0.2
    seconds, so the viewer can keep up.

3.  `card` frames the recordings on the task tracker’s card. With
    `when = "start"`, paparazzi measures the card when each recording
    starts, so the frame stays put while the list changes. The last
    section uses its own frame, for a reason we’ll get to.

## Add an urgent task

First, we’ll show the viewer how to add a new task. The viewer needs to
see the Urgent checkbox and what it does, the keystroke that submits the
task, and the new task in the list.

We’ll describe the new task with a [location
spec](https://posit-dev.github.io/paparazzi/reference/pz_loc.md) first,
so the script can wait for it and mark it:

``` r

release_notes <- pz_loc(".task", has_text = "Prepare release notes")

page |>
  pz_record_start(frame = card, fps = 8, scale = 0.6) |>
  pz_annotate_caption("Add an urgent task") |>
  # [1] Zoom in, then act
  pz_camera(pz_frame("#new-task", zoom = 1.5, anchor = "left"), wait = TRUE) |>
  # [2] Explain, then move on
  pz_act_click("#task-urgent") |>
  pz_annotate_callout(
    "Urgent tasks are high priority",
    target = "#task-urgent",
    side = "bottom",
    id = "urgent"
  ) |>
  pz_record_hold(1) |>
  pz_annotate_clear(id = "urgent") |>
  # [3] Show the keystroke
  pz_act_type("Prepare release notes", target = "#task-title") |>
  pz_act_press("Enter", show_keys = "words") |>
  # [4] Pull back for the result
  pz_camera_reset() |>
  pz_expect_visible(release_notes) |>
  pz_annotate(release_notes, type = "box", pad = 4) |>
  pz_record_hold(1)
```

[Download
recording](https://posit-dev.github.io/paparazzi/articles/demo-video_files/figure-html/add-task-1.mp4)

The script does one thing at a time, so the viewer can follow it:

1.  **Zoom in, then act.**
    [`pz_camera()`](https://posit-dev.github.io/paparazzi/reference/pz_camera.md)
    zooms in 1.5 times on the left side of the form, where the title
    field starts and the Urgent checkbox sits, and `wait = TRUE` lets
    the camera arrive before the cursor moves. While the camera is
    zoomed in, paparazzi pans it to keep each click and keystroke in
    view.
2.  **Explain, then move on.** The callout appears after the click on
    Urgent,
    [`pz_record_hold()`](https://posit-dev.github.io/paparazzi/reference/pz_record_hold.md)
    gives the viewer a second to read it, and
    [`pz_annotate_clear()`](https://posit-dev.github.io/paparazzi/reference/pz_annotate_clear.md)
    removes it before typing starts. paparazzi adds the hold to the
    video only, so it doesn’t slow down the script outside a recording.
3.  **Show the keystroke.** The task tracker adds a task when you press
    Enter in the title field.
    [`pz_act_press()`](https://posit-dev.github.io/paparazzi/reference/pz_act_press.md)
    presses Enter in the field that
    [`pz_act_type()`](https://posit-dev.github.io/paparazzi/reference/pz_act_type.md)
    left focused, and `show_keys = "words"` shows the key on screen,
    since a keypress is otherwise invisible in a video.
4.  **Pull back for the result.**
    [`pz_camera_reset()`](https://posit-dev.github.io/paparazzi/reference/pz_camera_reset.md)
    returns to the whole card. The task tracker shows “Saving…” before
    it adds the task, so
    [`pz_expect_visible()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_visible.md)
    waits for the new task before
    [`pz_annotate()`](https://posit-dev.github.io/paparazzi/reference/pz_annotate.md)
    draws a box around it.

The section ends with the box and caption still on the page. Annotations
belong to the page, not to the recording: paparazzi draws them into the
page itself, which is how they follow their elements as the page moves
and why they show up in screenshots too. The recorder only captures what
the page shows, so the next section would inherit them. We’ll clear them
between sections:

``` r

page |> pz_annotate_clear()
```

## Organize the list

The second section shows three ways to organize the list: renaming a
task, dragging a task to a new place, and marking a task done. These
steps act on individual tasks, so we’ll describe the tasks first.
There’s a lot for the viewer to follow, so we’ll also slow this section
down:

``` r

dentist <- pz_loc(".task", has_text = "Book dentist appointment")
plants <- pz_loc(".task", has_text = "Water the plants")
taxes <- pz_loc(".task", has_text = "File tax return")

page |>
  # [1] Slow down
  pz_stage(cursor_speed = 350, typing_speed = 10, pause = 0.6) |>
  pz_record_start(frame = card, fps = 8, scale = 0.6) |>
  # [2] Rename a task
  pz_annotate_caption("Rename a task") |>
  pz_find(dentist) |>
  pz_act_click(".task-edit") |>
  pz_act_select_text("dentist", target = ".task-title") |>
  pz_find_reset() |>
  pz_act_type("eye doctor") |>
  pz_act_press("Enter") |>
  # [3] Reorder the list
  pz_annotate_caption("Drag tasks to reorder them") |>
  pz_annotate_spotlight(".task-list", pad = 4) |>
  pz_act_drag(plants, to = taxes) |>
  pz_annotate_clear(id = "spotlight") |>
  # [4] Finish a task
  pz_annotate_caption("Mark a task done, then show open tasks") |>
  pz_find(taxes) |>
  pz_act_click(".task-done") |>
  pz_find_reset() |>
  pz_act_click(".filters a[href='#open']") |>
  pz_expect_visible(plants) |>
  pz_record_hold(1)
```

[Download
recording](https://posit-dev.github.io/paparazzi/articles/demo-video_files/figure-html/organize-1.mp4)

paparazzi shows one caption at a time. Each call to
[`pz_annotate_caption()`](https://posit-dev.github.io/paparazzi/reference/pz_annotate_caption.md)
replaces the caption on screen, and while recording, the old caption
fades out as the new one appears. That makes it easy to give each step
its own caption, so the caption always describes what the viewer is
watching. The steps fall into four groups:

1.  **Slow down.**
    [`pz_stage()`](https://posit-dev.github.io/paparazzi/reference/pz_stage.md)
    slows the cursor to 350 pixels per second and typing to 10
    characters per second, and pauses 0.6 seconds after each step
    instead of 0.2. Staged settings stay on the page until we change
    them, so we’ll restore the faster pace after this section.
2.  **Rename a task.**
    [`pz_find()`](https://posit-dev.github.io/paparazzi/reference/pz_find.md)
    narrows the chain to the dentist task, so `.task-edit` and
    `.task-title` mean that task’s Edit button and title. Clicking Edit
    makes the title editable, and
    [`pz_act_select_text()`](https://posit-dev.github.io/paparazzi/reference/pz_act_select_text.md)
    selects the word “dentist”.
    [`pz_find_reset()`](https://posit-dev.github.io/paparazzi/reference/pz_find_reset.md)
    returns to the whole page before typing: with a scope,
    [`pz_act_type()`](https://posit-dev.github.io/paparazzi/reference/pz_act_type.md)
    would click the task first and lose the selection. Without a target,
    it types into the focused title, replacing the selected word, and
    Enter saves the new title.
3.  **Reorder the list.**
    [`pz_annotate_spotlight()`](https://posit-dev.github.io/paparazzi/reference/pz_annotate_spotlight.md)
    dims everything but the list, drawing the viewer’s attention to the
    drag action.
    [`pz_act_drag()`](https://posit-dev.github.io/paparazzi/reference/pz_act_drag.md)
    drags “Water the plants” onto “File tax return”, using the same
    mouse input a person would. While paparazzi records, the cursor
    carries an image of the task as it glides. The spotlight’s id is
    always `"spotlight"`, so `pz_annotate_clear(id = "spotlight")`
    removes it once the task lands.
4.  **Finish a task.**
    [`pz_find()`](https://posit-dev.github.io/paparazzi/reference/pz_find.md)
    narrows the chain again so `.task-done` means the tax task’s Done
    button. Then a click on the Open filter hides finished tasks, and
    [`pz_expect_visible()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_visible.md)
    checks that “Water the plants” is still in the list.

This section never moves the camera. The list fits in the frame, and the
spotlight already shows the viewer where to look. Use the camera when
the action is too small to see, not for every step.

Before the next section, we’ll clear the annotations and return to the
pace we set at the start:

``` r

page |>
  pz_annotate_clear() |>
  pz_stage(cursor_speed = NULL, typing_speed = NULL, pause = 0.2)
```

## Hide private details

The last section opens the help panel. We’ll treat the titles of the
high-priority tasks as private, so we’ll cover them with redactions. A
redaction has to be in place before the first frame that would show the
private text, or the video shows the text before paparazzi covers it.

The recording starts on the Open filter that the last section left
behind. To show every task, we need to switch back to All, but the
viewer doesn’t need to see that.
[`pz_record_pause()`](https://posit-dev.github.io/paparazzi/reference/pz_record_pause.md)
pauses the recording: paparazzi captures nothing until
[`pz_record_resume()`](https://posit-dev.github.io/paparazzi/reference/pz_record_pause.md),
and the pause leaves no gap in the video. We’ll set up the page during
the pause:

``` r

page |>
  # [1] A frame measured at the end
  pz_record_start(frame = pz_frame("main", pad = 12), fps = 8, scale = 0.6) |>
  # [2] A caption out of the way
  pz_annotate_caption("Open the help panel", side = "top") |>
  pz_record_pause() |>
  pz_act_click(".filters a[href='#all']") |>
  # [3] Fill, not blur
  pz_annotate_redact(
    "[data-priority='high'] .task-title",
    method = "fill",
    id = "private-tasks"
  ) |>
  pz_record_resume() |>
  pz_act_click("#toggle-help") |>
  pz_expect_visible(target = "#help") |>
  pz_record_hold(1)
```

[Download
recording](https://posit-dev.github.io/paparazzi/articles/demo-video_files/figure-html/share-1.mp4)

The video starts with the redactions already in place. A few details
make this section work:

1.  **A frame measured at the end.** The help panel opens below the
    card.
    [`pz_frame()`](https://posit-dev.github.io/paparazzi/reference/pz_frame.md)
    measures the frame when the recording stops by default, so the frame
    includes the open panel. `card` measures the card at the start,
    before the panel opens, so it would cut the panel off.
2.  **A caption out of the way.** `side = "top"` puts the caption above
    the card, so it doesn’t cover the help panel.
3.  **Fill, not blur.** `method = "fill"`, the default, covers each
    title with a solid box. `method = "blur"` only obscures the text, so
    we spell out the fill to make the choice clear. Each redaction
    follows its task as the list changes.

We’re done with the demo, so we’ll remove the annotations and close the
browser:

``` r

page |> pz_annotate_clear()
pz_close(page)
```

## From sections to one video

We recorded three videos so each one sits next to its code, but you can
record the whole walkthrough as one video. Start the recording once, and
run each section’s steps in turn. Between sections,
[`pz_record_pause()`](https://posit-dev.github.io/paparazzi/reference/pz_record_pause.md)
and
[`pz_record_resume()`](https://posit-dev.github.io/paparazzi/reference/pz_record_pause.md)
hide the setup, like clearing the last section’s annotations, so the
video moves straight from one section to the next.

Some choices make more sense for a single video. In this article, the
redactions come last because they’re easier to explain on their own. In
a real walkthrough, you’d add them before the recording starts, so they
cover the private titles in every section.

To give viewers captions they can turn on or off,
`pz_record_start(captions = "vtt")` writes them to a WebVTT file next to
the MP4 instead of drawing them on the video. For more ways to direct
attention, like reveal animations and numbered marks, see the
[annotations
article](https://posit-dev.github.io/paparazzi/articles/annotations.md).
