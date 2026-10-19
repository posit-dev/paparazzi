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

## Drag preview

With `preview = TRUE`, paparazzi carries a static image of the HTML5
drag source during an active, unpaused recording with a visible cursor.
Paparazzi captures the image before `dragstart` styling; a handle inside
a draggable element previews that element. After the drop, the image
briefly settles to the same source node's new bounds if it survives with
a supported, unchanged size. Paparazzi never hides or replaces the
page's source. The preview is not the browser's native drag image and
does not reproduce custom `DataTransfer.setDragImage()` feedback.

Paparazzi disables the optional preview with a warning in these cases.
The drag continues without the preview.

- **Unreadable stylesheets**, often on `file://` pages: open the page
  over HTTP.
  [`pz_open()`](https://posit-dev.github.io/paparazzi/reference/pz_open.md)
  serves local `.html` paths over HTTP when httpuv is installed and
  loads. You can also serve the page with
  [`pz_serve_static()`](https://posit-dev.github.io/paparazzi/reference/pz_serve_static.md)
  and open the server handle with
  [`pz_open()`](https://posit-dev.github.io/paparazzi/reference/pz_open.md).
  Cross-origin stylesheets must also allow the browser to read their
  rules.

- **Iframes or SVG `<use>` references in the source**: use a source
  without these references; they can copy content outside the source
  subtree.

- **Unsupported CSS rule groups, imported stylesheets, or font
  sources**: move rules out of unsupported groups or imports and embed
  font sources as data URLs in `@font-face` rules. Registered fonts also
  need a readable embedded CSS representation.

- **Source-related or overlapping paparazzi redactions, or uncertain
  redaction state**: keep redactions separate from the source or turn
  off the preview. Paparazzi permits capture only when it can verify
  that redactions are separate; do not remove redactions from sensitive
  content for a preview.

- **Unsupported source geometry or content**: use a source without
  transforms, filters, clipping, overflowing content, shadow DOM, or
  generated content. Fixed or sticky descendants and out-of-box
  positioned content are also unsupported.

Other preview failures report the underlying error message. Use
`preview = FALSE` to turn off capture, carry imagery, and settling.
Unrecorded, paused, hidden-cursor, and ordinary mouse drags do no
preview work.

## Acting on the page

The `pz_act_*()` functions use the page the way a person would. They
send real browser input, such as pointer moves, clicks and key presses,
or use the browser's own focus and text-selection methods. They never
set a form value directly.

An action with a `target` looks for it in the current scope and waits
until it matches an element. Inside a scope, `target = NULL` normally
acts on the scope's element;
[`pz_act_type()`](https://posit-dev.github.io/paparazzi/reference/pz_act_type.md)
can instead preserve a held selection in a focused editable descendant.
Scrolling with `by` or `to` scrolls the scope's container. An explicit
target is scrolled into view first when needed. A few actions, like
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
pz_get_text(page, target = ".task-title")
#> [1] "Renew passport"           "File tax return"         
#> [3] "Book dentist appointment" "Return library books"    
#> [5] "Water the plants"         "Sort out the garage"     
#> [7] "Call the bank"           

# The tasks are HTML5 drag sources; drop "Water the plants" on the first task
page |>
  pz_act_drag(
    pz_loc(".task", has_text = "plants"),
    to = pz_loc(".task", which = "first")
  )
pz_get_text(page, target = ".task-title")
#> [1] "Water the plants"         "Renew passport"          
#> [3] "File tax return"          "Book dentist appointment"
#> [5] "Return library books"     "Sort out the garage"     
#> [7] "Call the bank"           
pz_close(page)
```
