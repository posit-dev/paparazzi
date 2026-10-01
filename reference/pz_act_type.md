# Type text into an element

With a `target`, auto-waits for the element to be actionable – visible
with a non-empty box and receiving pointer events at its center (not
covered by another element) – then scrolls it into view, clicks the
center of it (real mouse events, so the element genuinely gains focus),
and inserts `text` at the caret – the caret lands where the click lands,
just like a real user. With `target = NULL` at the root context, inserts
into whatever element currently has focus; if nothing editable is
focused, the text goes nowhere, exactly like typing into a page with no
focused field.

Insertion is instant (one `insertText`), except while recording with
`typing = "natural"` (the default; see
[`pz_stage()`](https://posit-dev.github.io/paparazzi/reference/pz_stage.md)):
one `insertText` per character with randomized delays around
`typing_speed`, so the video shows the text appearing. While recording,
the cursor that clicked the field fades out so it doesn't cover the
text, and fades back in when the next action moves it. For a
value-setting primitive that works on selects, checkboxes, and range
inputs, see
[`pz_set_value()`](https://posit-dev.github.io/paparazzi/reference/pz_set_value.md).

## Usage

``` r
pz_act_type(ctx, text, ..., target = NULL)
```

## Arguments

- ctx:

  A paparazzi context.

- text:

  A string to type.

- ...:

  Checked empty; reserved for future use.

- target:

  A CSS selector string, a
  [`pz_loc()`](https://posit-dev.github.io/paparazzi/reference/pz_loc.md)
  spec, or a list of specs (a union matching any of them). `NULL` uses
  the current scope or, at the root context, the focused element.

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

[`pz_act_press()`](https://posit-dev.github.io/paparazzi/reference/pz_act_press.md)
for key combos (Enter, Control+A, ...) and
[`pz_act_click()`](https://posit-dev.github.io/paparazzi/reference/pz_act_click.md).

## Examples

``` r
page <- pz_open(pz_example("tasks"))
page |> pz_act_type("Buy milk", target = "#task-title")
pz_get_value(page, target = "#task-title")
#> [1] "Buy milk"

# Typing fires input events, so the page reacts: Add is now enabled
pz_expect_enabled(page, target = "#add-task")

# At the root, target = NULL types into the focused element
page |> pz_act_type(" and eggs")
pz_get_value(page, target = "#task-title")
#> [1] "Buy milk and eggs"
pz_close(page)
```
