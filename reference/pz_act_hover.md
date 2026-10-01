# Hover the pointer over an element

Auto-waits for the element to be actionable – visible with a non-empty
box and receiving pointer events at its center (not covered by another
element) – then scrolls it into view and moves the pointer to the center
of it with a real `mousemove` event, without pressing any button. This
is what drives `:hover` styles and `mouseenter`/`mouseover` handlers.

## Usage

``` r
pz_act_hover(ctx, target = NULL, ...)
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

[`pz_act_click()`](https://posit-dev.github.io/paparazzi/reference/pz_act_click.md)

## Examples

``` r
page <- pz_open(pz_example("tasks"))
passport <- pz_loc(".task", has_text = "passport")

# Tasks change colour on :hover
pz_get_style(page, "background-color", target = passport)
#> # A tibble: 1 × 2
#>   `background-color` element 
#>   <chr>              <list>  
#> 1 rgb(255, 255, 255) <pz_ctx>
page |> pz_act_hover(passport)
pz_get_style(page, "background-color", target = passport)
#> # A tibble: 1 × 2
#>   `background-color` element 
#>   <chr>              <list>  
#> 1 rgb(255, 255, 255) <pz_ctx>
pz_close(page)
```
