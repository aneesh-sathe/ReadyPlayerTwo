#!/bin/zsh

set -euo pipefail

rpt_soak_duration_seconds() {
  local candidate="${RPT_SOAK_DURATION_SECONDS:-7200}"

  if [[ "$candidate" != <1-86400> ]]; then
    rpt_die "RPT_SOAK_DURATION_SECONDS must be a whole number from 1 through 86400."
    return
  fi

  printf '%s\n' "$candidate"
}
