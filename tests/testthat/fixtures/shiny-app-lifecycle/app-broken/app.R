# Deliberately broken app: startup must fail loudly and the error must
# carry this log output.
cat("PAPARAZZI_FIXTURE_BROKEN\n")
stop("boom: fixture app refuses to start")
