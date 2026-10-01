# Click an element

Auto-waits for the element to be actionable – visible with a non-empty
box, the same "visible"
[`pz_expect_visible()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_visible.md)
uses, and receiving pointer events at its center (not covered by another
element) – then scrolls it into view and clicks the center of it with
real browser input events: a mouse move to the point, then a left-button
press and release. The page sees a trusted pointer sequence – exactly
what a user's click produces – so `:hover` state, focus, and click
handlers all behave as they would live. While recording, the staging
settings
([`pz_stage()`](https://posit-dev.github.io/paparazzi/reference/pz_stage.md))
animate the scroll, the cursor glide, and the press; otherwise
everything runs straight to the final state.

## Usage

``` r
pz_act_click(ctx, target = NULL, ..., effect = NULL, effect_color = NULL)
```

## Arguments

- ctx:

  A paparazzi context.

- target:

  A CSS selector string, a
  [`pz_loc()`](https://posit-dev.github.io/paparazzi/reference/pz_loc.md)
  spec, or a list of specs (a union matching any of them). `NULL` uses
  the current scope; at the root context a target is required.

- ...:

  Checked empty; reserved for future use.

- effect:

  Click feedback while recording: `NULL` (the default) uses the page's
  [`pz_stage()`](https://posit-dev.github.io/paparazzi/reference/pz_stage.md)
  `click_effect` setting. `"press"` scales the cursor down while
  pressed, `"ring"` draws an expanding ring that fades out at the click
  point instead of scaling, and `"none"` shows nothing. Without a
  recording no effect is drawn.

- effect_color:

  CSS color of the `"ring"` effect. `NULL` (the default) uses the page's
  [`pz_stage()`](https://posit-dev.github.io/paparazzi/reference/pz_stage.md)
  `click_effect_color` setting.

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

[`pz_act_hover()`](https://posit-dev.github.io/paparazzi/reference/pz_act_hover.md),
[`pz_act_type()`](https://posit-dev.github.io/paparazzi/reference/pz_act_type.md),
[`pz_act_press()`](https://posit-dev.github.io/paparazzi/reference/pz_act_press.md)

## Examples

``` r
page <- pz_open(pz_example("tasks"))
page |> pz_act_click("#toggle-help")
pz_get_text(page, target = "#toggle-help")
#> [1] "Hide help"

# In a scoped context, target = NULL clicks the scope element
page |>
  pz_find(pz_loc(".task-done", within = pz_loc(".task", has_text = "bank"))) |>
  pz_act_click()
pz_get_count(page, target = ".task.done")
#> [1] 2
pz_close(page)
```
