# Scoped context visibility and print distinction

- `pz_find*()` return the new context directly; pop/reset return `ctx` directly on their root no-op paths. Other actions, including navigation, keep invisible returns.
- `inspect_summary_print()` branches on an empty scope stack: root uses the page header and skips Scope; scoped uses the scope header and emits Scope immediately after it, preserving entry counts and warnings. `inspect_header()` takes the label and subtracts its actual display width from `getOption("width")`.
- Add visible-return assertions for all six find functions and both root no-ops in test-scope.R; update root/scoped print and closed-page assertions in test-inspect.R and test-scope.R, including line positions and width.

Signed off: orchestrator (spec in kata q7h9)
