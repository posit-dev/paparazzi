---
name: paparazzi
description: Use when testing, screenshotting or recording web pages, Shiny apps and Quarto documents from R with paparazzi. Read the targeted references for serving pages, selecting elements, writing browser tests and controlling Shiny inputs.
---

# paparazzi

Use paparazzi to write R scripts that drive a Chromium browser, verify what
users see, and capture the result as PNGs or videos. The same action and
expectation chain can serve as a browser test and a recorded demonstration.
Use it for static sites, running web applications, Shiny apps on disk, and
Quarto documents or projects.

## Core loop

1. **Open** a URL, app path, document path or serving handle with `pz_open()`.
   Set the viewport before acting so layout and media queries are reproducible.
2. **Find** elements using CSS strings or reusable `pz_loc()` descriptions.
   Assign the context returned by `pz_find()` to work inside a pinned scope.
3. **Act and expect**: send input with `pz_act_*()` or set values with
   `pz_set_*()`, then wait for the intended result with `pz_expect_*()`.
4. **Capture** the verified state with `pz_screenshot()`, or put the interaction
   inside `pz_record()` to capture the steps and their result.
5. **Close** pages with `pz_close()`. For bounded work, `pz_with_page()` owns
   cleanup on block exit; in tests, `pz_local_page()` owns cleanup on test exit.

### Verify and capture a task

This complete example uses the bundled static task tracker. Serving it over
HTTP gives navigation the same origin and history behavior as a deployed site.
Chrome or another Chromium browser and the httpuv R package are required.

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
stopifnot(file.exists(image))
```

### Record the same interaction

Staging controls the cursor, typing and pauses **while recording**. Put
`pz_stage()` before `pz_record()`, then run ordinary actions and expectations
inside the recording block. This GIF example requires gifski.

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
stopifnot(file.exists(video))
```

## Best practices

- **Inspect before selecting.** Read the app's HTML or call `pz_get_elements()`
  and `pz_inspect()` to identify controls. Prefer IDs, data attributes and
  meaningful CSS classes; use `has_text` when the text identifies a row.
- **Keep the root page and scoped contexts separate.** `row <- pz_find(page,
  spec)` visibly returns a new context. Use `row` for row-local actions and
  `page` for whole-page checks. The root remains unchanged.
- **Use lazy specs across updates.** `pz_loc()` resolves when used. Keep specs
  across reactive re-renders and navigation, then create fresh pinned scopes
  with `pz_find()` once the new content is ready.
- **Wait for the result you need.** Actions wait for their own target to be
  ready. Follow an action with an expectation on its result before reading
  values or taking screenshots. Expectations retry up to the timeout.
- **Choose deterministic settings.** Set `width`, `height`, `color_scheme`,
  and any relevant `locale` or `timezone` on `pz_open()`. Choose
  `reduced_motion = TRUE` for stable stills; use normal motion for videos.
- **Serve navigation workflows over HTTP.** Use `pz_serve_static()` for
  rendered HTML, `pz_serve_quarto()` for source documents, and
  `pz_serve_shiny()` for apps. HTTP supports browser back/forward caching.
- **Capture deliberately.** Supply an explicit output `path` in scripts.
  A screenshot with a path keeps a chain going; a screenshot without one is
  an image result for an interactive session or knitted document.
- **Keep assertions in demos.** A recording is useful evidence only when the
  expected state is reached. The same expectations become testthat
  expectations inside `testthat::test_that()`.
- **Give resources an owner.** A page opened from a path owns its server.
  A page opened from a shared handle owns only its browser session. Stop the
  shared handle after all pages close; register cleanup when starting it.

## Reference index

Read only the topics relevant to the task. Each reference is also shipped as
an `agent-*` package vignette with the same content.

- [Pages and serving](references/pages-and-serving.md): opening targets,
  device settings, HTTP navigation, server ownership and reliable cleanup.
- [Locators and scopes](references/locators-and-scopes.md): reusable CSS
  specs, text and position qualifiers, pinned contexts and scope transitions.
- [Testing](references/testing.md): action/expectation loops, asynchronous
  readiness, testthat integration and browser-state diagnostics.
- [Screenshots and annotations](references/screenshots-and-annotations.md):
  **coming in phase 2**; capture framing and visual marks for still images.
- [Recording and staging](references/recording-and-staging.md):
  **coming in phase 2**; recording lifecycles and presentation controls.
- [Shiny](references/shiny.md): app processes, readiness, bound inputs,
  module IDs, shared app handles and user-facing tests.

## Find and install the skill

btw discovers this skill automatically when `library(paparazzi)` attaches the
package. To persist a copy in a project, use
`btw::btw_skill_install_package("paparazzi")`. Other agents can locate the
installed directory with `system.file("skills/paparazzi", package =
"paparazzi")` and copy the entire directory, including `references/`, into
their skill search path.
