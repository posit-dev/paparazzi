# Stage fonts for annotations and captions

Loads one or more fonts into the page so that everything Chrome draws
for it — annotation badges, callout bubbles, captions, and key callouts
— can use them. Declare fonts with
[`pz_font_google()`](https://posit-dev.github.io/paparazzi/reference/pz_font_google.md),
[`pz_font_bunny()`](https://posit-dev.github.io/paparazzi/reference/pz_font_bunny.md),
or
[`pz_font_file()`](https://posit-dev.github.io/paparazzi/reference/pz_font_file.md)
and pass them in `...`.

## Usage

``` r
pz_stage_fonts(
  ctx,
  ...,
  on_error = getOption("paparazzi.stage_fonts.on_error", "stop")
)
```

## Arguments

- ctx:

  A paparazzi context.

- ...:

  Font objects from
  [`pz_font_google()`](https://posit-dev.github.io/paparazzi/reference/pz_font_google.md),
  [`pz_font_bunny()`](https://posit-dev.github.io/paparazzi/reference/pz_font_bunny.md),
  or
  [`pz_font_file()`](https://posit-dev.github.io/paparazzi/reference/pz_font_file.md).

- on_error:

  What to do when a font fails to load: `"stop"` (the default) aborts
  without staging any of the call's fonts, `"warn"` warns and stages the
  fonts that loaded, and `"ignore"` stages the fonts that loaded,
  silently. Set with `options(paparazzi.stage_fonts.on_error = )` to
  change the default.

## Value

`ctx`, invisibly.

## Details

Staging is an ahead-of-time step: `pz_stage_fonts()` blocks until every
face has loaded (or fails per `on_error`), so annotating is never slowed
by a font load and never flashes a fallback font. Staged fonts persist
across recordings; after navigation they are re-added to the new
document lazily, the first time something is annotated there.

Repeated calls add fonts. A face whose family, weight, and style are
already staged is replaced by the new one. There is no clear or reset.

Remote stylesheets and font files are fetched by Chrome, not R, and stay
in Chrome's HTTP cache. On pages whose Content Security Policy blocks
the fetch (`connect-src` for the stylesheet, `font-src` for the font
files) the load fails and is routed through `on_error`.
[`pz_font_file()`](https://posit-dev.github.io/paparazzi/reference/pz_font_file.md)
sidesteps CSP entirely because its bytes are handed to the page
directly.

## See also

[`pz_stage_annotate()`](https://posit-dev.github.io/paparazzi/reference/pz_stage_annotate.md),
whose `font_family` sets the default family for annotations and key
callouts

## Examples

``` r
page <- pz_open(pz_example("tasks"))
page |>
  pz_stage_fonts(pz_font_google("Silkscreen")) |>
  # font_family takes a CSS family string; use the staged family with
  # a generic fallback
  pz_stage_annotate(font_family = '"Silkscreen", sans-serif') |>
  pz_annotate("#add-task", label = "New") |>
  pz_screenshot(file.path(tempdir(), "tasks.png"))
pz_close(page)
```
