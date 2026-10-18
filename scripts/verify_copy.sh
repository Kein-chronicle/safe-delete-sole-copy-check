#!/usr/bin/env bash
# Requires Python 3.10+. Never deletes anything. Exit 0 equal, 1 different, 2 unmeasured.
exec python3 "$(dirname "$0")/verify_copy.py" "$@"
