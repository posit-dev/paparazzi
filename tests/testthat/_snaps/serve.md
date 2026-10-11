# an invalid max_attempts option fails with the option named

    Code
      pz_serve_shiny(shiny_app_fixture_dir())
    Condition
      Error in `pz_serve_shiny()`:
      ! `options(paparazzi.serve.max_attempts)` must be a whole number larger than or equal to 1, not the number 0.

