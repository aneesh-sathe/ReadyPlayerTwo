#!/bin/zsh

set -euo pipefail

typeset -gr RPT_SCRIPT_DIR="${0:A:h}"
typeset -gr RPT_ROOT="${RPT_SCRIPT_DIR:h}"
typeset -gr RPT_TOOL_BUILD_ROOT="$RPT_ROOT/.build/tooling"
typeset -gr RPT_DERIVED_DATA="$RPT_TOOL_BUILD_ROOT/DerivedData"
typeset -gr RPT_SOURCE_PACKAGES="$RPT_TOOL_BUILD_ROOT/SourcePackages"
typeset -gr RPT_MODULE_CACHE="$RPT_TOOL_BUILD_ROOT/ModuleCache"
typeset -gr RPT_RUNTIME_ROOT="$RPT_TOOL_BUILD_ROOT/runtime"

rpt_note() {
  printf '%s\n' "$*"
}

rpt_warn() {
  printf 'warning: %s\n' "$*" >&2
}

rpt_die() {
  printf 'error: %s\n' "$*" >&2
  return 1
}

rpt_require_command() {
  local command_name="$1"
  local install_hint="${2:-}"

  if command -v "$command_name" >/dev/null 2>&1; then
    return 0
  fi

  if [[ -n "$install_hint" ]]; then
    rpt_die "$command_name is required. $install_hint"
  else
    rpt_die "$command_name is required."
  fi
}

rpt_prepare_build_directories() {
  mkdir -p \
    "$RPT_DERIVED_DATA" \
    "$RPT_SOURCE_PACKAGES" \
    "$RPT_MODULE_CACHE" \
    "$RPT_RUNTIME_ROOT"
}

rpt_node24_prefix() {
  local candidate="${RPT_NODE24_PREFIX:-}"

  if [[ -z "$candidate" ]]; then
    rpt_require_command brew "Run brew bundle from the repository root."
    candidate="$(brew --prefix node@24 2>/dev/null)" ||
      rpt_die "Homebrew node@24 is missing. Run brew bundle from the repository root."
  fi

  local node_binary="$candidate/bin/node"
  if [[ ! -x "$node_binary" ]]; then
    rpt_die "Node 24 was not found at $node_binary."
  fi

  local node_version
  node_version="$("$node_binary" --version)"
  if [[ "$node_version" != v24.* ]]; then
    rpt_die "Expected Node 24 at $node_binary, found $node_version."
  fi

  printf '%s\n' "$candidate"
}

rpt_node24_binary() {
  local node_prefix
  node_prefix="$(rpt_node24_prefix)"
  printf '%s\n' "$node_prefix/bin/node"
}

rpt_node24_without_openai_key() {
  local node_prefix
  node_prefix="$(rpt_node24_prefix)"
  env -u OPENAI_API_KEY "PATH=$node_prefix/bin:${PATH}" "$@"
}

rpt_without_openai_key() {
  env -u OPENAI_API_KEY "$@"
}

rpt_swift_format() {
  if command -v swift-format >/dev/null 2>&1; then
    swift-format "$@"
    return
  fi

  if xcrun --find swift-format >/dev/null 2>&1; then
    xcrun swift-format "$@"
    return
  fi

  rpt_die "swift-format is required. Run brew bundle from the repository root."
}

rpt_xcode_project() {
  local configured_project="${RPT_XCODE_PROJECT:-}"
  if [[ -n "$configured_project" ]]; then
    if [[ "$configured_project" != /* ]]; then
      configured_project="$RPT_ROOT/$configured_project"
    fi
    [[ -d "$configured_project" ]] ||
      rpt_die "RPT_XCODE_PROJECT does not identify an Xcode project."
    printf '%s\n' "$configured_project"
    return
  fi

  local -a projects
  projects=("$RPT_ROOT"/*.xcodeproj(N))

  if (( ${#projects} == 0 )); then
    rpt_die "No Xcode project exists. Add project.yml and run xcodegen."
  fi
  if (( ${#projects} > 1 )); then
    rpt_die "Multiple Xcode projects exist. Set RPT_XCODE_PROJECT explicitly."
  fi

  printf '%s\n' "$projects[1]"
}

rpt_generate_project_if_configured() {
  if [[ ! -f "$RPT_ROOT/project.yml" ]]; then
    return
  fi

  rpt_require_command xcodegen "Run brew bundle from the repository root."
  rpt_note "Generating the Xcode project..."
  (
    cd "$RPT_ROOT"
    rpt_without_openai_key xcodegen generate --spec project.yml
  )
}

rpt_reject_pattern() {
  local description="$1"
  local pattern="$2"
  shift 2

  local -a existing_paths
  existing_paths=()
  local candidate
  for candidate in "$@"; do
    if [[ -e "$candidate" ]]; then
      existing_paths+=("$candidate")
    fi
  done

  if (( ${#existing_paths} == 0 )); then
    return
  fi

  if rg -q -e "$pattern" "${existing_paths[@]}"; then
    rpt_die "$description"
  fi
}
