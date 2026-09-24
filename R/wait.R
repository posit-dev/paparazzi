#' Wait while pumping the page's event loop
#'
#' Pauses for `seconds`, driving chromote's child event loop so timers
#' scheduled on it (e.g. recording capture) keep firing during the wait.
#' Never sleeps without pumping the loop.
#'
#' @param ctx A paparazzi context.
#' @param seconds Number of seconds to wait.
#' @return `ctx`, invisibly.
#' @export
pz_wait <- function(ctx, seconds) {
  check_context(ctx)
  check_number_decimal(seconds, min = 0)
  pump_loop(ctx$page$child_loop, seconds)
  invisible(ctx)
}

pump_loop <- function(loop, seconds, interval = 0.1) {
  deadline <- Sys.time() + seconds
  repeat {
    remaining <- as.numeric(difftime(deadline, Sys.time(), units = "secs"))
    if (remaining <= 0) {
      break
    }
    later::run_now(timeoutSecs = min(remaining, interval), loop = loop)
  }
  invisible(TRUE)
}

#' Poll `fn()` until it returns `TRUE` or `timeout` seconds elapse
#'
#' Between checks, pumps `loop` (the page's child loop) instead of sleeping,
#' so timers scheduled on the loop keep firing during the poll.
#'
#' @param fn Zero-arg function returning `TRUE` when the condition holds.
#' @param timeout Seconds before giving up.
#' @param interval Seconds between checks.
#' @param loop A `later` event loop.
#' @param what Description of the condition, used in the timeout error.
#' @param call Reported as the source of the timeout error.
#' @noRd
pz_poll <- function(
  fn,
  timeout,
  interval = 0.1,
  loop,
  what = "condition",
  call = caller_env()
) {
  deadline <- Sys.time() + timeout
  repeat {
    if (isTRUE(fn())) {
      return(invisible(TRUE))
    }
    remaining <- as.numeric(difftime(deadline, Sys.time(), units = "secs"))
    if (remaining <= 0) {
      cli::cli_abort(
        # Plain interpolation: descriptions may carry their own quotes
        # (has_text: "..."), and {.val} would escape them.
        "Timed out after {timeout}s waiting for {what}.",
        class = "paparazzi_error_timeout",
        call = call
      )
    }
    later::run_now(timeoutSecs = min(remaining, interval), loop = loop)
  }
}
