# Run from the package root under chrome-lock.sh.
chrome_count <- function(label) {
  processes <- system2(
    "pgrep",
    c("-fl", shQuote("Google Chrome|chrome-headless")),
    stdout = TRUE
  )
  cat(label, ":", length(processes), "Chrome processes\n")
}

chrome_count("Before reference")
pkgdown::build_reference(topics = "pz_act_click")
chrome_count("After reference")
stopifnot(!chromote::has_default_chromote_object())

page <- paparazzi::pz_open(paparazzi::pz_example("tasks"))
paparazzi::pz_close(page)
cat("Same-session page opened successfully\n")

# pkgdown renders articles in fresh processes with the same reference seed.
callr::r_safe(function(path) {
  set.seed(1014)
  pkgload::load_all(path, quiet = TRUE)
  page <- paparazzi::pz_open(paparazzi::pz_example("tasks"))
  paparazzi::pz_close(page)
  invisible(NULL)
}, args = list(path = getwd()))
chrome_count("After article-like child")
cat("Reference browser cleanup and seeded article startup passed\n")
