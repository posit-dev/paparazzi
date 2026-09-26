# Minor correctness nits (paparazzi#wny8)

Signed off: orchestrator.

## Scope and mechanism decisions

- In `pz_get_elements()`, pass the getter's `call` through to `new_get_tibble()` as `pz_get_rect()` does. Test that an error originating inside the tibble factory is attributed to `pz_get_elements()`; use an internal mock if the failure is not reliably reproducible through the browser.
- In `js_value()`, decode CDP's `unserializableValue` `"-0"` as R `-0`, retaining its sign. Extend the existing `pz_js` unserializable-values test with a reciprocal check.
- Land the two fixes separately, each with a regression test that fails before the code change.

## Handoff

Pending.
