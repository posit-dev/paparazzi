---
name: paparazzi
description: Use when testing, screenshotting or recording web pages, Shiny apps or Quarto documents from R with the paparazzi package. Covers opening and serving pages, selecting elements, browser tests with testthat, and Shiny inputs.
---

# paparazzi

paparazzi drives a headless Chromium browser from R. One chain of actions and
expectations can be a browser test, a screenshot script or a recorded demo.
It works with static sites, running web apps, Shiny apps on disk and Quarto
documents.

## The core loop

1. **Open** a page with `pz_open()`: a URL, an app or document path, or a
   serving handle. Set the viewport when opening so the first render already
   uses it.
2. **Find** elements with CSS strings or `pz_loc()` specs. `pz_find()` returns
   a new scoped context; assign it to work inside that scope.
3. **Act, then expect.** Send input with `pz_act_*()` or `pz_set_*()`, then
   wait for the result with a `pz_expect_*()` call.
4. **Capture** the verified state with `pz_screenshot()`, or wrap the steps
   in `pz_record()` to capture them as video.
5. **Close** the page. `pz_with_page()` closes it when its code finishes, and
   `pz_local_page()` closes it when the calling test or function exits.

This script adds a task to the bundled task tracker, checks that it appears
first, and saves a screenshot of the list. Serving the page over HTTP gives it
the origin and history behavior of a deployed site.

```r
library(paparazzi)

server <- pz_serve_static(pz_example("tasks"))
image <- tempfile(fileext = ".png")
pz_with_page(server, function(page) {
  page |>
    pz_act_type("Repot the fern", target = "#task-title") |>
    pz_act_click("#add-task") |>
    pz_expect_text(
      "Repot the fern",
      target = pz_loc(".task-title", which = "first"),
      match = "exact"
    ) |>
    pz_screenshot(image, frame = pz_frame(".task-list", pad = 16))
}, width = 1000, height = 720, color_scheme = "light")
server$stop()
```

To record the same interaction, stage the page first and run the chain
inside `pz_record()`. Staging animates the cursor and typing only while a
recording runs. This GIF needs the gifski package.

```r
video <- tempfile(fileext = ".gif")
pz_with_page(pz_example("tasks"), function(page) {
  page |> pz_stage(enter = "bottom", pause = 0.2)
  page |> pz_record(video, code = {
    page |>
      pz_act_type("Repot the fern", target = "#task-title") |>
      pz_act_click("#add-task") |>
      pz_expect_visible(pz_loc(".task", has_text = "Repot the fern")) |>
      pz_record_hold(0.5)
  }, fps = 8, scale = 0.5)
}, width = 800, height = 600)
```

## Best practices

- **Read the page before choosing selectors.** Look at the app's HTML, or
  call `pz_get_elements()` and `pz_inspect()`. Target IDs, data attributes
  and meaningful classes; add `has_text` when text identifies a row.
- **Keep the root page and scopes apart.** `row <- pz_find(page, spec)`
  leaves `page` unchanged. Use `row` for row-level steps and `page` for
  whole-page checks.
- **Keep specs, refind scopes.** A `pz_loc()` spec is resolved each time it's
  used, so it survives re-renders and navigation. After the page changes,
  expect the new content, then call `pz_find()` again.
- **Expect the result of every action.** An action waits for its own target,
  not for what it causes. Follow it with an expectation on the outcome
  before reading values or taking a screenshot. Expectations retry until
  they pass or time out.
- **Pin down the device.** Pass `width`, `height` and `color_scheme` to
  `pz_open()`, plus `locale` and `timezone` when the page formats dates or
  numbers. Use `reduced_motion = TRUE` for stills.
- **Serve pages over HTTP when they navigate.** Use `pz_serve_static()` for
  HTML files, `pz_serve_quarto()` for Quarto sources and `pz_serve_shiny()`
  for apps.
- **Give screenshots a path in scripts.** With a path, `pz_screenshot()`
  writes the file and the chain continues. Without one it returns an image
  for interactive use or knitted documents.
- **Keep expectations in demos.** A recording that runs its expectations is
  also evidence that the demo reached the state it shows.
- **Know who owns each server.** A page opened from a path owns the server
  it started, and closing the page stops it. A server handle you created is
  yours to stop after its pages close.

## References

Read the reference that matches the task. Each one is also a package
vignette named `agents-<topic>`.

- [Pages and serving](references/pages-and-serving.md): what `pz_open()`
  accepts, device settings, HTTP servers, navigation and cleanup.
- [Locators and scopes](references/locators-and-scopes.md): `pz_loc()` specs,
  text and position filters, scoped contexts and moving between scopes.
- [Testing](references/testing.md): choosing expectations, waiting on
  conditions, testthat integration and inspecting failures.
- [Screenshots and annotations](references/screenshots-and-annotations.md):
  framing captures, marks, callouts, spotlights, redactions and fonts.
- [Recording and staging](references/recording-and-staging.md): recording
  formats, cursor and typing settings, camera moves and captions.
- [Shiny](references/shiny.md): app processes, Shiny readiness, setting bound
  inputs, module IDs and sharing one app across pages.

## Installing this skill

btw finds this skill whenever paparazzi is attached.
`btw::btw_skill_install_package("paparazzi")` copies it into a project's
skills directory. For other agents, copy the whole directory returned by
`system.file("skills/paparazzi", package = "paparazzi")`, including
`references/`.
