# Declare a font from Bunny Fonts

Declares a font face for
[`pz_stage_fonts()`](https://posit-dev.github.io/paparazzi/reference/pz_stage_fonts.md),
served by Bunny Fonts (<https://fonts.bunny.net>), a GDPR-friendly
foundry that mirrors the Google Fonts collection and stylesheet format.

## Usage

``` r
pz_font_bunny(family, weight = 400, style = "normal")
```

## Arguments

- family:

  The font family name, exactly as Google Fonts spells it, e.g.
  `"Open Sans"`.

- weight:

  Font weight, a number from 1 to 1000 (400 is regular, 700 is bold).

- style:

  `"normal"` (the default) or `"italic"`.

## Value

A font object for
[`pz_stage_fonts()`](https://posit-dev.github.io/paparazzi/reference/pz_stage_fonts.md).

## See also

[`pz_stage_fonts()`](https://posit-dev.github.io/paparazzi/reference/pz_stage_fonts.md),
[`pz_font_google()`](https://posit-dev.github.io/paparazzi/reference/pz_font_google.md),
[`pz_font_file()`](https://posit-dev.github.io/paparazzi/reference/pz_font_file.md)

## Examples

``` r
pz_font_bunny("Inter", style = "italic")
#> <paparazzi font> Inter (bunny, weight 400, italic)
```
