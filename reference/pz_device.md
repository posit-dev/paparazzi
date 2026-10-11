# Set the page's size and display settings

Configures device emulation for the page: viewport size, device scale
factor, mobile-ness, zoom, color scheme, reduced motion, locale and time
zone. Only **supplied** arguments change state: `NULL` (the default)
means "leave this setting alone", so `zoom = 1`, not `zoom = NULL`,
disables an active zoom.

## Usage

``` r
pz_device(
  ctx,
  ...,
  width = NULL,
  height = NULL,
  scale = NULL,
  mobile = NULL,
  zoom = NULL,
  zoom_method = NULL,
  color_scheme = NULL,
  reduced_motion = NULL,
  locale = NULL,
  timezone = NULL
)
```

## Arguments

- ctx:

  A paparazzi context.

- ...:

  Checked empty; reserved for future use.

- width, height:

  Viewport size in CSS pixels. Only the supplied one changes; the other
  keeps its current value.

- scale:

  Device scale factor: how many screen pixels each CSS pixel covers.
  `NULL` keeps the current value. Until you set it, the page renders at
  the browser's own scale (1), but once you set `width`, `height`, or
  `mobile`, it switches to 2 for sharp, retina-quality captures. Zooming
  with the default `zoom_method` multiplies the scale by `zoom`.

- mobile:

  Emulate a mobile device (touch input, mobile viewport semantics)?
  `NULL` retains the stored value, or uses `FALSE` when unset.

- zoom:

  Zoom factor; `1` disables zoom.

- zoom_method:

  `"viewport"` or `"css"`; see above. `NULL` retains the stored method,
  or uses `"viewport"` when unset. Used when a `zoom` is (or later
  becomes) active.

- color_scheme:

  `"light"` or `"dark"` for `prefers-color-scheme`.

- reduced_motion:

  Emulate `prefers-reduced-motion`? `TRUE` maps to `reduce`, `FALSE` to
  `no-preference`.

- locale:

  An ICU locale, e.g. `"de-DE"`.

- timezone:

  An IANA time zone, e.g. `"Pacific/Auckland"`.

## Value

`ctx`, invisibly.

## Details

The two zoom methods trade off differently:

- `zoom_method = "viewport"` (the default) shrinks the CSS viewport and
  raises the device scale factor, so `vh` stays correct but media
  queries can start (or stop) matching.

- `zoom_method = "css"` applies a CSS `zoom` to the page instead – on
  every document, so it survives navigation and reload: layout and media
  queries are untouched, but `vh`-sized elements no longer fit the
  viewport (a 50vh element covers the whole viewport at zoom 2).

`reduced_motion = TRUE` gives deterministic stills (animations stop);
it's opt-in because it's usually wrong for videos.

## See also

[`pz_open()`](https://posit-dev.github.io/paparazzi/reference/pz_open.md)
forwards its `...` here.

## Examples

``` r
page <- pz_open(pz_example("tasks"))

# Only the settings you supply change
page |> pz_device(width = 390, height = 844, mobile = TRUE)
pz_js(page, "[window.innerWidth, window.devicePixelRatio]")
#> [[1]]
#> [1] 390
#> 
#> [[2]]
#> [1] 2
#> 

page |> pz_device(color_scheme = "dark")
pz_get_style(page, "background-color", target = "body")
#> # A tibble: 1 × 2
#>   `background-color` element 
#>   <chr>              <list>  
#> 1 rgb(33, 37, 41)    <pz_ctx>
pz_close(page)
```
