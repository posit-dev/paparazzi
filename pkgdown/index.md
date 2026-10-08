
<!-- index.md is generated from index.Rmd. Please edit that file -->

# paparazzi <a href="https://posit-dev.github.io/paparazzi/" style="display: fixed"><img src="../man/figures/logo.png" align="right" height="138" alt="paparazzi website" /></a>

<!-- badges: start -->

[![CRAN
status](https://www.r-pkg.org/badges/version/paparazzi)](https://CRAN.R-project.org/package=paparazzi)
[![paparazzi status
badge](https://posit-dev.r-universe.dev/paparazzi/badges/version)](https://posit-dev.r-universe.dev/paparazzi)
[![R-CMD-check](https://github.com/posit-dev/paparazzi/actions/workflows/R-CMD-check.yaml/badge.svghttps://github.com/posit-dev/paparazzi/actions/workflows/R-CMD-check.yaml/badge.svghttps://github.com/posit-dev/paparazzi/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/posit-dev/paparazzi/actions/workflows/R-CMD-check.yaml)
<!-- badges: end -->

*Polished demo videos and screenshots of anything that runs in a
browser, from reusable R scripts.*

<img src="images/readme-hero-1.gif" alt="A demo of a task tracker. The view zooms in on the new-task form, a cursor clicks the title field and types Prepare release notes, then clicks Add. The view pulls back as the task appears at the top of the list, outlined in red, with the caption New tasks go to the top of the list. Under the caption Drag to reorder, the cursor drags the new task down the list and drops it just below the two high-priority tasks. Under the caption Check it off when you're done, the cursor clicks the task's Done button and the task is crossed out."  />

That video came from the short R script shown below. paparazzi opened
the page in a headless Chrome browser and did what the script said. The
cursor glides to each control, text is typed one character at a time,
and the camera zooms in on the form and pulls back to show the result.
Captions and highlights appear on cue. There’s no screen recorder
involved, and no timeline to edit afterward.

Because the video is a script, you never have to record a second take.
When the app changes, rerun the script and you get the same demo of the
new version. paparazzi works with any page Chrome can open, including
Shiny apps, Quarto documents and slides, pkgdown sites, and live
websites.

## Installation

You can install the development version of paparazzi from GitHub:

``` r
# install.packages("pak")
pak::pak("posit-dev/paparazzi")
```

### Additional requirements

paparazzi controls Chrome (or another Chromium-based browser) through
[chromote](https://rstudio.github.io/chromote/), so you’ll need one
installed. If chromote can’t find it, see `?chromote::find_chrome`.

paparazzi routes each recording to the encoder that suits it best: MP4
and WebM videos go to the [av](https://docs.ropensci.org/av/) package,
GIFs to [gifski](https://r-rust.github.io/gifski/). These are suggested
dependencies, checked only when a recording needs them. Simple GIFs need
only gifski, but two features call in extra packages: cropping a GIF to
a framed region of the page needs
[png](https://cran.r-project.org/package=png), and camera movement or
burned-in captions need av to composite the frames.

## The code that made the video

Here’s the whole script for the video at the top of this page, running
on a small task-tracker page that ships with paparazzi:

``` r
library(paparazzi)

page <- pz_open(
  pz_example("tasks"),
  width = 1000,
  height = 720,
  color_scheme = "light"
)

task_release <- pz_loc(".task", has_text = "Prepare release notes")
task_dentist <- pz_loc(".task", has_text = "Book dentist appointment")

page |>
  pz_stage(enter = "bottom", pause = 0.3) |>
  pz_stage_annotate(caption_side = "top") |>
  pz_record_start(
    frame = pz_frame(list("h1", ".task-list"), pad = 24, ratio = 16 / 9),
    format = "gif",
    scale = 800
  ) |>
  pz_annotate_caption("Add a task") |>
  pz_camera("#new-task", wait = TRUE) |>
  pz_act_type("Prepare release notes", target = "#task-title") |>
  pz_act_click("#add-task") |>
  pz_expect_visible(task_release) |>
  pz_annotate(task_release, type = "box", pad = 4, id = "new") |>
  pz_annotate_caption("New tasks go to the top of the list") |>
  pz_record_hold(1.2) |>
  pz_camera_reset() |>
  pz_annotate_clear(id = "new") |>
  pz_annotate_caption("Drag to reorder") |>
  pz_act_drag(
    pz_loc(".task-drag-handle", within = task_release),
    to = pz_loc(".task-drag-handle", within = task_dentist)
  ) |>
  pz_record_hold(1) |>
  pz_annotate_caption("Check it off when you're done") |>
  pz_find(task_release) |>
  pz_act_click(".task-done") |>
  pz_expect_class("done") |>
  pz_cursor_leave() |>
  pz_record_hold(1)

pz_close(page)
```

The first few lines set the scene. `pz_open()` opens the page at the
size you want to record. `pz_stage()` sets how the recording looks: the
cursor enters from the bottom, and each step pauses for a moment so
viewers can follow. `pz_loc()` describes the task we’re about to add, so
we can point at it once it exists.

`pz_record()` records everything in its `code` block. The `frame` is the
part of the page the video shows: the task card, from its heading to the
bottom of the list, padded and widened to 16:9. `format` and `scale`
make the result an 800-pixel-wide GIF, small enough for a README.

Inside the block, each line is one step, and the steps fall into two
groups:

- **Using the page.** `pz_act_type()` clicks the title field and types
  into it, `pz_act_click()` presses a button, and `pz_act_drag()` moves
  the new task to a new place in the list. `pz_find()` narrows the next
  steps to the new task, so `".task-done"` means that task’s Done
  button.
- **Directing the viewer.** `pz_camera()` zooms in and
  `pz_camera_reset()` pulls back out. `pz_annotate()` outlines the new
  task, `pz_annotate_caption()` changes the caption, and
  `pz_record_hold()` gives viewers a moment to read. `pz_cursor_leave()`
  moves the cursor out of the shot at the end.

`pz_expect_visible()` waits for the page to finish saving the task
before the script outlines it, and `pz_expect_class()` waits for it to
be marked done. Waits like this keep a scripted demo in step with a real
page. The video keeps rolling while the script waits, so if a step takes
longer than you’d like viewers to watch, `pz_record_pause()` and
`pz_record_resume()` cut it out.

When a recording is the last thing in a knitted R Markdown or Quarto
chunk, it appears in the document, so rendering the document again
records the demo again.

## Features

### Point the viewer at what matters

Zoom and pan the camera to a form, a button, or a whole panel with
`pz_camera()`. While it’s zoomed in, the camera pans to keep each click
and keystroke in view, so nothing happens out of the shot. The camera
only exists in the video: it never scrolls or zooms the page itself.
Outline, circle, underline, or highlight elements with `pz_annotate()`,
with numbered badges if you want them. Add callouts with arrows
(`pz_annotate_callout()`), or dim everything except one element with a
spotlight (`pz_annotate_spotlight()`). In a recording, annotations draw,
pop, fade, slide, or wipe in. They follow their elements as the page
scrolls or changes.

### Make it look like a person is using the page

The cursor glides between elements, changes shape over text fields and
links, and presses down when it clicks. Typing arrives one character at
a time at a natural pace. `pz_stage()` sets the cursor’s speed and size,
the typing speed, and the pause after each step.

### Tell the story

Captions sit at the top or bottom of the video and change as you go. You
can burn them into the video or, for MP4 and WebM, write them to a
WebVTT subtitle file alongside it. Keyboard shortcuts pressed with
`pz_act_press()` can appear on screen as keystrokes. `pz_record_hold()`
gives viewers time to read, and `pz_record_pause()` cuts out anything
they don’t need to see.

### Frame it for wherever it’s going

Crop a video or a screenshot to one element, or to several, with
padding, using `pz_frame()`. Set an aspect ratio, like 16:9 for slides
or 9:16 for a vertical video. Save MP4, WebM, or GIF files, and scale
them down to a size that suits a README.

### Make every version from one script

Record or capture the same steps on a phone, in dark mode, zoomed in, or
in another locale or time zone. `pz_device()` switches between them.
Cover private data with `pz_annotate_redact()` before recording starts,
so it stays hidden from the very first frame.

Screenshots use the same annotations and framing. Here’s the task
tracker on a phone in dark mode, with a callout:

<img src="images/readme-phone-1.png" alt="The task tracker on a narrow phone screen in dark mode. A red-bordered callout under the first task's Done button reads Tap Done to finish a task." width="300px" />

Like the recording, a screenshot at the end of a knitted chunk becomes a
figure in the document.

## Shiny apps

Give `pz_open()` the path to a Shiny app, and paparazzi runs the app in
a background R process, opens it, and waits until it’s ready. Closing
the page stops the app. `pz_set_shiny_input()` sets an input the way
Shiny sees it, so even selectize inputs and sliders update on the page
and the server responds:

``` r
app <- pz_open(pz_example("tasks-app"))

app |>
  pz_set_shiny_input("priority", "high") |>
  pz_set_value("Buy milk", target = "#title") |>
  pz_act_click("#add") |>
  pz_expect_text("3 tasks", target = "#summary")

pz_close(app)
```

Recording works the same way on an app as on any other page.

## Browser tests with paparazzi

The cursor animation and typing only happen while recording. Take away
`pz_record()` and the same steps run at full speed: the cursor stays
hidden, text goes in without the typing animation, and camera moves and
holds do nothing. That makes a demo script a browser test too.

The steps behave well in a test. Actions like `pz_act_click()` wait for
their element to be ready before acting. Expectations like
`pz_expect_text()` retry until the page shows what they expect, or time
out with an error that says what they last saw. Inside a testthat test,
expectations count as test expectations. `pz_local_page()` closes the
page, and stops its app, when the test ends:

``` r
test_that("adding a task updates the summary", {
  page <- pz_local_page(pz_example("tasks-app"))

  page |>
    pz_set_value("Buy milk", target = "#title") |>
    pz_act_click("#add") |>
    pz_expect_text("3 tasks", target = "#summary")
})
```

If you mainly want regression tests for a Shiny app’s inputs and outputs
compared against saved snapshots,
[shinytest2](https://rstudio.github.io/shinytest2/) is built for that.
paparazzi tests what a person does on the page, on any page, Shiny or
not.

## Learn more

- [Get started](articles/paparazzi.html) builds a demo video one step at
  a time, from opening a page to framing the finished recording.
- [Make a three-part app walkthrough](articles/walkthrough.html) records
  a series of short videos with camera moves, callouts, captions, and
  redactions.
- [Annotate pages](articles/annotations.html) tours every kind of mark,
  callout, spotlight, redaction, and caption.
- [Shiny apps](articles/shiny.html) covers starting apps, waiting for
  the server, setting inputs, and testing.
- The [function reference](reference/) lists every function by task.
