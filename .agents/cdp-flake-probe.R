# Discriminating probe for chromote command-timeout flakes (the
# "Runtime.callFunctionOn timed out" / "Timed out after Ns resolving"
# family under parallel test suites).
#
# Usage (from the package root): Rscript .agents/cdp-flake-probe.R [n_rounds]
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
# enabled -- s$parent$debug_messages(TRUE) on the Chromote object
# prints every SEND/RECV to stderr -- and check whether a RECV for the
# timed-out command id precedes the timeout in the log.

# Prefer the working tree over the installed package so branch-local
# regressions in open/close or loop handling are exercised too.
if (file.exists("DESCRIPTION") && requireNamespace("pkgload", quietly = TRUE)) {
  pkgload::load_all(quiet = TRUE)
} else {
  library(paparazzi)
}
library(later)

n_rounds <- if (length(commandArgs(TRUE))) {
  as.integer(commandArgs(TRUE)[1])
} else {
  25L
}
if (is.na(n_rounds)) {
  stop("n_rounds must be an integer", call. = FALSE)
}
n_rounds <- max(1L, n_rounds)

run_probe <- function() {
  page <- pz_open(
    file.path("tests", "testthat", "fixtures", "elements.html"),
    wait = "none"
  )
  on.exit(pz_close(page), add = TRUE)
  s <- page$session

  probe_wedge <- function(i) {
    msg <- list(
      method = "Runtime.evaluate",
      params = list(expression = "1 + 1", returnByValue = TRUE)
    )
    # The callback's return value becomes the chained promise's value;
    # TRUE distinguishes the pre-settled path from a plain pass-through.
    settled <- FALSE
    p <- s$parent$send_command(
      msg,
      sessionId = s$get_session_id(),
      callback = function(res) {
        settled <<- TRUE
        TRUE
      },
      error = function(err) {
        settled <<- TRUE
        FALSE
      }
    )
    Sys.sleep(0.05)
    # Stray pump: process the response exactly like the old GC-finalizer
    # bug did, before wait_for() registers synchronize()'s then().
    # Bounded so a wedged dispatch ends in a verdict, not a hang.
    deadline <- proc.time()[["elapsed"]] + 5
    repeat {
      later::run_now(loop = page$child_loop)
      if (settled || proc.time()[["elapsed"]] > deadline) {
        break
      }
    }
    if (!settled) {
      # The response never arrived; skip wait_for() (it has no timeout on
      # a raw send_command and would spin forever) and report directly.
      cat(sprintf("wedge %02d: NO-RESPONSE after 5s of pumping\n", i))
      return(FALSE)
    }
    t0 <- proc.time()[["elapsed"]]
    val <- tryCatch(s$parent$wait_for(p), error = function(e) {
      conditionMessage(e)
    })
    dt <- proc.time()[["elapsed"]] - t0
    status <- if (isTRUE(val) && dt < 0.5) {
      "instant"
    } else if (is.character(val)) {
      paste("ERROR:", val)
    } else {
      "WEDGED"
    }
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
        "unstable result; inspect the non-instant rounds above before concluding"
      }
    )
  )
}

tryCatch(run_probe(), error = function(e) {
  cat("probe failed:", conditionMessage(e), "\n")
  quit(status = 1)
})
