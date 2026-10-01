# Select text inside an element

Auto-waits for a match, then highlights the exact `text` inside it as if
dragging across it: the substring is found among the element's text
nodes (so a match spanning inline tags, e.g. across an `<em>` and a
`<strong>`, is selected as one piece) and becomes the page's real window
selection. Typing afterwards replaces it – call
[`pz_act_type()`](https://posit-dev.github.io/paparazzi/reference/pz_act_type.md)
with `target = NULL`, which inserts into whatever has focus.

## Usage

``` r
pz_act_select_text(ctx, text, ..., target = NULL)
```

## Arguments

- ctx:

  A paparazzi context.

- text:

  A string to select. Must appear exactly in the element, across tags if
  needed; not found is an error.

- ...:

  Checked empty; reserved for future use.

- target:

  A CSS selector string, a
  [`pz_loc()`](https://posit-dev.github.io/paparazzi/reference/pz_loc.md)
  spec, or a list of specs (a union matching any of them). `NULL` uses
  the current scope; at the root context a target is required.

## Value

`ctx`, invisibly.

## Details

A contenteditable target is focused too (dragging across editable text
focuses it, and that focus is where the typing lands); a static target
is not.

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

[`pz_act_type()`](https://posit-dev.github.io/paparazzi/reference/pz_act_type.md),
[`pz_set_value()`](https://posit-dev.github.io/paparazzi/reference/pz_set_value.md)

## Examples

``` r
page <- pz_open(pz_example("tasks"))

# Typing replaces the selection
page |>
  pz_find(pz_loc(".task", has_text = "Renew passport")) |>
  pz_act_click(".task-edit") |>
  pz_find(".task-title") |>
  pz_act_select_text("passport") |>
  pz_act_type("driving licence") |>
  pz_act_press("Enter") |>
  pz_get_text()
#> [1] "Renew driving licence"
pz_close(page)
```
