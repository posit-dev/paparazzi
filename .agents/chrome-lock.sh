#!/bin/bash
# Usage: .agents/chrome-lock.sh <command...>
#
# Serializes Chrome-heavy test runs across worktrees and parallel agents.
# Concurrent 5-worker suites overload the machine and cause chromote
# command timeouts that look like test failures. The lock is a directory
# in /tmp shared by every worktree; the owner file records who holds it.
LOCK=/tmp/paparazzi-chrome.lock

until mkdir "$LOCK" 2>/dev/null; do
  # A SIGKILLed holder never runs its EXIT trap; reclaim its lock.
  owner=$(cut -d' ' -f1 "$LOCK/owner" 2>/dev/null)
  if [ -n "$owner" ] && ! kill -0 "$owner" 2>/dev/null; then
    rm -rf "$LOCK"
    continue
  fi
  sleep 10
done
echo "$$ $PWD $*" > "$LOCK/owner"
trap 'rm -rf "$LOCK"' EXIT
"$@"
