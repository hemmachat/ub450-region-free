#!/bin/sh
# Probe test suite. Exit 0 = all passed.
set -e
cd "$(dirname "$0")"
exec python3 test_probe.py
