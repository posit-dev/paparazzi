# Scoped context visibility and print distinction

- `pz_find*()` return the new context directly; pop/reset return `ctx` directly on their root no-op paths. Other actions, including navigation, keep invisible returns.
- `inspect_summary_print()` branches on an empty scope stack: root uses the page header and skips Scope; scoped uses the scope header and emits Scope immediately after it, preserving entry counts and warnings. `inspect_header()` takes the label and subtracts its actual display width from `getOption("width")`.
- Add visible-return assertions for all six find functions and both root no-ops in test-scope.R; update root/scoped print and closed-page assertions in test-inspect.R and test-scope.R, including line positions and width.

Signed off: orchestrator (spec in kata q7h9)

- Landed: visible find returns, root/scoped summaries, closed-page strings, generated help and tests (c483d65, fef9ccc).
- Verified: scoped/inspect/context [ FAIL 0 | WARN 0 | SKIP 0 | PASS 183 ]; plus open [ FAIL 0 | WARN 0 | SKIP 0 | PASS 337 ]. Next: orchestrator gate and docs task.
- Provisional: none; `pz_inspect()` on a closed page still rejects the context before summary printing, as before.
