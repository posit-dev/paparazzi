# Declare a font from a local file

Declares a font face for
[`pz_stage_fonts()`](https://posit-dev.github.io/paparazzi/reference/pz_stage_fonts.md)
from a local font file. The bytes are read by R and handed to the page
directly, so the file works on `http` pages (which cannot load `file://`
URLs) and is not subject to Content Security Policy font restrictions.
You are responsible for the license of fonts you use.

## Usage

``` r
pz_font_file(family, path, weight = 400, style = "normal")
```

## Arguments

- family:

  The font family name, exactly as Google Fonts spells it, e.g.
  `"Open Sans"`.

- path:

  Path to a `.woff2`, `.woff`, `.ttf`, or `.otf` file.

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
[`pz_font_bunny()`](https://posit-dev.github.io/paparazzi/reference/pz_font_bunny.md)

## Examples

``` r
if (FALSE) { # \dontrun{
pz_font_file("My Brand Sans", "~/fonts/my-brand-sans.woff2")
} # }
```
