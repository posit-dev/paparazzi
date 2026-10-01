# Declare a font from Google Fonts

Declares a font face for
[`pz_stage_fonts()`](https://posit-dev.github.io/paparazzi/reference/pz_stage_fonts.md).
The family is identified by its Google Fonts name, and Chrome fetches
the stylesheet and font files at staging time; nothing is downloaded by
R.

## Usage

``` r
pz_font_google(family, weight = 400, style = "normal")
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
[`pz_font_bunny()`](https://posit-dev.github.io/paparazzi/reference/pz_font_bunny.md),
[`pz_font_file()`](https://posit-dev.github.io/paparazzi/reference/pz_font_file.md)

## Examples

``` r
pz_font_google("Inter", weight = 700)
#> <paparazzi font> Inter (google, weight 700, normal)
```
