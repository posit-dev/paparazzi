# Pages and serving

Use this reference to choose an opening target, run local servers, set device
emulation, navigate, and give every browser session and server a cleanup owner.
All examples below run in order. They write files under R's temporary directory.

## Choose the opening target

`pz_open(x)` returns the root `PaparazziPage`, which starts a `|>` chain.
It accepts a URL, local path, serving handle or existing ChromoteSession.
For path-based opening, the page starts a server when needed and owns it.
Closing that page stops the server as well as its browser session.

| Target | Opening behavior |
| --- | --- |
| HTTP URL | Navigate to an already running site |
| Shiny app directory or runnable app file | Start a background R app process |
| `.qmd`, `.Rmd`, or directory with `_quarto.yml` | Start Quarto preview |
| Other directory | Serve static files over HTTP |
| Other existing file, including HTML | Open the file directly |
| Serving handle | Open a browser page on the handle's URL |
| ChromoteSession | Wrap the existing session without navigating |

Shiny path detection comes before Quarto detection. A Shiny directory contains
`app.R` or `server.R`; supply the app directory or a runnable app file.
For an app already running elsewhere, use its HTTP URL with `wait = "shiny"`.

For a bounded read of the bundled static page, use the function form of
`pz_with_page()`. Its callback receives the page and cleanup runs on exit,
including when code raises an error. `pz_with_page()` returns the closed page
invisibly; assign readings within the callback when retaining them.

```r
library(paparazzi)

heading <- NULL
pz_with_page(pz_example("tasks"), function(page) {
  heading <<- pz_get_text(page, target = "h1")
}, width = 1000, height = 720)
stopifnot(identical(heading, "Tasks"))
```

## Serve static pages over HTTP

Use `pz_serve_static()` for local HTML when links, history or navigation are
part of the task. HTTP allows the browser's back/forward cache and gives
relative links their usual site behavior. The server accepts a directory or
an HTML file. For a file, it serves the containing directory and points the
handle's URL at that file; neighboring assets are also available.

```r
server <- pz_serve_static(pz_example("tasks"))
page <- pz_open(server, width = 1000, height = 720)
page |> pz_expect_url("http://127.0.0.1", match = "contains")
server$is_running()
```

Opening two pages from the same handle shares the server, not page state.
The caller owns that server. Close every page and call `server$stop()` after
all uses; `$stop()` is idempotent. For a single-use directory,
`pz_open(directory)` instead gives server ownership to the page.

## Set the viewport before capturing

Named device arguments on `pz_open()` are forwarded to `pz_device()` before
navigation, so the first render sees the intended media queries. Set the
viewport to a known CSS size and the color scheme to a known preference.
`scale` is the device pixel ratio; the PNG pixel dimensions reflect it.
Setting width, height or mobile switches the default scale to 2 unless a
scale is supplied explicitly.

```r
phone <- pz_open(
  server,
  width = 390,
  height = 844,
  scale = 1,
  mobile = TRUE,
  color_scheme = "light"
)
phone |> pz_expect_visible(target = "#new-task")
pz_close(phone)
```

`pz_device()` changes only supplied settings. `NULL` leaves the device setting
unchanged; use `zoom = 1` to return to normal zoom. `zoom_method = "viewport"`
changes the effective CSS viewport, including media queries;
`zoom_method = "css"` keeps media queries and applies CSS zoom to the document.
Use `reduced_motion = TRUE` when still captures need stable animation state.
Choose motion settings for the intended capture, and set them before recording.

```r
page |>
  pz_device(
    color_scheme = "light",
    reduced_motion = TRUE,
    locale = "en-US",
    timezone = "UTC",
    zoom = 1
  ) |>
  pz_expect_visible(target = ".task-list")
```

## Navigate and re-scope

Navigation functions return a root context and release existing pinned
scopes. Keep reusable `pz_loc()` descriptions across navigation, then call
`pz_find()` again on the returned root to pin the new document's elements.
`pz_nav_goto()` and `pz_nav_reload()` settle the document by default.
`pz_nav_back()` and `pz_nav_forward()` settle load and return immediately at
a history boundary.

The task page's filters change the URL fragment. Verify the visible outcome
after settling navigation because app-specific updates can occur afterward.

```r
base_url <- pz_get_url(page)
page |>
  pz_nav_goto(paste0(base_url, "#done")) |>
  pz_expect_url("#done", match = "contains") |>
  pz_expect_count(1, target = ".task.done:not(.hidden)")

page |>
  pz_nav_back() |>
  pz_expect_url(base_url, match = "exact")

page |>
  pz_nav_forward() |>
  pz_expect_url("#done", match = "contains")

page |>
  pz_nav_goto(base_url) |>
  pz_expect_visible(target = ".task-list")
task_list <- pz_find(page, ".task-list")
pz_get_count(task_list, target = ".task")
```

For navigation triggered by a click, follow the action with
`pz_wait_for_navigation()`, then assert the destination. It synchronizes with
the navigation associated with the last action. For a known destination,
`pz_expect_url()` can wait for that URL; a content expectation checks that the
user-facing result is ready too. See Testing for a full two-document example.

## Preview a Quarto document

`pz_serve_quarto()` runs the Quarto CLI for a `.qmd`, `.Rmd` or project
containing `_quarto.yml`. The CLI must be on PATH or available through
`QUARTO_PATH`. A standalone document is rendered on startup; `render = TRUE`
requests a full render for preview. Use `render = FALSE` when intentionally
reusing project execution results. Keep input resources stable during capture.
For rendered HTML, choose `pz_serve_static()` instead.

This creates a minimal source document with no executable code. It needs
Quarto, but no application-specific files.

```r
doc_dir <- tempfile("paparazzi-doc-")
dir.create(doc_dir)
doc <- file.path(doc_dir, "index.qmd")
writeLines(c(
  "---",
  "title: Preview example",
  "format: html",
  "---",
  "",
  "# Ready",
  "",
  "A document served for a browser check."
), doc)
preview <- pz_serve_quarto(doc, render = TRUE)
pz_with_page(preview, function(doc_page) {
  doc_page |> pz_expect_text("Ready", target = pz_loc("h1", has_text = "Ready"))
})
preview$stop()
unlink(doc_dir, recursive = TRUE)
```

Quarto and Shiny handles expose `$logs()` and `$is_running()` for diagnostics.
A static handle has the same interface and returns an empty log vector.
For interactive documents, serve the application through Shiny rather than
Quarto preview. See Shiny for process options and input bindings.

## Finish with explicit resource ownership

The `page` above owns a browser session; `server` owns the HTTP service.
Close the browser before stopping the service it uses.

```r
pz_close(page)
server$stop()
```

In functions, register `withr::defer(server$stop())` immediately after creating
a shared handle, and use `pz_with_page()` for each page. In tests,
`pz_local_page()` binds page cleanup to the test's calling frame. Both cleanup
helpers accept a page already opened elsewhere: using it in the block or test
transfers responsibility for closing that page to the helper.
