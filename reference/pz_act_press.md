# Press key combinations

Presses one or more key combinations against whatever the page currently
has focused, e.g. `"Enter"`, `"Control+A"`, `c("Shift+Tab", "Escape")`.
A vector presses each combination fully (down then up) in order. Specs
are `"Mod+Mod+Key"` strings with the modifiers Control, Shift, Alt,
Meta, and Mod (matched case-insensitively) and a named key (Enter, Tab,
Escape, Backspace, arrows, F1-F12, ...) or a single printable character.
`Mod` resolves to Meta on browsers reporting a Mac platform
(`navigator.userAgentData.platform` or `navigator.platform`), and
Control otherwise. Following Playwright, an uppercase letter or shifted
symbol implies Shift: `"Control+A"` sends Control+Shift+A.

Keys only reach focused elements; call
[`pz_act_click()`](https://posit-dev.github.io/paparazzi/reference/pz_act_click.md)
or
[`pz_act_focus()`](https://posit-dev.github.io/paparazzi/reference/pz_act_focus.md)
first to focus the element you're typing into.

## Usage

``` r
pz_act_press(ctx, key, ..., show_keys = NULL)
```

## Arguments

- ctx:

  A paparazzi context.

- key:

  A character vector of key specs.

- ...:

  Checked empty; reserved for future use.

- show_keys:

  `NULL` uses the page's
  [`pz_stage()`](https://posit-dev.github.io/paparazzi/reference/pz_stage.md)
  setting (initially `"none"`). `"words"` shows named modifier keycaps,
  `"mac"` uses Mac symbols, and `"both"` shows `Mod` as `Ctrl / ⌘`.
  Keystroke callouts appear only in recordings; subsequent calls replace
  earlier ones. A vector is displayed as a single sequence. In a GIF
  recording, keystroke callouts need the av package.

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
few actions, like `pz_act_press()`, take no target and act on the
focused element instead.

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

[`pz_act_type()`](https://posit-dev.github.io/paparazzi/reference/pz_act_type.md)
to insert text.

## Examples

``` r
page <- pz_open(pz_example("tasks"))
page |>
  pz_act_type("Buy milkk", target = "#task-title") |>
  pz_act_press("Backspace")
pz_get_value(page, target = "#task-title")
#> [1] "Buy milk"

# Enter submits the form; the page shows "Saving..." before the task appears
page |> pz_act_press("Enter")
pz_expect_text(page, "Saved", target = "#status")
pz_get_text(page, target = pz_loc(".task-title", which = "first"))
#> [1] "Buy milk"

# A vector presses keys in sequence; + joins keys pressed together
page |> pz_act_press(c("Tab", "Shift+Tab"))
pz_expect_focused(page, target = "#task-title")
pz_close(page)
```
