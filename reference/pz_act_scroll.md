# Scroll the page or an element into view

Exactly one of `target`, `by`, and `to`:

- `target`: auto-waits for a match, then scrolls it into view (instantly
  outside a recording).

- `by = c(x, y)`: scrolls the current scope's scroll container – the
  scope element or its nearest scrollable ancestor, or the page itself
  at the root context – by that many pixels.

- `to`: scrolls that same container to an edge or corner from the
  direction vocabulary: `"top"`, `"bottom"`, `"left"`, `"right"`, the
  four corners, or `"center"` (e.g. `"bottom"` scrolls to the end;
  `"top right"` to the top-right corner).

Scrolling is instant outside a recording; while recording it is staged
as real mouse wheel events with the cursor over the container, so the
video shows the scroll. Wheel scrolling is best-effort: if the page
swallows the events, the instant scroll still guarantees the final
position.

## Usage

``` r
pz_act_scroll(ctx, target = NULL, ..., by = NULL, to = NULL, duration = NULL)
```

## Arguments

- ctx:

  A paparazzi context.

- target:

  A CSS selector string, a
  [`pz_loc()`](https://posit-dev.github.io/paparazzi/reference/pz_loc.md)
  spec, or a list of specs (a union matching any of them). Scrolled into
  view. `NULL` disables the element-target mode; use `by` or `to`
  instead.

- ...:

  Checked empty; reserved for future use.

- by:

  Offset in pixels, `c(x, y)` (or a single number for both axes). `NULL`
  disables the offset mode.

- to:

  A direction string: the sides, the four corners, or `"center"`. `NULL`
  disables the direction mode.

- duration:

  Seconds per staged wheel scroll; `NULL` computes the time from the
  scroll distance and `cursor_speed` in
  [`pz_stage()`](https://posit-dev.github.io/paparazzi/reference/pz_stage.md).
  Applies only while recording, including `target` and any scroll needed
  to bring a scoped container into view. Use 0 to scroll instantly
  without wheel animation.

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

[`pz_find()`](https://posit-dev.github.io/paparazzi/reference/pz_find.md),
[`pz_act_click()`](https://posit-dev.github.io/paparazzi/reference/pz_act_click.md)

## Examples

``` r
page <- pz_open(pz_example("tasks"), height = 600)

# With a target, scroll it into view
page |> pz_act_scroll("#toggle-help")
pz_expect_in_viewport(page, target = "#toggle-help")

# With `to` or `by`, scroll the current scope's container: here the list
page |>
  pz_find(".task-list") |>
  pz_act_scroll(to = "bottom")
pz_expect_in_viewport(page, target = pz_loc(".task", which = "last"))

# At the root, the container is the page itself
page |> pz_act_scroll(to = "top")
pz_js(page, "window.scrollY")
#> [1] 0
pz_close(page)
```
