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

rpt_soak_sample_process() {
  local process_id="$1"

  if [[ "$process_id" != <1-> ]]; then
    rpt_die "A positive process identifier is required for a soak sample."
    return
  fi

  local raw_sample
  raw_sample="$(
    LC_ALL=C /bin/ps \
      -p "$process_id" \
      -o pid= \
      -o ppid= \
      -o %cpu= \
      -o rss=
  )" || {
    rpt_die "The monitored process $process_id is not running."
    return
  }

  if [[ -z "$raw_sample" || "$raw_sample" == *$'\n'* ]]; then
    rpt_die "The monitored process $process_id returned an invalid sample."
    return
  fi

  local sampled_pid
  local parent_pid
  local cpu_percent
  local rss_kib
  read -r sampled_pid parent_pid cpu_percent rss_kib <<<"$raw_sample"

  if [[ "$sampled_pid" != "$process_id" ||
    "$parent_pid" != <1-> ||
    ! "$cpu_percent" =~ '^[0-9]+([.][0-9]+)?$' ||
    "$rss_kib" != <1-> ]]; then
    rpt_die "The monitored process $process_id returned unsafe metrics."
    return
  fi

  printf '%s %s %s %s\n' \
    "$sampled_pid" \
    "$parent_pid" \
    "$cpu_percent" \
    "$rss_kib"
}
