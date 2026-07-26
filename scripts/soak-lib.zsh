#!/bin/zsh

set -euo pipefail

rpt_soak_duration_seconds() {
  printf '%s\n' "${RPT_SOAK_DURATION_SECONDS:-7200}"
}
