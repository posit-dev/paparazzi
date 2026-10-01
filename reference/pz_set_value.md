# Set the value of a form control

Auto-waits for a match, then sets the value instantly – never staged as
typing, even while recording – and dispatches `input` and `change`, so
the page reacts exactly as if a user had made the edit.
Framework-controlled inputs (React and friends) notice the change: the
value is assigned through the browser's native value setter, not the
instance-level property those frameworks intercept.

## Usage

``` r
pz_set_value(ctx, value, ..., target = NULL)
```

## Arguments

- ctx:

  A paparazzi context.

- value:

  A string (most controls), a number (range, number), or `TRUE`/`FALSE`
  (checkboxes, radios).

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

Covers text inputs and textareas (clear with `pz_set_value(ctx, "")`),
native `<select>` elements (matched by option `value`), checkboxes and
radios (`TRUE`/`FALSE`; a radio set to `TRUE` unchecks the others in its
group), and range, date, and number inputs. A contenteditable element
(plain or framework-driven, e.g. ProseMirror) has its content replaced
in one step.

## See also

[`pz_act_type()`](https://posit-dev.github.io/paparazzi/reference/pz_act_type.md)
for visible, keystroke-by-keystroke input and
[`pz_set_files()`](https://posit-dev.github.io/paparazzi/reference/pz_set_files.md).

## Examples

``` r
page <- pz_open(pz_example("tasks"))
page |>
  pz_set_value("Buy milk", target = "#task-title") |>
  pz_set_value("high", target = "#task-priority") |>
  pz_set_value(TRUE, target = "#task-urgent")
pz_get_value(page, target = list("#task-title", "#task-priority"))
#> [1] "Buy milk" "high"    
pz_expect_checked(page, target = "#task-urgent")

# An empty string clears a text input
page |> pz_set_value("", target = "#task-title")
pz_expect_enabled(page, target = "#add-task", not = TRUE)
pz_close(page)
```
