# Clear page annotations

Remove an annotation by id, or remove every annotation when `id` is
`NULL`. During an active recording, marks play their reveal in reverse
before removal; paused recordings and stills clear instantly.

## Usage

``` r
pz_annotate_clear(ctx, id = NULL, ...)
```

## Arguments

- ctx:

  A paparazzi context.

- id:

  Id to clear; `NULL` clears all. Reserved ids are allowed.

- ...:

  Checked empty; reserved for future use.

## Value

`ctx`, invisibly.
