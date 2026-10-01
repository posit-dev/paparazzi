# Focus an element

Scrolls the element into view (instantly) and focuses it via the
browser's element focus method, so the page shows focus rings and
enabled-input styles exactly as a user would see them. Focus is an
element-state change, not an input event, so the direct method call is
the faithful implementation (Playwright does the same).

## Usage

``` r
pz_act_focus(ctx, target = NULL, ...)
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

[`pz_act_blur()`](https://posit-dev.github.io/paparazzi/reference/pz_act_blur.md),
[`pz_act_type()`](https://posit-dev.github.io/paparazzi/reference/pz_act_type.md)

## Examples

``` r
if (FALSE) { # paparazzi:::examples_run()
page <- pz_open(pz_example("tasks"))
page |> pz_act_focus("#task-title")
pz_expect_focused(page, target = "#task-title")
pz_close(page)
}
```
