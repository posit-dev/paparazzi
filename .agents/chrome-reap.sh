#!/bin/bash
# Usage: .agents/chrome-reap.sh
#
# Kills paparazzi test workers and chromote Chromes orphaned by a killed
# test run, and removes the Chrome profiles they pinned. testthat's parallel
# workers are unsupervised callr sessions: when the main test process dies,
# each worker is reparented to init and gets SIGPIPE writing to its closed
# stdio. On macOS that signal can land on a background thread (later's timer
# thread doesn't block signals), where R's SIGPIPE handler runs the
# interpreter off the main thread; the worker then deadlocks or spins
# forever and keeps its Chrome alive. chrome-lock.sh runs this before each
# locked run.

descendants() {
  local child
  for child in $(pgrep -P "$1"); do
    echo "$child"
    descendants "$child"
  done
}

# Chrome deletes its own headless scoped_dir* profile only on Browser.close,
# not on SIGTERM or SIGKILL.
scoped_profiles() {
  lsof -p "$1" -Fn 2>/dev/null |
    sed -n 's|^n\(.*/Chrome-headless/scoped_dir[^/]*\).*|\1|p' |
    sort -u
}

# SIGKILL the given processes, wait up to 5 seconds for them to exit, then
# remove the scoped profiles any of them held.
reap() {
  local pid profiles
  profiles=$(for pid in "$@"; do scoped_profiles "$pid"; done)
  kill -KILL "$@" 2>/dev/null
  for _ in $(seq 50); do
    for pid in "$@"; do
      kill -0 "$pid" 2>/dev/null && break
      pid=
    done
    [ -z "$pid" ] && break
    sleep 0.1
  done
  [ -n "$profiles" ] && printf '%s\n' "$profiles" |
    while IFS= read -r profile; do rm -rf "$profile"; done
}

workers=$(ps -axo pid=,ppid=,command= |
  awk '$2 == 1 && /\/exec\/R --no-readline --slave --no-save --no-restore/ { print $1 }')
for worker in $workers; do
  cwd=$(lsof -a -p "$worker" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')
  case $cwd in
    */paparazzi*) ;;
    *) continue ;;
  esac
  echo "chrome-reap: orphaned test worker $worker ($cwd)"
  # R's tempdir(), from processx's supervisor FIFO: a SIGKILLed R can't
  # remove it, and the test Chrome profile lives there.
  tmp=$(ps -o command= -p "$(pgrep -P "$worker" supervisor | head -n1)" 2>/dev/null |
    sed -n 's|.* -i \(.*/Rtmp[^/]*\)/supervisor_stdin.*|\1|p')
  # shellcheck disable=SC2046
  reap "$worker" $(descendants "$worker")
  [ -n "$tmp" ] && rm -rf "$tmp"
done

# A chromote Chrome whose R parent is gone; chromote puts its crash dumps in
# that R session's tempdir(), which a SIGKILLed R can't remove.
browsers=$(ps -axo pid=,ppid=,command= |
  awk '$2 == 1 && /--headless/ && /--remote-debugging-port=/ &&
    /--crash-dumps-dir=[^ ]*\/Rtmp[^ ]*\/chrome-/ { print $1 }')
for browser in $browsers; do
  echo "chrome-reap: orphaned chromote Chrome $browser"
  tmp=$(ps -o command= -p "$browser" 2>/dev/null |
    sed -n 's|.*--crash-dumps-dir=\([^ ]*/Rtmp[^/]*\)/chrome-.*|\1|p')
  # shellcheck disable=SC2046
  reap "$browser" $(descendants "$browser")
  [ -n "$tmp" ] && rm -rf "$tmp"
done
