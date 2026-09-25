# pz_example() errors on unknown names

    Code
      pz_example("nope")
    Condition
      Error in `pz_example()`:
      ! "nope" is not a paparazzi example.
      i Available examples: "tasks" and "tasks-app".
    Code
      pz_example(c("tasks", "tasks-app"))
    Condition
      Error in `pz_example()`:
      ! `name` must be a single string or `NULL`, not a character vector.

