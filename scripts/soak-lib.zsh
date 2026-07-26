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

rpt_soak_expected_presence() {
  local candidate="${RPT_SOAK_EXPECTED_PRESENCE:-roam}"

  if [[ "$candidate" != "roam" && "$candidate" != "park" ]]; then
    rpt_die "RPT_SOAK_EXPECTED_PRESENCE must be roam or park."
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

rpt_soak_verify_lineage() {
  local launcher_pid="$1"
  local broker_pid="$2"
  local app_pid="$3"

  if [[ "$launcher_pid" != <1-> ||
    "$broker_pid" != <1-> ||
    "$app_pid" != <1-> ||
    "$launcher_pid" == "$broker_pid" ||
    "$launcher_pid" == "$app_pid" ||
    "$broker_pid" == "$app_pid" ]]; then
    rpt_die "The soak requires three distinct positive process identifiers."
    return
  fi

  local launcher_sample
  local broker_sample
  local app_sample
  launcher_sample="$(rpt_soak_sample_process "$launcher_pid")" || return
  broker_sample="$(rpt_soak_sample_process "$broker_pid")" || return
  app_sample="$(rpt_soak_sample_process "$app_pid")" || return

  local -a broker_fields
  local -a app_fields
  broker_fields=("${(@s: :)broker_sample}")
  app_fields=("${(@s: :)app_sample}")

  if [[ "$broker_fields[2]" != "$launcher_pid" ]]; then
    rpt_die "The monitored broker is no longer owned by the launcher."
    return
  fi
  if [[ "$app_fields[2]" != "$launcher_pid" ]]; then
    rpt_die "The monitored app is no longer owned by the launcher."
    return
  fi
}

rpt_soak_direct_children() {
  local parent_pid="$1"

  if [[ "$parent_pid" != <1-> ]]; then
    rpt_die "A positive parent process identifier is required."
    return
  fi

  local children
  if children="$(/usr/bin/pgrep -P "$parent_pid" . 2>/dev/null)"; then
    local child_pid
    for child_pid in "${(@f)children}"; do
      if [[ "$child_pid" != <1-> ]]; then
        rpt_die "The process table returned an invalid child identifier."
        return
      fi
      printf '%s\n' "$child_pid"
    done
    return
  else
    local pgrep_status="$?"
    if (( pgrep_status != 1 )); then
      rpt_die "The process table could not be inspected safely."
      return
    fi
  fi
}

rpt_soak_unexpected_children() {
  local launcher_pid="$1"
  local broker_pid="$2"
  local app_pid="$3"
  local -a unexpected_children
  unexpected_children=()

  local parent_pid
  local children
  local child_pid
  for parent_pid in "$launcher_pid" "$broker_pid" "$app_pid"; do
    children="$(rpt_soak_direct_children "$parent_pid")" || return
    if [[ -z "$children" ]]; then
      continue
    fi
    for child_pid in "${(@f)children}"; do
      if [[ "$parent_pid" == "$launcher_pid" &&
        ("$child_pid" == "$broker_pid" || "$child_pid" == "$app_pid") ]]; then
        continue
      fi
      unexpected_children+=("$child_pid")
    done
  done

  if (( ${#unexpected_children} > 0 )); then
    printf '%s\n' "${unexpected_children[@]}" |
      LC_ALL=C /usr/bin/sort -n -u
  fi
}

rpt_soak_persistent_unexpected_children() {
  local previous_children="$1"
  local current_children="$2"

  if [[ -z "$previous_children" || -z "$current_children" ]]; then
    return
  fi

  local -A previous_identifiers
  previous_identifiers=()
  local child_pid
  for child_pid in "${(@f)previous_children}"; do
    if [[ "$child_pid" != <1-> ]]; then
      rpt_die "A previous unexpected child identifier is invalid."
      return
    fi
    previous_identifiers[$child_pid]=1
  done

  for child_pid in "${(@f)current_children}"; do
    if [[ "$child_pid" != <1-> ]]; then
      rpt_die "A current unexpected child identifier is invalid."
      return
    fi
    if [[ -n "${previous_identifiers[$child_pid]:-}" ]]; then
      printf '%s\n' "$child_pid"
    fi
  done
}

rpt_soak_rss_growth_is_unbounded() {
  local -a rss_samples
  rss_samples=("$@")

  if (( ${#rss_samples} < 12 )); then
    return 1
  fi

  local rss_kib
  for rss_kib in "${rss_samples[@]}"; do
    if [[ "$rss_kib" != <0-> ]]; then
      rpt_die "An RSS sample is invalid."
      return
    fi
  done

  local first_index=$(( ${#rss_samples} - 11 ))
  local first_rss_kib="$rss_samples[$first_index]"
  local last_rss_kib="$rss_samples[-1]"
  integer increasing_intervals=0
  integer sample_index
  integer previous_rss_kib="$first_rss_kib"
  integer current_rss_kib
  integer rss_delta

  for ((sample_index = first_index + 1;
    sample_index <= ${#rss_samples};
    sample_index += 1)); do
    current_rss_kib="$rss_samples[$sample_index]"
    rss_delta=$(( current_rss_kib - previous_rss_kib ))
    if (( rss_delta > 0 )); then
      increasing_intervals+=1
    elif (( rss_delta < -1024 )); then
      return 1
    fi
    previous_rss_kib="$current_rss_kib"
  done

  (( last_rss_kib - first_rss_kib >= 32768 &&
    increasing_intervals >= 9 ))
}

rpt_soak_cpu_window_exceeds_limit() {
  local cpu_limit_percent="$1"
  shift
  local -a cpu_samples
  cpu_samples=("$@")

  if [[ ! "$cpu_limit_percent" =~ '^[0-9]+([.][0-9]+)?$' ]]; then
    rpt_die "The soak CPU limit is invalid."
    return
  fi
  if (( ${#cpu_samples} < 12 )); then
    return 1
  fi

  local first_index=$(( ${#cpu_samples} - 11 ))
  integer sample_index
  typeset -F 3 cpu_total=0
  local cpu_percent
  for ((sample_index = first_index;
    sample_index <= ${#cpu_samples};
    sample_index += 1)); do
    cpu_percent="$cpu_samples[$sample_index]"
    if [[ ! "$cpu_percent" =~ '^[0-9]+([.][0-9]+)?$' ]]; then
      rpt_die "A CPU sample is invalid."
      return
    fi
    cpu_total=$(( cpu_total + cpu_percent ))
  done

  typeset -F 3 cpu_average=$(( cpu_total / 12 ))
  (( cpu_average >= cpu_limit_percent ))
}

rpt_soak_resident_memory_exceeds_limit() {
  local rss_limit_kib="$1"
  shift
  local -a rss_samples
  rss_samples=("$@")

  if [[ "$rss_limit_kib" != <1-> || ${#rss_samples} == 0 ]]; then
    rpt_die "The soak resident memory policy is invalid."
    return
  fi

  integer rss_total_kib=0
  local rss_kib
  for rss_kib in "${rss_samples[@]}"; do
    if [[ "$rss_kib" != <0-> ]]; then
      rpt_die "An RSS sample is invalid."
      return
    fi
    rss_total_kib+=rss_kib
  done

  (( rss_total_kib >= rss_limit_kib ))
}
