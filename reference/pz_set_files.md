# Attach files to a file input

Auto-waits for a match, then sets the input's files to the given local
files through the browser's own file-input channel, so the input's
`FileList` holds the real names, sizes, and contents, and `change` fires
exactly as if the files had been picked in a dialog.

## Usage

``` r
pz_set_files(ctx, files, ..., target = NULL)
```

## Arguments

- ctx:

  A paparazzi context.

- files:

  A character vector of paths to existing local files.

- ...:

  Checked empty; reserved for future use.

- target:

  A CSS selector string, a
  [`pz_loc()`](https://posit-dev.github.io/paparazzi/reference/pz_loc.md)
  spec, or a list of specs (a union matching any of them). `NULL` uses
  the current scope; at the root context a target is required.

## Value

`ctx`, invisibly.

## See also

[`pz_set_value()`](https://posit-dev.github.io/paparazzi/reference/pz_set_value.md)

## Examples

``` r
notes <- file.path(tempdir(), "meeting-notes.txt")
writeLines("Agenda: plants, parcel, passport", notes)

page <- pz_open(pz_example("tasks"))
page |> pz_set_files(notes, target = "#attachment")
pz_get_text(page, target = "#attachment-name")
#> [1] "Attached meeting-notes.txt."
pz_close(page)
```
