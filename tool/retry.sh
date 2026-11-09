#!/usr/bin/env bash
# GitHub release downloads used by package:sqlite3 sometimes return 504.
# Version 3.5.2 then hashes that error page and fails the build hook.
# Retry the command that triggers the download; a later attempt gets the real binary.
set -u
attempts="${RETRY_ATTEMPTS:-5}"
delay="${RETRY_DELAY:-8}"
for ((i = 1; i <= attempts; i++)); do
  if "$@"; then
    exit 0
  fi
  status=$?
  if ((i == attempts)); then
    exit "$status"
  fi
  echo "command failed (attempt ${i}/${attempts}, exit ${status}); retrying in ${delay}s"
  sleep "$delay"
  delay=$((delay * 2))
done
