# Dies with httpuv's bind-failure signature on every launch, exercising
# pz_serve()'s log-based port-taken detection and its retry budget. (A
# genuinely occupied port can't force a child bind failure on macOS --
# SO_REUSEADDR lets a second specific-address bind succeed -- which is
# why pz_serve() also refuses ports that already answer a connect.)
stop("Failed to create server")
