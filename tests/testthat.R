# This file is part of the standard setup for testthat.
# It is recommended that you do not modify it.
#
# Where should you do additional test configuration?
# Learn more about the roles of various files in:
# * https://r-pkgs.org/testing-design.html#sec-tests-files-overview
# * https://testthat.r-lib.org/articles/special-files.html

library(testthat)
library(paparazzi)

# Platform smoke mode (PAPARAZZI_SMOKE_ONLY=true; CI sets it on
# macOS/Windows jobs outside rc-v* branches): run only the
# platform-sensitive subset. The full suite runs everywhere else.
if (identical(Sys.getenv("PAPARAZZI_SMOKE_ONLY"), "true")) {
  test_check("paparazzi", filter = "platform-smoke")
} else {
  test_check("paparazzi")
}
