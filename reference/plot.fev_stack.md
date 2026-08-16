# Plot the layers of a `fev_stack`

Plot the layers of a `fev_stack`

## Usage

``` r
# S3 method for class 'fev_stack'
plot(x, layer = NULL, ...)
```

## Arguments

- x:

  A `fev_stack`.

- layer:

  Optional layer name or index. When `NULL`, all layers are drawn on a
  common panel layout.

- ...:

  Passed to
  [`terra::plot()`](https://rspatial.github.io/terra/reference/plot.html).

## Value

`x`, invisibly.
