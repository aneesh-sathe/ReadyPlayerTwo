#!/bin/zsh

set -euo pipefail

rpt_smoke_read_lifecycle_report() {
  local report_path="$1"

  typeset -g RPT_SMOKE_LAUNCHER_PID=""
  typeset -g RPT_SMOKE_BROKER_PID=""
  typeset -g RPT_SMOKE_APP_PID=""

  if [[ ! -f "$report_path" || -L "$report_path" ]]; then
    rpt_die "The lifecycle report is missing or unsafe."
    return
  fi
  if [[ "$(stat -f '%u:%Lp' "$report_path")" != "$(id -u):600" ]]; then
    rpt_die "The lifecycle report has unsafe ownership or permissions."
    return
  fi
  if [[ "$(wc -l <"$report_path" | tr -d ' ')" != "4" ]]; then
    rpt_die "The lifecycle report has an unexpected shape."
    return
  fi

  local schema_version=""
  local key
  local value
  while IFS='=' read -r key value; do
    case "$key" in
      schema_version)
        [[ -z "$schema_version" ]] || {
          rpt_die "The lifecycle report repeats schema_version."
          return
        }
        schema_version="$value"
        ;;
      launcher_pid)
        [[ -z "$RPT_SMOKE_LAUNCHER_PID" ]] || {
          rpt_die "The lifecycle report repeats launcher_pid."
          return
        }
        RPT_SMOKE_LAUNCHER_PID="$value"
        ;;
      broker_pid)
        [[ -z "$RPT_SMOKE_BROKER_PID" ]] || {
          rpt_die "The lifecycle report repeats broker_pid."
          return
        }
        RPT_SMOKE_BROKER_PID="$value"
        ;;
      app_pid)
        [[ -z "$RPT_SMOKE_APP_PID" ]] || {
          rpt_die "The lifecycle report repeats app_pid."
          return
        }
        RPT_SMOKE_APP_PID="$value"
        ;;
      *)
        rpt_die "The lifecycle report contains an unknown field."
        return
        ;;
    esac
  done <"$report_path"

  if [[ "$schema_version" != "1" ]]; then
    rpt_die "The lifecycle report schema is unsupported."
    return
  fi

  local process_id
  for process_id in \
    "$RPT_SMOKE_LAUNCHER_PID" \
    "$RPT_SMOKE_BROKER_PID" \
    "$RPT_SMOKE_APP_PID"; do
    if [[ "$process_id" != <1-> ]]; then
      rpt_die "The lifecycle report contains an invalid process identifier."
      return
    fi
  done
}

rpt_smoke_count_microphone_requests() {
  local bundle_identifier="$1"
  local app_pid="$2"

  if [[ -z "$bundle_identifier" || "$bundle_identifier" == *$'\n'* ]]; then
    rpt_die "A bundle identifier is required for the microphone audit."
    return
  fi
  if [[ "$app_pid" != <1-> ]]; then
    rpt_die "A valid app process identifier is required for the microphone audit."
    return
  fi

  LC_ALL=C /usr/bin/awk \
    -v bundle_identifier="$bundle_identifier" \
    -v app_pid="$app_pid" '
      {
        process_id = ""
        message_id = ""

        if (match($0, /"processID"[[:space:]]*:[[:space:]]*[0-9]+/)) {
          process_id = substr($0, RSTART, RLENGTH)
          sub(/^.*:[[:space:]]*/, "", process_id)
        }
        if (match($0, /msgID=[^ ,"}]+/)) {
          message_id = substr($0, RSTART + 6, RLENGTH - 6)
        }
        if (process_id == "" || message_id == "") {
          next
        }

        correlation_id = process_id ":" message_id
        if (index($0, "service=kTCCServiceMicrophone") > 0) {
          microphone[correlation_id] = 1
        }

        attribution = "identifier=" bundle_identifier ", pid=" app_pid ","
        if (index($0, attribution) > 0) {
          application[correlation_id] = 1
        }
      }

      END {
        count = 0
        for (correlation_id in microphone) {
          if (application[correlation_id]) {
            count += 1
          }
        }
        print count
      }
    '
}

rpt_smoke_verify_dockless_bundle() {
  local app_bundle="$1"
  local info_plist="$app_bundle/Contents/Info.plist"

  if [[ ! -d "$app_bundle" || ! -f "$info_plist" ]]; then
    rpt_die "The packaged app bundle is incomplete."
    return
  fi

  local bundle_identifier
  bundle_identifier="$(
    /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$info_plist" 2>/dev/null
  )" || {
    rpt_die "The packaged app has no bundle identifier."
    return
  }
  if [[ "$bundle_identifier" != "com.aneeshsathe.readyplayertwo" ]]; then
    rpt_die "The packaged app has an unexpected bundle identifier."
    return
  fi

  local is_dockless
  is_dockless="$(
    /usr/libexec/PlistBuddy -c "Print :LSUIElement" "$info_plist" 2>/dev/null
  )" || {
    rpt_die "The packaged app does not declare Dockless operation."
    return
  }
  if [[ "$is_dockless" != "true" ]]; then
    rpt_die "The packaged app is not configured as a Dockless agent."
    return
  fi

  local prohibits_multiple_instances
  prohibits_multiple_instances="$(
    /usr/libexec/PlistBuddy \
      -c "Print :LSMultipleInstancesProhibited" \
      "$info_plist" \
      2>/dev/null
  )" || {
    rpt_die "The packaged app does not prohibit multiple instances."
    return
  }
  if [[ "$prohibits_multiple_instances" != "true" ]]; then
    rpt_die "The packaged app allows multiple instances."
    return
  fi

  local executable_name
  executable_name="$(
    /usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$info_plist" 2>/dev/null
  )" || {
    rpt_die "The packaged app has no executable name."
    return
  }
  if [[ -z "$executable_name" || "${executable_name:t}" != "$executable_name" ]]; then
    rpt_die "The packaged app executable name is unsafe."
    return
  fi
  if [[ ! -x "$app_bundle/Contents/MacOS/$executable_name" ]]; then
    rpt_die "The packaged app executable is missing."
    return
  fi
}

rpt_smoke_parse_loopback_listener() {
  local line
  local loopback_port=""
  integer listener_count=0
  integer unsafe_listener_count=0

  while IFS= read -r line; do
    case "$line" in
      n127.0.0.1:<1->)
        loopback_port="${line##*:}"
        listener_count+=1
        ;;
      n*)
        unsafe_listener_count+=1
        ;;
    esac
  done

  if (( unsafe_listener_count > 0 )); then
    rpt_die "The credential broker has a non-loopback listener."
    return
  fi
  if (( listener_count != 1 )); then
    rpt_die "The credential broker must have exactly one loopback listener."
    return
  fi
  if (( loopback_port < 1 || loopback_port > 65535 )); then
    rpt_die "The credential broker listener port is invalid."
    return
  fi

  printf '%s\n' "$loopback_port"
}
