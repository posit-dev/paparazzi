# Test value: what a failure tells you

A test's value is the diagnostic precision of its failure. Judge every
test by what happens when it goes red:

- **High value:** a failure points to one and only one thing, and that
  thing is obvious. Diagnosis starts immediately.
- **Low value:** a failure implicates many possible problems. Diagnosis
  starts with an investigation, not a fix.
- **Worst:** a failure that first requires proving the test itself was
  working correctly. The triage bill — fetching logs, reading the test,
  checking timing and load conditions, re-running to see if it
  reproduces — is spent before anyone knows whether a real problem
  exists at all.

A flaky test is worse than no test. It is not zero-value, it is
negative-value: it teaches everyone to rerun-and-ignore, and that
reflex devalues every other test in the suite. The suite's credibility
is set by its least interpretable failure.

## The two axes

Failure interpretability decomposes into two independent properties:

1. **Suspect-set size** — how many product components a failure
   implicates. Narrow is better, but a broad integration test is
   acceptable if its failures are rare and always real: "something in
   this area genuinely changed" is actionable when it can be trusted.
2. **Substrate trustworthiness** — whether the test's own operation
   must be verified before the failure means anything. A failure on an
   untrusted substrate always names the test as the first suspect.

Nondeterminism is mostly a machine for manufacturing axis-2 debt. In
browser tests the classic form is two clocks racing — a wall-clock
animation in the page against a load-sensitive capture or polling loop
in R — where the test asserts on their intersection. Under CI
contention the intersection moves, the assertion fails, and nothing
about the product is implicated.

## Design rules for this suite

These specialize the reliability rules in `AGENTS.md`; that file states
the mechanics, this file states the property they buy.

1. **Pixel assertions only over state the test arranged to persist.**
   Assert on resting cursors, settled layouts, monotonic quantities
   (ink that only grows), or retained-frame polls. Never assert on a
   sampled instant of a live animation: the capture pump's cadence is
   not part of the product contract.
2. **Animation assertions over the schedule, not the samples.**
   Keyframes, durations, easing math, and commanded positions are
   deterministic and can be asserted directly. Whether a moving element
   appears in N intermediate frames of a recording cannot be — with
   poll-based capture that property is cosmetic and belongs to manual
   QA or paint-driven (screencast) capture only.
3. **Polls move load off the suspect list.** `pz_poll()` /
   `expect_retry()` convert "did it happen within a fixed window" into
   "did it ever happen", so a slow runner changes the test's duration,
   not its verdict. A test that fails only under load is asserting a
   timing contract nobody signed.
4. **A failing assertion should fail loudly and name what never
   happened.** A poll that gives up must abort with what it waited
   for; never return `NULL` or an empty vector that downstream
   expressions quietly absorb into a pass.
5. **When deleting an uninterpretable assertion, record the trade.**
   Say in the test comment what coverage was given up, where the
   property is pinned instead (usually a schedule-level test), or why
   leaving it unpinned is acceptable.

## Using this in an audit

For each existing test, ask: *if this failed on CI tonight, what is the
first thing I would check?* If the answer is "whether the test raced",
the test is a liability regardless of its pass rate.

Audit checklist per test:

- Does a failure implicate more than one subsystem? Can the assertion
  be split or moved closer to the unit that owns the behavior?
- Does the test depend on wall-clock alignment between two clocks
  (animation vs. capture, action vs. sampler)? Convert to a poll, a
  schedule assertion, or delete it.
- Does every timeout path fail loudly with a named condition?
- Does the test pass vacuously when its subject is absent (empty frame
  lists, zero-length vectors, `all(logical(0))`)?

Triage heuristic for CI failures: a failure that reproduces identically
on rerun is a product bug until proven otherwise; a failure that
passes on an unmodified rerun is a test bug until proven otherwise —
file it, don't just rerun past it.
