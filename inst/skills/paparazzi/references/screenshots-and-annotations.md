# Screenshots and annotations

This reference covers saving verified page states, framing the capture and
adding marks, callouts, spotlights and redactions. The examples share one
page, run in order and write under R's temporary directory.

## Expect the state, then save it

Give `pz_screenshot()` a path in scripts. It writes a PNG and returns the
context invisibly, so the chain can continue. An existing file is overwritten.
Set the viewport and color scheme when opening, and use `reduced_motion =
TRUE` for stills. Expect the result of each action before capturing it.

```r
library(paparazzi)
page <- pz_open(
  pz_example("tasks"),
  width = 1000,
  height = 720,
  scale = 1,
  color_scheme = "light",
  reduced_motion = TRUE
)
fern <- pz_loc(".task", has_text = "Repot the fern")
page |>
  pz_act_type("Repot the fern", target = "#task-title") |>
  pz_act_click("#add-task") |>
  pz_expect_visible(fern) |>
  pz_expect_count(8, target = ".task") |>
  pz_screenshot(tempfile(fileext = ".png"))
```

At the root, the default capture is the viewport. On a scoped context it
is the scope's box. PNG dimensions are the captured CSS size multiplied by
the device pixel ratio (`scale` on `pz_open()`), so set that explicitly when
pixel dimensions matter.

## Frame the content

`pz_frame()` is a lazy spec: its target is measured when the screenshot is
taken. A selector matching several elements frames their union; a list of
selectors or `pz_loc()` specs frames the union across targets. A bare
locator passed as `frame` is shorthand for a frame around that target.

```r
page |>
  pz_screenshot(tempfile(fileext = ".png"), frame = ".task-list") |>
  pz_screenshot(
    tempfile(fileext = ".png"),
    frame = pz_frame(list("h1", "#new-task"), pad = 24, ratio = 16 / 9)
  )
```

`pad` is CSS pixels: one number for every side, or `c(top, right, bottom,
left)`. `ratio` is width divided by height; it grows the shorter side rather
than shrinking the content. `anchor` places the content within that growth,
`offset = c(x, y)` nudges the region, and `bounds` clamps it to another
locator's box. The rendered page also limits the region.

```r
page |>
  pz_screenshot(
    tempfile(fileext = ".png"),
    frame = pz_frame(
      "#new-task",
      pad = c(16, 24, 16, 24),
      ratio = 4 / 3,
      anchor = "top",
      offset = c(0, 8),
      bounds = "main"
    )
  )
```

With `zoom = NULL`, a frame fits its target plus padding. A numeric `zoom`
fixes the crop size to the viewport divided by that number and places the
target inside it. For stills this crops at the current pixel ratio; it never
upscales. `when` controls measurement for recordings, covered in Recording
and staging; screenshots always measure at capture time.

## Stage repeated framing

`pz_stage_frame()` sets a default frame for later screenshots and recordings.
Pass its targets unnamed. Each capture's unset frame fields inherit the
staged values, then the built-in defaults. A scope takes precedence over a
staged target when the capture has no target of its own.

```r
page |>
  pz_stage_frame("#new-task", pad = 16) |>
  pz_screenshot(tempfile(fileext = ".png")) |>
  pz_screenshot(
    tempfile(fileext = ".png"),
    frame = pz_frame(".filters", ratio = 16 / 9)
  ) |>
  pz_screenshot(tempfile(fileext = ".png"), frame = FALSE) |>
  pz_stage_frame(NULL)
```

`frame = FALSE` captures the scope or viewport unframed for that call.
`pz_stage_frame(NULL)` clears the default. Framing applies to stills as well
as video; it is separate from the recording-only animations in `pz_stage()`.

## Mark elements and number matches

`pz_annotate()` draws one mark per match. Types are `"box"` (outline),
`"circle"` (ellipse), `"underline"` (bottom stroke) and `"highlight"`
(translucent fill). `label = TRUE` numbers matches in order; a string or
number repeats the same badge on every match. With no label, only the mark
is drawn. Use `pad` to give the mark room around its target.

```r
page |>
  pz_annotate("#task-title", type = "box", label = "Title", pad = 4) |>
  pz_annotate("#add-task", type = "circle", pad = 6) |>
  pz_annotate("h1", type = "underline") |>
  pz_annotate(".filters a", type = "highlight", label = TRUE) |>
  pz_screenshot(
    tempfile(fileext = ".png"),
    frame = pz_frame(
      list("h1", "#new-task", ".filters"),
      pad = 16,
      target_box = "annotated"
    )
  ) |>
  pz_annotate_clear()
```

`target_box = "annotated"` includes attached marks, callouts and spotlight
cutouts on the target or its descendants. Use it to keep badges and bubbles
inside a still's frame. Redactions and annotations on unrelated elements
are excluded from this measurement.

Marks persist until cleared. Give a mark an `id` to replace or clear it
later; calls without one accumulate. Clear annotations between shots so
each image shows only the explanation intended for it.

## Style new annotations

`pz_stage_annotate()` sets page defaults for later annotations. Omitted
arguments leave a setting alone; explicit `NULL` restores its default.
Per-call styles override the staged settings. Mark badges use the mark's
`color` with white text; `label_fill` and `label_text_color` override those.
Staged `fill` and `text_color` style callout bubbles and their badges.

```r
page |>
  pz_stage_annotate(
    color = "#2563eb",
    fill = "#172554",
    text_color = "white",
    stroke_width = 2,
    distance = 20,
    font_family = '"Arial", sans-serif',
    font_size = 16
  ) |>
  pz_annotate(
    "#add-task",
    label = "Add",
    id = "button",
    label_fill = "#dbeafe",
    label_text_color = "#172554"
  ) |>
  pz_screenshot(
    tempfile(fileext = ".png"),
    frame = pz_frame("#new-task", pad = 16, target_box = "annotated")
  ) |>
  pz_annotate_clear(id = "button")
```

`reveal` chooses how a mark enters during an active, unpaused recording:
`"fade"`, `"draw"`, `"pop"`, `"slide"`, `"wipe"` or `"none"`. The default,
`"auto"`, uses fade for boxes and draw for other marks. Clearing plays the
reverse. For stills, drawing and clearing are instant.

## Explain a control with a callout

`pz_annotate_callout()` repeats literal `text` beside each match. `side`
chooses a cardinal side or a corner such as `"top right"`; leaving it unset
chooses the cardinal side with the most room. The bubble stays within the
viewport. Set the viewport before drawing so the text wraps for that size.

```r
page |>
  pz_annotate_callout(
    "New tasks appear first",
    target = "#add-task",
    side = "bottom",
    leader = c(start = "dot", end = "arrow"),
    label = "1",
    id = "explanation"
  ) |>
  pz_screenshot(
    tempfile(fileext = ".png"),
    frame = pz_frame("#new-task", pad = 12, target_box = "annotated")
  ) |>
  pz_annotate_clear(id = "explanation")
```

`leader = TRUE` draws an arrow at the target; `FALSE` makes a tooltip-style
bubble. A named vector sets `start` and `end` decorations to `"none"`,
`"arrow"`, `"dot"` or `"bar"`. `distance` sets the bubble's gap in CSS pixels,
and `stroke_width` sets the leader width. Callout `reveal` defaults to
`"pop"`, with the same explicit choices as marks.

## Spotlight a region

`pz_annotate_spotlight()` dims the document except for a cutout around each
match. `dim` ranges from 0 (transparent) to 1 (black); `pad` grows the
cutouts. Each call replaces the page's one spotlight.

```r
page |>
  pz_annotate_spotlight(
    list("#task-title", "#add-task"),
    pad = 6,
    dim = 0.65
  ) |>
  pz_screenshot(tempfile(fileext = ".png"), frame = "main") |>
  pz_annotate_clear(id = "spotlight")
```

Marks, badges, spotlight cutouts and redactions follow their targets and
clip with the targets' overflow containers. A fully clipped target, or a
hidden target without visible descendants, hides its annotation. Scroll the
intended target into view and
expect it before capturing. A callout hides when its target is fully
clipped; for a partly clipped target its leader points at the visible part,
while the bubble stays unclipped. Clipping is axis-aligned and follows
`overflow`, with the standard clipping edge rather than a custom
`overflow-clip-margin`.

## Cover private content before capture

Use `pz_annotate_redact(method = "fill")` for secrets. The opaque cover
follows the target's border box plus `pad`; target overflowing content
itself or add padding to cover it. `method = "blur"` provides a visual blur
for non-secret content. Apply redactions before starting a recording so
its first frame is already covered. Recording and staging covers the
recorder's lifecycle.

```r
page |>
  pz_annotate_redact(
    '[data-priority="high"] .task-title',
    method = "fill",
    pad = 2,
    id = "private"
  ) |>
  pz_screenshot(tempfile(fileext = ".png"), frame = ".task-list") |>
  pz_annotate_clear(id = "private")
```

Annotations belong to the current document and are removed on navigation.
For a multi-page recording, prepare each document's redactions before
resuming capture. `pz_annotate_clear()` with no `id` clears all annotations;
`"spotlight"` and `"caption"` are reserved ids for those types.

## Load fonts before annotating

`pz_stage_fonts()` waits for font faces to load before returning. Declare
remote faces with `pz_font_google()` or `pz_font_bunny()`, using the provider's
family name, `weight` (400 is regular) and `style` (`"normal"` or `"italic"`).
Chrome fetches the fonts, so remote staging needs network access and a page
policy that permits it. Use CSS family strings with a generic fallback in
`font_family`.

```r
page |>
  pz_stage_fonts(pz_font_google("Inter"), pz_font_bunny("Lato")) |>
  pz_stage_annotate(font_family = '"Inter", sans-serif') |>
  pz_annotate("#add-task", label = "Add", font_family = '"Lato", sans-serif') |>
  pz_screenshot(
    tempfile(fileext = ".png"),
    frame = pz_frame("#new-task", pad = 16, target_box = "annotated")
  ) |>
  pz_annotate_clear()
```

For offline scripts, `pz_font_file()` reads a local `.woff2`, `.woff`, `.ttf`
or `.otf` and passes its bytes directly to the page. This example uses the
Open Sans file bundled with rmarkdown; use a licensed project font for your
own app. Repeated staging adds faces and replaces matching family/weight/
style combinations. Staged faces survive recordings and are re-added to a
new document when annotations first need them after navigation.

```r
font_path <- system.file(
  "rmd/h/bootstrap/css/fonts/OpenSans.ttf",
  package = "rmarkdown",
  mustWork = TRUE
)
page |>
  pz_stage_fonts(pz_font_file("Project Sans", font_path)) |>
  pz_stage_annotate(font_family = '"Project Sans", sans-serif') |>
  pz_annotate_callout("Ready to add", target = "#add-task", side = "bottom") |>
  pz_screenshot(
    tempfile(fileext = ".png"),
    frame = pz_frame("#new-task", pad = 16, target_box = "annotated")
  ) |>
  pz_annotate_clear()
pz_close(page)
```

## Include a screenshot in R Markdown

In a knitted chunk, end with `pz_screenshot()` without a path. It returns a
knitr image and writes a numbered PNG into the chunk's figure directory.
The image is a terminal result; use explicit paths for intermediate
screenshots that should keep a chain running. Put this block in an R Markdown
chunk. `pz_local_page()` closes the page when the function returns the image.

```r
task_figure <- function() {
  page <- pz_local_page(
    pz_example("tasks"), width = 1000, height = 720,
    color_scheme = "light", reduced_motion = TRUE
  )
  page |>
    pz_expect_count(7, target = ".task") |>
    pz_screenshot(frame = pz_frame(".task-list", pad = 16))
}
task_figure()
```
