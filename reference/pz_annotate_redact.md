# Redact page elements

Covers every element matched by `target` with an instant opaque fill or
backdrop blur in screenshots and recordings. Fill is the safe choice for
secrets: blur can leave text partly legible. Redactions follow elements
as they move and respect axis-aligned overflow clipping, except custom
`overflow-clip-margin`. If a target disconnects, stops rendering, or is
entirely clipped, its redaction hides until it becomes visible again.
They belong to the current document and are lost on navigation.
Redaction covers each element's border box plus `pad`, not overflowing
descendants; target the overflowing element or add padding. Later
top-layer UI (modal dialogs and popovers) paints above redactions, so
targets inside an open modal or popover are rejected.

## Usage

``` r
pz_annotate_redact(
  ctx,
  target = NULL,
  ...,
  method = c("fill", "blur"),
  pad = 0,
  id = NULL,
  color = NULL
)
```

## Arguments

- ctx:

  A paparazzi context.

- target:

  A selector,
  [`pz_loc()`](https://posit-dev.github.io/paparazzi/reference/pz_loc.md)
  spec, or list of targets. `NULL` uses the current scope, or
  `document.body` at the root.

- ...:

  Checked empty; reserved for future use.

- method:

  `"fill"` (default) or `"blur"` (32 CSS px backdrop blur).

- pad:

  Extra CSS pixels around each element; defaults to zero.

- id:

  Optional nonempty id; reusing it replaces the old annotation. `NULL`
  generates a unique id, so calls accumulate annotations. `"spotlight"`
  and `"caption"` are reserved.

- color:

  CSS color for fill; `NULL` uses near-black (`#171717`), not the staged
  mark color. A near-black opaque base stays underneath even when a
  custom color is translucent or invalid. For blur, only `NULL` is
  allowed.

## Value

`ctx`, invisibly.

## See also

[`pz_annotate()`](https://posit-dev.github.io/paparazzi/reference/pz_annotate.md),
[`pz_annotate_clear()`](https://posit-dev.github.io/paparazzi/reference/pz_annotate_clear.md)
