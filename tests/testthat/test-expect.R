# Inside testthat, the bridge routes failures through testthat::expect() so
# they register as test failures. These tests override the env var(s)
# testthat::is_testing() consults to exercise the outside-tests path,
# where the same calls abort with the classed error instead. The set is
# immediate and the restore is deferred on the caller, because
# withr::local_envvar()'s envir argument was renamed in withr 3 and a
# helper-wrapped call would otherwise restore when the helper returns.
local_outside_testthat <- function(env = parent.frame()) {
  old <- Sys.getenv(c("TESTTHAT", "TESTTHAT_IS_TESTING"))
  Sys.setenv(TESTTHAT = "", TESTTHAT_IS_TESTING = "")
  withr::defer(do.call(Sys.setenv, as.list(old)), envir = env)
}

test_that("pz_expect_text orders match before target like value and attr", {
  expect_identical(
    names(formals(pz_expect_text)),
    c("ctx", "text", "...", "match", "target", "not", "timeout")
  )
})

test_that("pz_expect_exists passes and returns ctx invisibly", {
  page <- local_elements_page()
  res <- withVisible(pz_expect_exists(page, target = ".btn"))
  expect_false(res$visible)
  expect_identical(res$value, page)
})

test_that("pz_expect_exists trivially passes at the root", {
  page <- local_elements_page()
  pz_expect_exists(page)
})

test_that("pz_expect_exists failure has the classed error format", {
  page <- local_elements_page()
  local_outside_testthat()
  err <- expect_error(
    pz_expect_exists(page, target = ".never", timeout = 0),
    class = "paparazzi_expectation_failure"
  )
  msg <- conditionMessage(err)
  expect_match(msg, "Expected an element to match", fixed = TRUE)
  expect_match(msg, "Target: `.never`", fixed = TRUE)
  expect_match(msg, "Last seen: 0 matches", fixed = TRUE)
  expect_match(msg, "Waited", fixed = TRUE)
})

test_that("pz_expect_count passes exact counts and inclusive bounds", {
  page <- local_elements_page()
  pz_expect_count(page, n = 1, target = ".story")
  pz_expect_count(page, n = 3, target = ".message")
  pz_expect_count(page, min = 1, target = ".btn")
  pz_expect_count(page, max = 10, target = ".btn")
  pz_expect_count(page, min = 5, max = 7, target = ".btn") # 6 matches
  # min = max is the same as n
  pz_expect_count(page, min = 2, max = 2, target = ".chat")
  # not = TRUE passes when the count is anything else
  pz_expect_count(page, n = 2, target = ".message", not = TRUE)
})

test_that("pz_expect_count(n = 0) passes on a missing target without waiting", {
  page <- local_elements_page()
  start <- Sys.time()
  pz_expect_count(page, n = 0, target = ".never", timeout = 0)
  expect_lt(as.numeric(difftime(Sys.time(), start, units = "secs")), 1)
})

test_that("pz_expect_count validates its inputs", {
  page <- local_elements_page()
  expect_error(pz_expect_count(page), "range")
  expect_error(pz_expect_count(page, n = 1, min = 1), "combine")
  expect_error(pz_expect_count(page, n = 1, max = 1), "combine")
  expect_error(pz_expect_count(page, min = 3, max = 2), class = "paparazzi_error_input")
  expect_error(pz_expect_count(page, n = 1.5), "whole")
  expect_error(pz_expect_count(page, n = -1), "whole")
  expect_error(pz_expect_count(page, n = 1, extra = 1), "empty")
})

test_that("pz_expect_count failure shows the observed count", {
  page <- local_elements_page()
  local_outside_testthat()
  err <- expect_error(
    pz_expect_count(page, n = 3, target = ".btn", timeout = 0),
    class = "paparazzi_expectation_failure"
  )
  msg <- conditionMessage(err)
  expect_match(msg, "Expected count to be exactly 3", fixed = TRUE)
  expect_match(msg, "Last seen: 6 matches", fixed = TRUE)
})

test_that("pz_expect_visible requires every match to be visible", {
  page <- local_elements_page()
  pz_expect_visible(page, target = ".message")
  pz_expect_visible(page, target = ".story")

  local_outside_testthat()
  err <- expect_error(
    pz_expect_visible(page, target = ".ghost", timeout = 0),
    class = "paparazzi_expectation_failure"
  )
  expect_match(conditionMessage(err), "0 of 1 visible", fixed = TRUE)
  expect_match(
    conditionMessage(err),
    "Expected all elements to be visible",
    fixed = TRUE
  )

  # A set mixing visible and hidden elements fails with the mix visible.
  err <- expect_error(
    pz_expect_visible(page, target = list(".story", ".ghost"), timeout = 0),
    class = "paparazzi_expectation_failure"
  )
  msg <- conditionMessage(err)
  expect_match(msg, "1 of 2 visible", fixed = TRUE)
  expect_match(msg, "Target: `.story` | `.ghost`", fixed = TRUE)
})

test_that("pz_expect_hidden is pz_expect_visible(not = TRUE)", {
  page <- local_elements_page()
  # .ghost is display: none; .veiled is visibility: hidden.
  pz_expect_hidden(page, target = ".ghost")
  pz_expect_hidden(page, target = ".veiled")
  pz_expect_visible(page, target = ".ghost", not = TRUE)
  # Zero matches counts as hidden, for both spellings.
  pz_expect_hidden(page, target = ".never")
  pz_expect_visible(page, target = ".never", not = TRUE)

  local_outside_testthat()
  err <- expect_error(
    pz_expect_hidden(page, target = ".story", timeout = 0),
    class = "paparazzi_expectation_failure"
  )
  expect_match(
    conditionMessage(err),
    "Expected no element to be visible",
    fixed = TRUE
  )
})

test_that("pz_expect_text contains, exact, and regex, whitespace-collapsed", {
  page <- local_elements_page()
  pz_expect_text(page, "otters", target = ".story")
  pz_expect_text(page, "Once there were otters.", target = ".story", match = "exact")
  pz_expect_text(page, "ott+ers", target = ".story", match = "regex")
  # The fixture text runs "  Once   there were   otters.  "; both sides
  # collapse before comparing.
  pz_expect_text(page, "Once   there were otters.", target = ".story", match = "exact")
  # A single value applies to every match.
  pz_expect_text(page, "same words", target = ".twin", match = "exact")
})

test_that("pz_expect_text compares vectors pairwise in order", {
  page <- local_elements_page()
  texts <- c("What's the weather?", "The weather is sunny.", "Bring a hat.")
  pz_expect_text(page, texts, target = ".message", match = "exact")
  pz_expect_text(page, c("same words", "same words"), target = ".twin", match = "exact")

  local_outside_testthat()
  # Wrong order: pairwise comparison fails.
  expect_error(
    pz_expect_text(page, rev(texts), target = ".message", match = "exact", timeout = 0),
    class = "paparazzi_expectation_failure"
  )
  # Length n requires exactly n matches: two values against three
  # elements never passes.
  expect_error(
    pz_expect_text(page, texts[1:2], target = ".message", match = "exact", timeout = 0),
    class = "paparazzi_expectation_failure"
  )
})

test_that("pz_expect_text with not = TRUE", {
  page <- local_elements_page()
  pz_expect_text(page, "penguins", target = ".story", not = TRUE)
  # No match satisfies, including zero matches.
  pz_expect_text(page, "anything", target = ".never", not = TRUE, timeout = 0)
  # Partial satisfaction fails the negation too: 3 of 6 .btn contain
  # "Save", and the SPEC's negation needs NO match to satisfy.
  testthat::expect_failure(
    pz_expect_text(page, "Save", target = ".btn", not = TRUE, timeout = 0)
  )
  # Same for vectors: the first .twin satisfies its pairwise text, so
  # the negation fails even though the second pair doesn't match.
  testthat::expect_failure(
    pz_expect_text(
      page,
      c("same words", "WRONG"),
      target = ".twin",
      not = TRUE,
      timeout = 0
    )
  )
  # When the count differs from the vector length there is no pairwise
  # correspondence, so the negation passes vacuously.
  pz_expect_text(
    page,
    c("What's the weather?", "Bring a hat."),
    target = ".panel",
    not = TRUE,
    timeout = 0
  )
})

test_that("page text is never interpreted as cli markup", {
  page <- local_elements_page()
  local_outside_testthat()
  err <- expect_error(
    pz_expect_text(page, "nope", target = ".brace", timeout = 0),
    class = "paparazzi_expectation_failure"
  )
  # If the observed text were glued as a template this would read "2".
  expect_match(conditionMessage(err), "{1 + 1}", fixed = TRUE)
})

test_that("pz_expect_text failure shows the last seen text", {
  page <- local_elements_page()
  local_outside_testthat()
  err <- expect_error(
    pz_expect_text(page, "penguins", target = ".story", timeout = 0),
    class = "paparazzi_expectation_failure"
  )
  msg <- conditionMessage(err)
  expect_match(msg, 'Expected text to contain "penguins"', fixed = TRUE)
  expect_match(msg, "Target: `.story`", fixed = TRUE)
  expect_match(msg, 'Last seen: "Once there were otters."', fixed = TRUE)
  expect_match(msg, "Waited", fixed = TRUE)
})

test_that("target = NULL at the root resolves to document.body", {
  page <- local_elements_page()
  pz_expect_text(page, "otters")

  local_outside_testthat()
  err <- expect_error(
    pz_expect_text(page, "penguins", timeout = 0),
    class = "paparazzi_expectation_failure"
  )
  expect_match(conditionMessage(err), "Target: document.body", fixed = TRUE)
})

test_that("expectations retry until they pass", {
  page <- local_elements_page()
  # The element gains the expected text only after 300 ms.
  pz_js(
    page,
    "setTimeout(() => { document.querySelector('.late-text').textContent = 'ready now'; }, 300)",
    await = FALSE
  )
  pz_expect_text(page, "ready now", target = ".late-text", timeout = 5)
})

test_that("timeout = 0 checks once and fails fast", {
  page <- local_elements_page()
  pz_js(
    page,
    "setTimeout(() => { document.querySelector('.late-text').textContent = 'ready now'; }, 300)",
    await = FALSE
  )
  local_outside_testthat()
  start <- Sys.time()
  expect_error(
    pz_expect_text(page, "ready now", target = ".late-text", timeout = 0),
    class = "paparazzi_expectation_failure"
  )
  expect_lt(as.numeric(difftime(Sys.time(), start, units = "secs")), 1)
})

test_that("the testthat bridge counts passes and reports failures", {
  page <- local_elements_page()
  expect_success(pz_expect_exists(page, target = ".btn"))
  expect_failure(pz_expect_exists(page, target = ".never", timeout = 0))
})

test_that("outside of testthat, failures abort with the classed error", {
  page <- local_elements_page()
  local_outside_testthat()
  expect_error(
    pz_expect_visible(page, target = ".ghost", timeout = 0),
    class = "paparazzi_expectation_failure"
  )
})

test_that("expectations validate their inputs", {
  page <- local_elements_page()
  expect_error(pz_expect_exists(page, extra = 1), "empty")
  expect_error(pz_expect_exists(1, target = ".btn"), class = "paparazzi_error_context")
  expect_error(pz_expect_exists(page, target = ".btn", not = "yes"), "yes")
  expect_error(pz_expect_hidden(page, target = ".btn", not = 1), "not")
  expect_error(pz_expect_exists(page, target = ".btn", timeout = -1), "timeout")
  expect_error(pz_expect_text(page, 1), "character")
  expect_error(
    pz_expect_text(page, "x", target = ".btn", match = "near"),
    "contains"
  )
  expect_error(pz_expect_visible(page, target = list()), class = "paparazzi_error_target")
})

test_that("expect_retry returns the last failure without aborting", {
  page <- local_elements_page()
  n <- 0
  result <- expect_retry(
    function() {
      n <<- n + 1
      list(pass = FALSE, observed = n)
    },
    timeout = 0.25,
    loop = page$child_loop
  )
  expect_false(result$pass)
  expect_identical(result$observed, n)
  expect_gte(n, 2)
})

test_that("expect_retry with timeout = 0 checks once", {
  page <- local_elements_page()
  n <- 0
  result <- expect_retry(
    function() {
      n <<- n + 1
      list(pass = TRUE)
    },
    timeout = 0,
    loop = page$child_loop
  )
  expect_true(result$pass)
  expect_identical(n, 1)
})

test_that("expect_retry pumps the page's event loop between checks", {
  page <- local_elements_page()
  fired <- FALSE
  later::later(function() fired <<- TRUE, delay = 0.1, loop = page$child_loop)
  result <- expect_retry(
    function() list(pass = fired),
    timeout = 2,
    loop = page$child_loop
  )
  expect_true(result$pass)
})

# Scoped-context expectations run against scopes.html: two parallel
# #scope-a/#scope-b sections, so in-scope counts are unambiguous.

test_that("expectations resolve inside the current scope", {
  page <- local_scopes_page()
  ctx <- pz_find(page, "#scope-b")

  # An explicit target resolves lazily inside the scope: .sc-label
  # matches once inside #scope-b, twice at the root.
  expect_invisible(
    ctx |> pz_expect_count(1, target = ".sc-label", timeout = 0)
  )
  expect_invisible(
    ctx |> pz_expect_text("shared", target = ".sc-target", timeout = 0)
  )
  # NULL means the scope itself: the pinned #scope-b section.
  expect_invisible(ctx |> pz_expect_count(1, timeout = 0))
  expect_invisible(ctx |> pz_expect_text("B1", timeout = 0))
  # A narrowed scope's own element.
  item <- pz_find_nth(ctx, 1, target = ".sc-item")
  expect_invisible(item |> pz_expect_text("B1", timeout = 0))
})

test_that("each attempt re-queries lazily inside the pinned scope", {
  page <- local_scopes_page()
  ctx <- pz_find(page, "#scope-a")
  pz_js(
    page,
    "setTimeout(function() {
      const el = document.createElement('span');
      el.className = 'sc-label';
      el.textContent = 'late';
      document.getElementById('scope-a').appendChild(el);
    }, 300)"
  )
  # Inside the scope the count reaches 2 once the span lands; at the
  # root it would be 3 (scope-b's sc-label included) and never pass.
  expect_invisible(ctx |> pz_expect_count(2, target = ".sc-label", timeout = 3))
})

test_that("a detached scope aborts expectations before the retry loop", {
  page <- local_scopes_page()
  ctx <- pz_find(page, "#scope-a .sc-item")

  pz_js(page, "document.querySelectorAll('#scope-a .sc-item')[0].remove()")
  expect_error(
    ctx |> pz_expect_count(3, target = ".sc-item", timeout = 0.3),
    class = "paparazzi_error_detached"
  )
  expect_error(
    ctx |> pz_expect_count(3, timeout = 0.3),
    class = "paparazzi_error_detached"
  )
})

test_that("a scope detaching mid-expectation raises the classed error", {
  page <- local_scopes_page()
  ctx <- pz_find(page, "#scope-a .sc-item")

  # The expectation fails and keeps retrying; the scope detaches
  # mid-retry, and the next attempt's probe aborts instead of letting
  # the checks degrade into failures on a stale set.
  pz_js(
    page,
    "setTimeout(function() {
      document.querySelectorAll('#scope-a .sc-item').forEach((el) => el.remove());
    }, 300)"
  )
  expect_error(
    ctx |> pz_expect_count(1, target = ".never", timeout = 3),
    class = "paparazzi_error_detached"
  )
})

test_that("a mid-expectation detach raises for target = NULL too", {
  page <- local_scopes_page()
  ctx <- pz_find(page, "#scope-b .sc-item")

  pz_js(
    page,
    "setTimeout(function() {
      document.getElementById('scope-b').remove();
    }, 300)"
  )
  expect_error(
    ctx |> pz_expect_text("never appears", timeout = 3),
    class = "paparazzi_error_detached"
  )
})

# State expectations run against state.html: enabled/disabled controls
# (including a disabled fieldset), focus, checkboxes and radios, and
# elements positioned in and out of the viewport.

test_that("pz_expect_enabled requires every match to be enabled", {
  page <- local_state_page()
  pz_expect_enabled(page, target = ".on")
  pz_expect_enabled(page, target = "#btn-disabled", not = TRUE)
  # Inputs inside a disabled fieldset count as disabled.
  pz_expect_enabled(page, target = "#inherited", not = TRUE)

  local_outside_testthat()
  err <- expect_error(
    pz_expect_enabled(page, target = ".ctl", timeout = 0),
    class = "paparazzi_expectation_failure"
  )
  msg <- conditionMessage(err)
  expect_match(msg, "Expected all elements to be enabled", fixed = TRUE)
  expect_match(msg, "2 of 5 enabled", fixed = TRUE)
  # Zero matches only satisfies the negated form.
  err <- expect_error(
    pz_expect_enabled(page, target = ".never", timeout = 0),
    class = "paparazzi_expectation_failure"
  )
  expect_match(conditionMessage(err), "Last seen: 0 matches", fixed = TRUE)
})

test_that("pz_expect_enabled retries until a control is enabled", {
  page <- local_state_page()
  pz_js(page, "setTimeout(function () {
    document.getElementById('btn-disabled').disabled = false;
  }, 300)", await = FALSE)
  pz_expect_enabled(page, target = "#btn-disabled", timeout = 5)
})

test_that("pz_expect_focused checks document.activeElement", {
  page <- local_state_page()
  pz_focus(page, target = "#focus-target")
  pz_expect_focused(page, target = "#focus-target")
  pz_expect_focused(page, target = "#btn-enabled", not = TRUE)

  local_outside_testthat()
  err <- expect_error(
    pz_expect_focused(page, target = "#btn-enabled", timeout = 0),
    class = "paparazzi_expectation_failure"
  )
  expect_match(conditionMessage(err), "0 of 1 focused", fixed = TRUE)
})

test_that("pz_expect_checked covers checkboxes and radios", {
  page <- local_state_page()
  pz_expect_checked(page, target = ".checked-on")
  pz_expect_checked(page, target = "#cb-off", not = TRUE)

  local_outside_testthat()
  err <- expect_error(
    pz_expect_checked(page, target = ".check", timeout = 0),
    class = "paparazzi_expectation_failure"
  )
  expect_match(conditionMessage(err), "2 of 4 checked", fixed = TRUE)

  # Clicking toggles the checkbox, and the expectation follows.
  pz_click(page, target = "#cb-off")
  pz_expect_checked(page, target = "#cb-off")
})

test_that("pz_expect_in_viewport checks viewport overlap", {
  page <- local_state_page()
  pz_expect_in_viewport(page, target = "#in-viewport")
  pz_expect_in_viewport(page, target = "#off-viewport", not = TRUE)

  local_outside_testthat()
  err <- expect_error(
    pz_expect_in_viewport(page, target = ".vp", timeout = 0),
    class = "paparazzi_expectation_failure"
  )
  expect_match(conditionMessage(err), "1 of 2 in viewport", fixed = TRUE)
  expect_match(
    conditionMessage(err),
    "Expected all elements to be in the viewport",
    fixed = TRUE
  )
})

test_that("pz_expect_in_viewport retries when an element moves into view", {
  page <- local_state_page()
  # The fixture scrolls #late-in-viewport inside after 300 ms.
  pz_expect_in_viewport(page, target = "#late-in-viewport", timeout = 5)
})

test_that("state expectations work from a scoped context", {
  page <- local_state_page()
  ctx <- pz_find(page, "#btn-one")
  # target = NULL is the pinned set: #btn-one.
  ctx |> pz_expect_enabled()
  ctx |> pz_expect_checked(not = TRUE)

  # Explicit targets resolve inside the scope.
  grp <- pz_find(page, "#grp")
  grp |> pz_expect_enabled(target = "#inherited", not = TRUE, timeout = 0)
})

# Content expectations run against state.html's value/attr/class block:
# inputs, a textarea, a select, a checkbox, an element with no value
# property, links with and without href, and a .cls class mix.

test_that("pz_expect_value compares the value property", {
  page <- local_state_page()
  pz_expect_value(page, "hello", target = "#val-text")
  pz_expect_value(page, "hello world", target = "#val-text", match = "exact")
  pz_expect_value(page, "^h", target = "#val-text", match = "regex")
  # A select's value is its selected option.
  pz_expect_value(page, "b", target = "#val-select", match = "exact")
  # A checkbox's value is its value attribute, checked or not.
  pz_expect_value(page, "cb-custom", target = "#val-check", match = "exact")
})

test_that("pz_expect_value collapses whitespace on both sides", {
  page <- local_state_page()
  # The textarea holds "line one\nline two"; both sides collapse.
  pz_expect_value(page, "line one line two", target = "#val-area", match = "exact")
  pz_expect_value(page, "line   one", target = "#val-area")
})

test_that("pz_expect_value compares vectors pairwise in order", {
  page <- local_state_page()
  values <- c("alpha", "beta", "gamma")
  pz_expect_value(page, values, target = ".val-line", match = "exact")

  local_outside_testthat()
  expect_error(
    pz_expect_value(page, rev(values), target = ".val-line", match = "exact", timeout = 0),
    class = "paparazzi_expectation_failure"
  )
  # Length n requires exactly n matches.
  expect_error(
    pz_expect_value(page, values[1:2], target = ".val-line", match = "exact", timeout = 0),
    class = "paparazzi_expectation_failure"
  )
})

test_that("pz_expect_value treats a missing value property as unsatisfied", {
  page <- local_state_page()
  # #val-none is a <p>: no value property, reads as NA.
  pz_expect_value(page, "anything", target = "#val-none", not = TRUE, timeout = 0)
  # NA never satisfies the positive form.
  testthat::expect_failure(
    pz_expect_value(page, "anything", target = "#val-none", timeout = 0)
  )

  local_outside_testthat()
  err <- expect_error(
    pz_expect_value(page, "anything", target = "#val-none", timeout = 0),
    class = "paparazzi_expectation_failure"
  )
  expect_match(conditionMessage(err), 'Expected value to contain "anything"', fixed = TRUE)
  expect_match(conditionMessage(err), 'Last seen: "NA"', fixed = TRUE)
})

test_that("pz_expect_value follows a typed value", {
  page <- local_state_page()
  pz_js(page, "document.getElementById('val-text').value = 'typed otters'")
  pz_expect_value(page, "typed otters", target = "#val-text", match = "exact")
  # And it retries: the input only carries the text after a timer.
  pz_js(page, "setTimeout(function () {
    document.getElementById('val-line-1').value = 'later';
  }, 300)", await = FALSE)
  pz_expect_value(page, "later", target = "#val-line-1", match = "exact", timeout = 5)
})

test_that("pz_expect_attr defaults to an exact comparison", {
  page <- local_state_page()
  pz_expect_attr(page, "href", "https://example.com/page", target = "#link-one")
  # Non-default modes are still available.
  pz_expect_attr(page, "href", "example.com", target = "#link-one", match = "contains")
  pz_expect_attr(page, "href", "^https://", target = "#link-one", match = "regex")
  # A missing attribute satisfies nothing, so not covers absence.
  pz_expect_attr(page, "href", "whatever", target = "#no-href", not = TRUE, timeout = 0)
  pz_expect_attr(page, "target", "_blank", target = "#link-two", not = TRUE, timeout = 0)
})

test_that("pz_expect_attr compares vectors pairwise in order", {
  page <- local_state_page()
  hrefs <- c("one.html", "two.html", "three.html")
  pz_expect_attr(page, "href", hrefs, target = ".attr-line")

  local_outside_testthat()
  err <- expect_error(
    pz_expect_attr(page, "href", rev(hrefs), target = ".attr-line", timeout = 0),
    class = "paparazzi_expectation_failure"
  )
  expect_match(
    conditionMessage(err),
    'Expected attributes "href" to be "three.html", "two.html", "one.html"',
    fixed = TRUE
  )
  expect_match(
    conditionMessage(err),
    'Last seen: "one.html", "two.html", "three.html"',
    fixed = TRUE
  )
})

test_that("pz_expect_attr retries until the attribute lands", {
  page <- local_state_page()
  pz_js(page, "setTimeout(function () {
    document.getElementById('btn-one').setAttribute('data-state', 'ready');
  }, 300)", await = FALSE)
  pz_expect_attr(page, "data-state", "ready", target = "#btn-one", timeout = 5)
})

test_that("pz_expect_class checks class membership", {
  page <- local_state_page()
  pz_expect_class(page, "btn", target = "#btn-one")
  pz_expect_class(page, "btn-primary", target = "#btn-one")
  # no match carries "missing", including the bare span.
  pz_expect_class(page, "missing", target = ".cls", not = TRUE, timeout = 0)
  # Zero matches satisfies only the negated form.
  pz_expect_class(page, "missing", target = ".never", not = TRUE, timeout = 0)

  local_outside_testthat()
  err <- expect_error(
    pz_expect_class(page, "btn", target = ".cls", timeout = 0),
    class = "paparazzi_expectation_failure"
  )
  msg <- conditionMessage(err)
  expect_match(msg, 'Expected all elements to have class "btn"', fixed = TRUE)
  expect_match(msg, "2 of 3 with class \"btn\"", fixed = TRUE)
})

test_that("pz_expect_class validates its input", {
  page <- local_state_page()
  expect_error(pz_expect_class(page, "btn btn", target = ".cls"), "single class name")
  expect_error(pz_expect_class(page, 1, target = ".cls"), "string")
})

# pz_expect_js and the page-level expectations (url, title). The state
# fixture carries #scroll-box (scrollTop starts at 0) and #late-flag,
# whose dataset is set after 300 ms.

test_that("pz_expect_js maps the predicate over every match", {
  page <- local_state_page()
  pz_expect_js(page, "el => el.scrollTop === 0", target = "#scroll-box")
  pz_expect_js(page, "el => el.tagName === 'BODY'") # target = NULL: the body
  pz_expect_js(page, "el => el.disabled", target = "#btn-disabled")
  pz_expect_js(page, "el => el.disabled", target = "#btn-enabled", not = TRUE)

  pz_js(page, "document.getElementById('scroll-box').scrollTop = 50")
  pz_expect_js(page, "el => el.scrollTop > 0", target = "#scroll-box")
  pz_expect_js(page, "el => el.scrollTop === 0", target = "#scroll-box", not = TRUE)
})

test_that("pz_expect_js failure shows the predicate and the count", {
  page <- local_state_page()
  local_outside_testthat()
  err <- expect_error(
    pz_expect_js(page, "el => el.scrollTop > 0", target = "#scroll-box", timeout = 0),
    class = "paparazzi_expectation_failure"
  )
  msg <- conditionMessage(err)
  expect_match(
    msg,
    "Expected JS predicate (el => el.scrollTop > 0) to hold for every match",
    fixed = TRUE
  )
  expect_match(msg, "0 of 1 satisfied", fixed = TRUE)
  # Zero matches satisfies only the negated form.
  err <- expect_error(
    pz_expect_js(page, "el => true", target = ".never", timeout = 0),
    class = "paparazzi_expectation_failure"
  )
  expect_match(conditionMessage(err), "Last seen: 0 matches", fixed = TRUE)
})

test_that("pz_expect_js retries until the predicate holds", {
  page <- local_state_page()
  # The fixture sets #late-flag's dataset after 300 ms.
  pz_expect_js(page, "el => el.dataset.ready === 'yes'", target = "#late-flag", timeout = 5)
})

test_that("pz_expect_js surfaces a throwing predicate as a JS error", {
  page <- local_state_page()
  local_outside_testthat()
  # A bare expression (not a function receiving el) throws at definition.
  expect_error(
    pz_expect_js(page, "el.scrollTop > 0", target = "#scroll-box", timeout = 0),
    class = "paparazzi_error_js"
  )
})

test_that("pz_expect_js works from a scoped context", {
  page <- local_state_page()
  pz_js(page, "document.getElementById('scroll-box').scrollTop = 50")
  ctx <- pz_find(page, "#scroll-box")
  # target = NULL is the pinned set: the predicate sees #scroll-box.
  ctx |> pz_expect_js("el => el.scrollTop > 0")
})

test_that("pz_expect_title matches contains, exact, and regex", {
  page <- local_state_page()
  pz_expect_title(page, "state fixture")
  pz_expect_title(page, "paparazzi state fixture", match = "exact")
  pz_expect_title(page, "state|unit", match = "regex")
  pz_expect_title(page, "renamed", not = TRUE)
})

test_that("pz_expect_title failure uses the classed format", {
  page <- local_state_page()
  local_outside_testthat()
  err <- expect_error(
    pz_expect_title(page, "nope", timeout = 0),
    class = "paparazzi_expectation_failure"
  )
  msg <- conditionMessage(err)
  expect_match(msg, 'Expected title to contain "nope"', fixed = TRUE)
  expect_match(msg, "Target: the page", fixed = TRUE)
  expect_match(msg, 'Last seen: "paparazzi state fixture"', fixed = TRUE)
  expect_match(msg, "Waited", fixed = TRUE)
})

test_that("pz_expect_title retries until the title changes", {
  page <- local_state_page()
  pz_js(page, "setTimeout(function () { document.title = 'renamed title'; }, 300)", await = FALSE)
  pz_expect_title(page, "renamed title", timeout = 5)
})

test_that("pz_expect_url matches contains, exact, and regex", {
  page <- local_state_page()
  pz_expect_url(page, "state.html")
  pz_expect_url(page, pz_get_url(page), match = "exact")
  pz_expect_url(page, "^file://", match = "regex")
  # file:// URLs contain no http://.
  pz_expect_url(page, "http://", not = TRUE)
})

test_that("pz_expect_url failure uses the classed format", {
  page <- local_state_page()
  local_outside_testthat()
  err <- expect_error(
    pz_expect_url(page, "https://example.com", timeout = 0),
    class = "paparazzi_expectation_failure"
  )
  msg <- conditionMessage(err)
  expect_match(msg, 'Expected URL to contain "https://example.com"', fixed = TRUE)
  expect_match(msg, "Target: the page", fixed = TRUE)
  expect_match(msg, "Last seen: ", fixed = TRUE)
})

test_that("pz_expect_url retries until the hash lands", {
  page <- local_state_page()
  pz_js(page, "setTimeout(function () { location.hash = 'later'; }, 300)", await = FALSE)
  pz_expect_url(page, "#later", timeout = 5)
})

test_that("page-level expectations work from a scoped context", {
  page <- local_state_page()
  ctx <- pz_find(page, "#btn-one")
  ctx |> pz_expect_title("state fixture")
  ctx |> pz_expect_url("state.html")
})
