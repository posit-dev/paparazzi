# Drag an element to another element or by an offset

Auto-waits for the source to be actionable: visible, non-empty, and
receiving pointer events at its center (not covered by another element).
With `to`, the destination is checked for visibility and that it
receives the drop at its center after the source is brought into view.
It then drags with real mouse input: press at the source's center, move
to the destination, release. When the source is a real HTML5 drag source
(`draggable`, including inherited `draggable` or the image/`<a href>`
defaults), the drag runs through the browser's drag pipeline instead:
the press and move start a genuine `dragstart` (so `dataTransfer` holds
whatever the page put there), and the drop is delivered to the
destination as trusted `dragenter`/`dragover`/`drop` events with that
payload.

While recording, the staging
([`pz_stage()`](https://posit-dev.github.io/paparazzi/reference/pz_stage.md))
shows the press at the source and glides the cursor while holding from
the source to the destination, streaming the path's real input events
(held moves, or `dragenter`/`dragover` on the HTML5 path) along the
glide, so pointer-following content tracks the cursor and intermediate
elements see the drag pass. The drop lands as the cursor arrives. On the
HTML5 path the carry runs between the page's `dragstart` and the
replayed `drop`, so `dragstart` styling stays visible through the carry,
and the real pointer stays by the source until the release, so the
destination shows no hover during the carry.

With `preview = TRUE`, an active, unpaused recording with a visible
cursor also carries a static image of the HTML5 source, captured before
`dragstart` styling. A handle inside a draggable element previews that
element. After the drop, the image briefly settles to the same source
node's new bounds, if it survives with a supported, unchanged size. The
page's source is never hidden or replaced. This is not the browser's
native drag image and does not reproduce custom
`DataTransfer.setDragImage()` feedback.

Source-related or overlapping paparazzi redactions, uncertain redaction
state, and unsupported source geometry or content references disable the
preview with a warning. Sources containing SVG `<use>` references or
iframes are not captured. Preview capture also skips documents with
imported or unreadable stylesheets, unsupported CSS rule groups,
nonembedded font source URLs, or registered fonts without a readable
embedded CSS representation. Provably separate redactions permit preview
capture. If a local `file://` page has unreadable stylesheets, serve it
over HTTP with
[`pz_serve_static()`](https://posit-dev.github.io/paparazzi/reference/pz_serve_static.md)
and open the server handle with
[`pz_open()`](https://posit-dev.github.io/paparazzi/reference/pz_open.md);
[`pz_open()`](https://posit-dev.github.io/paparazzi/reference/pz_open.md)
serves `.html` files over HTTP on its own when httpuv is installed.
Capture and other optional preview failures also warn without changing
the drag. Use `preview = FALSE` to disable capture, carry imagery, and
settling. Unrecorded, paused, hidden-cursor, and ordinary mouse drags do
no preview work.

`to` names the element to drop onto; `by = c(x, y)` drops at that offset
in pixels from the source's center. Supply exactly one.

## Usage

``` r
pz_act_drag(ctx, target, to = NULL, ..., by = NULL, preview = TRUE)
```

## Arguments

- ctx:

  A paparazzi context.

- target:

  A CSS selector string, a
  [`pz_loc()`](https://posit-dev.github.io/paparazzi/reference/pz_loc.md)
  spec, or a list of specs (a union matching any of them). The drag
  source. Unlike most actions it is always required.

- to:

  A CSS selector string, a
  [`pz_loc()`](https://posit-dev.github.io/paparazzi/reference/pz_loc.md)
  spec, or a list of specs (a union matching any of them): the drop
  target. `NULL` omits the absolute destination. Supply exactly one of
  `to` or `by`.

- ...:

  Checked empty; reserved for future use.

- by:

  Offset in pixels from the source's center, `c(x, y)` (or a single
  number for both axes). `NULL` disables the offset mode.

- preview:

  Whether to show a static source image during recorded HTML5 drags and
  a brief post-drop settling animation. Must be named.

## Value

`ctx`, invisibly.

## Acting on the page

The `pz_act_*()` functions use the page the way a person would. They
send real browser input, such as pointer moves, clicks and key presses,
or use the browser's own focus and text-selection methods. They never
set a form value directly.

An action with a `target` looks for it in the current scope and waits
until it matches an element. Inside a scope, `target = NULL` acts on the
scope's element, and scrolling with `by` or `to` scrolls the scope's
container. An explicit target is scrolled into view first when needed. A
few actions, like
[`pz_act_press()`](https://posit-dev.github.io/paparazzi/reference/pz_act_press.md),
take no target and act on the focused element instead.

While the page is recording, actions are staged as
[`pz_stage()`](https://posit-dev.github.io/paparazzi/reference/pz_stage.md)
sets them up: the cursor glides to pointer targets, typing is paced,
scrolls normally use the mouse wheel, and the page holds for the staged
`pause` afterward. Without a recording, actions go straight to their
final state.

To set a value directly instead, without staging, use
[`pz_set_value()`](https://posit-dev.github.io/paparazzi/reference/pz_set_value.md),
[`pz_set_files()`](https://posit-dev.github.io/paparazzi/reference/pz_set_files.md),
or
[`pz_set_shiny_input()`](https://posit-dev.github.io/paparazzi/reference/pz_set_shiny_input.md).

## See also

[`pz_act_click()`](https://posit-dev.github.io/paparazzi/reference/pz_act_click.md),
[`pz_act_hover()`](https://posit-dev.github.io/paparazzi/reference/pz_act_hover.md)

## Examples

``` r
page <- pz_open(pz_example("tasks"))
#> Error in startup(port = port, ...): Chrome debugging port not open after 10 seconds.
pz_get_text(page, target = ".task-title")
#> Error in pz_get_text(page, target = ".task-title"): `ctx` must be a paparazzi context (from `pz_open()` or `pz_find*()`),
#> not a function.

# The tasks are HTML5 drag sources; drop "Water the plants" on the first task
page |>
  pz_act_drag(
    pz_loc(".task", has_text = "plants"),
    to = pz_loc(".task", which = "first")
  )
#> Error in pz_act_drag(page, pz_loc(".task", has_text = "plants"), to = pz_loc(".task",     which = "first")): `ctx` must be a paparazzi context (from `pz_open()` or `pz_find*()`),
#> not a function.
pz_get_text(page, target = ".task-title")
#> Error in pz_get_text(page, target = ".task-title"): `ctx` must be a paparazzi context (from `pz_open()` or `pz_find*()`),
#> not a function.
pz_close(page)
#> Error in pz_close(page): `page` must be a page from `pz_open()`.
```
