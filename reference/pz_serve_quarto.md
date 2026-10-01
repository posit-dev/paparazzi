# Serve a document or project with Quarto

Starts a local `quarto preview` process for a `.qmd` or `.Rmd` file, or
a directory containing `_quarto.yml`. Quarto renders `.Rmd` files with
knitr. The Quarto CLI must be on `PATH`, or its executable path must be
set in `QUARTO_PATH`; the quarto R package is not required.

## Usage

``` r
pz_serve_quarto(path, ..., render = FALSE)
```

## Arguments

- path:

  A path to a `.qmd` or `.Rmd` file, or a Quarto project directory.

- ...:

  Reserved; must be empty.

- render:

  Whether to request a full render before previewing. `FALSE` passes
  `--no-render`; projects use Quarto's preview preparation and cached
  execution results. Quarto still renders standalone documents on
  startup. `TRUE` passes `--render all`.

## Value

A `PaparazziServe` handle with `$url`, `$port`, `$stop()`,
`$is_running()`, and `$logs()`. Each handle owns its process, so
multiple previews can run at once. Standard output and errors go to a
temporary log file, readable during and after the preview. Pass the
handle to
[`pz_open()`](https://posit-dev.github.io/paparazzi/reference/pz_open.md)
to share it across pages; closing those pages leaves it running.
`$stop()` is idempotent; use `withr::defer(server$stop())` for cleanup.
A finalizer stops the preview as a last resort.

## Details

Input watching and automatic navigation are disabled. Quarto may still
reload pages after resource changes, such as CSS edits; keep those
resources unchanged during a capture. Interactive documents
(`runtime: shiny` or `server: shiny`) are not supported.
