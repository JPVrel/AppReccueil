#!/bin/sh
set -eu

exec semgrep scan --config auto --no-git-ignore --include '*.R' R app.R launcher.R shiny scripts tests
