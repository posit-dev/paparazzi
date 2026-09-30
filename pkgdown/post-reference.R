# References and article subprocesses use the same seed, so Chromote can
# choose the reference browser's occupied port again when an article starts.
if (chromote::has_default_chromote_object()) {
  chromote::default_chromote_object()$close()
}
