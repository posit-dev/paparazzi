# Discriminating probe for chromote command-timeout flakes (the
# "Runtime.callFunctionOn timed out" / "Timed out after Ns resolving"
# family under parallel test suites).
#
# Usage: Rscript .agents/cdp-flake-probe.R [n_rounds]
#
# Two signatures have historically produced 10s CDP command timeouts:
#
#   1. Wedge: a nested pump settles a command's promise before
#      wait_for()/synchronize() registers its then(), so the completion
#      handler queues on a loop no worker pumps and the call spins to
#      its timeout with the response already on the wire. Root-caused
#      and fixed via the fire-and-forget pinned-set finalizer and
#      nav_await's child-loop pinning; this probe forces that exact
#      interleave to confirm the current promises/chromote stack
#      settles it instantly.
#
#   2. Starvation: extreme machine load (multi-worktree parallel
#      suites) delays the response past the timeout. Serializing
#      Chrome-heavy runs with .agents/chrome-lock.sh prevents the
#      observed trigger; moderate synthetic load does not reproduce it.
#
# On a future recurrence, run this probe first: a clean pass (all
# "wedge: instant" lines) rules the wedge out and points at
# starvation; re-run the failing suite with chromote wire logging
# enabled (see probe_wedge() for how) and check whether a RECV for the
# timed-out command id precedes the timeout in the log.

library(paparazzi)
library(later)

n_rounds <- if (length(commandArgs(TRUE))) {
  as.integer(commandArgs(TRUE)[1])
} else {
  25L
}
n_rounds <- max(1L, n_rounds)

page <- pz_open(
  file.path("tests", "testthat", "fixtures", "elements.html"),
  wait = "none"
)
s <- page$session

probe_wedge <- function(i) {
  msg <- list(
    method = "Runtime.evaluate",
    params = list(expression = "1 + 1", returnByValue = TRUE)
  )
  # The callback's return value becomes the chained promise's value;
  # TRUE distinguishes the pre-settled path from a plain pass-through.
  fired <- FALSE
  p <- s$parent$send_command(
    msg,
    sessionId = s$get_session_id(),
    callback = function(res) {
      fired <<- TRUE
      TRUE
    }
  )
  Sys.sleep(0.05)
  # Stray pump: process the response exactly like the old GC-finalizer
  # bug did, before wait_for() registers synchronize()'s then().
  repeat {
    later::run_now(loop = page$child_loop)
    if (fired) {
      break
    }
  }
  t0 <- proc.time()[["elapsed"]]
  val <- tryCatch(s$parent$wait_for(p), error = function(e) conditionMessage(e))
  dt <- proc.time()[["elapsed"]] - t0
  status <- if (isTRUE(val) && dt < 0.5) "instant" else "WEDGED"
  cat(sprintf("wedge %02d: %s (%.4fs)\n", i, status, dt))
  status == "instant"
}

results <- vapply(seq_len(n_rounds), probe_wedge, logical(1))
cat(
  sprintf(
    "result: %d/%d instant -- %s\n",
    sum(results),
    length(results),
    if (all(results)) {
      "wedge signature not reproducible; treat timeouts as load-induced"
    } else {
      "wedge reproduced; the never-pumped-loop race is back"
    }
  )
)
pz_close(page)
