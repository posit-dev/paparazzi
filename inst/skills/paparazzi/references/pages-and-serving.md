# Pages and serving

This reference covers what to open, how to serve local files, device
settings, navigation and cleanup. The examples run in order and write files
under R's temporary directory.

## Choose what to open

`pz_open(x)` returns the root page, which starts a `|>` chain. When `x` is a
path that needs a server, the page starts one and owns it, so closing the
page stops the server too.

| Target | Opening behavior |
| --- | --- |
| HTTP URL | Navigate to an already running site |
| Shiny app directory or runnable app file | Start a background R app process |
| `.qmd`, `.Rmd`, or directory with `_quarto.yml` | Start Quarto preview |
| Other directory | Serve static files over HTTP |
| `.html` file | Serve the file over HTTP when httpuv is installed, as `file://` otherwise |
| Other existing file | Open the file directly |
| Serving handle | Open a browser page on the handle's URL |
| ChromoteSession | Wrap the existing session without navigating |

Shiny detection runs before Quarto detection: a directory with `app.R` or
`server.R` is a Shiny app. For an app that's already running, open its URL
with `wait = "shiny"`.

For a short task, `pz_with_page()` opens the page, passes it to a function
and closes it afterward, even if the code errors. Put the checks inside the
function.

```r
library(paparazzi)

pz_with_page(pz_example("tasks"), function(page) {
  page |> pz_expect_text("Tasks", target = "h1", match = "exact")
}, width = 1000, height = 720)
```

## Serve static pages over HTTP

Local HTML benefits from HTTP whenever links, history or navigation matter:
relative links resolve as on a real site and the browser's back/forward cache
works. `pz_open()` serves `.html` files itself when httpuv is installed, with
the file's directory as the server root.

```r
page <- pz_open(pz_example("tasks"), width = 1000, height = 720)
page |> pz_expect_url("http://127.0.0.1", match = "contains")
```

`pz_serve_static()` creates a handle you can share across pages. For an
HTML file, pass `root` to serve a wider directory while still navigating
to the file, such as a pkgdown or Quarto subpage referencing
`../site_libs/`. Pages opened from the same handle share the server but
nothing else. You own that server: close its pages, then call
`server$stop()`, which is safe to call twice.

## Set the viewport when opening

Device arguments to `pz_open()` are applied before the page loads, so the
first render already sees them. `scale` is the device pixel ratio, which sets
the PNG's pixel size. Once you set `width`, `height` or `mobile`, the scale
defaults to 2 unless you give one.

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

`pz_device()` changes only the settings you pass. `zoom = 1` returns to
normal zoom. `zoom_method = "viewport"` shrinks the CSS viewport, so media
queries respond; `zoom_method = "css"` zooms the document and leaves media
queries alone. Set motion preferences before recording: `reduced_motion =
TRUE` suits stills.

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

## Navigate, then refind scopes

Navigation functions return the root context and release pinned scopes. Keep
your `pz_loc()` specs and call `pz_find()` again on the new document.
`pz_nav_goto()` and `pz_nav_reload()` wait for the document to settle.
`pz_nav_back()` and `pz_nav_forward()` wait for the load, and return right
away when there's no history in that direction.

The task page's filters change the URL fragment. After navigating, expect
the visible result, since the app may update the page after the load.

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

When a click starts a navigation, follow it with `pz_wait_for_navigation()`,
then expect something on the destination page. Testing has a full
two-page example.

## Preview a Quarto document

`pz_serve_quarto()` runs Quarto preview on a `.qmd`, an `.Rmd` or a project
with `_quarto.yml`. Quarto must be on the PATH or set in `QUARTO_PATH`.
`render = TRUE` renders the document fully before preview. For HTML that's
already rendered, open it with `pz_open()`.

This example writes a small document with no code chunks and checks its
heading.

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

Quarto, Shiny and static handles all have `$logs()` and `$is_running()`; a
static handle's log is always empty. Serve interactive documents through
Shiny instead of Quarto preview (see Shiny).

## Close the page, then stop the server

Here `page` owns a browser session and `server` owns the HTTP service. Close
the page first.

```r
pz_close(page)
server$stop()
```

Inside a function, call `withr::defer(server$stop())` right after creating a
shared handle, and use `pz_with_page()` for each page. In tests, use
`pz_local_page()`. Both also accept a page that's already open, and take over
closing it.
