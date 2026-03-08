#!/usr/bin/env bash
set -euo pipefail

APP_NAME="HoldToTalk"
BUNDLE_ID="com.holdtotalk.app"
APP_USER="${APP_USER:-${SUDO_USER:-$USER}}"
ASSUME_YES=0
FAILED_PATHS=()

usage() {
  cat <<'EOF'
Usage: scripts/reset-fresh-test.sh [--yes]

Removes HoldToTalk.app and app-specific local state so you can test from a clean slate:
- /Applications/HoldToTalk.app
- ~/Applications/HoldToTalk.app
- app preferences, caches, logs, saved state
- sandbox container data
- downloaded Whisper models
- TCC permissions for Microphone, Accessibility, and Input Monitoring

If /Applications/HoldToTalk.app exists and is not writable by your current user,
re-run with:

  sudo APP_USER=$USER bash scripts/reset-fresh-test.sh --yes

Environment:
  APP_USER   User whose HoldToTalk state should be removed.

Notes:
  On newer macOS versions, deleting ~/Library/Containers/<bundle id> may require
  Full Disk Access for Terminal/iTerm even if the files are owned by your user.
EOF
}

while (($# > 0)); do
  case "$1" in
    -y|--yes)
      ASSUME_YES=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

resolve_home() {
  local user="$1"
  local home=""
  home="$(dscl . -read "/Users/${user}" NFSHomeDirectory 2>/dev/null | sed -n 's/^NFSHomeDirectory: //p')"
  if [[ -n "${home}" && -d "${home}" ]]; then
    printf '%s\n' "${home}"
    return
  fi

  if [[ "${user}" == "${USER:-}" && -n "${HOME:-}" && -d "${HOME}" ]]; then
    printf '%s\n' "${HOME}"
    return
  fi

  eval "home=~${user}"
  if [[ -n "${home}" && "${home}" != "~${user}" && -d "${home}" ]]; then
    printf '%s\n' "${home}"
    return
  fi

  return 1
}

USER_HOME="$(resolve_home "${APP_USER}")"
SYSTEM_APP="/Applications/${APP_NAME}.app"
USER_APP="${USER_HOME}/Applications/${APP_NAME}.app"

run_as_app_user() {
  if [[ "$(id -un)" == "${APP_USER}" ]]; then
    "$@"
  else
    sudo -u "${APP_USER}" "$@"
  fi
}

print_path() {
  printf '  %s\n' "$1"
}

remove_path() {
  local path="$1"
  local output
  if [[ -e "${path}" || -L "${path}" ]]; then
    if output="$(rm -rf "${path}" 2>&1)"; then
      printf 'removed %s\n' "${path}"
    else
      FAILED_PATHS+=("${path}")
      printf 'warning: could not remove %s\n' "${path}" >&2
      [[ -n "${output}" ]] && printf '%s\n' "${output}" >&2
    fi
  fi
}

remove_matches() {
  local dir="$1"
  local pattern="$2"
  local output
  [[ -d "${dir}" ]] || return 0
  while IFS= read -r path; do
    [[ -n "${path}" ]] || continue
    if output="$(rm -rf "${path}" 2>&1)"; then
      printf 'removed %s\n' "${path}"
    else
      FAILED_PATHS+=("${path}")
      printf 'warning: could not remove %s\n' "${path}" >&2
      [[ -n "${output}" ]] && printf '%s\n' "${output}" >&2
    fi
  done < <(find "${dir}" -maxdepth 1 -name "${pattern}" -print)
}

if [[ ! -d "${USER_HOME}" ]]; then
  echo "error: could not resolve home directory for ${APP_USER}" >&2
  exit 1
fi

if [[ -e "${SYSTEM_APP}" && "${EUID}" -ne 0 && ! -w "${SYSTEM_APP}" ]]; then
  echo "error: ${SYSTEM_APP} exists and is not writable by $(id -un)." >&2
  echo "re-run with: sudo APP_USER=${APP_USER} bash scripts/reset-fresh-test.sh --yes" >&2
  exit 1
fi

APP_PATHS=(
  "${SYSTEM_APP}"
  "${USER_APP}"
  "${USER_HOME}/Library/Application Support/HoldToTalk"
  "${USER_HOME}/Library/Application Support/${BUNDLE_ID}"
  "${USER_HOME}/Library/Caches/${BUNDLE_ID}"
  "${USER_HOME}/Library/HTTPStorages/${BUNDLE_ID}"
  "${USER_HOME}/Library/Logs/HoldToTalk"
  "${USER_HOME}/Library/Logs/${BUNDLE_ID}"
  "${USER_HOME}/Library/Preferences/${BUNDLE_ID}.plist"
  "${USER_HOME}/Library/Saved Application State/${BUNDLE_ID}.savedState"
  "${USER_HOME}/Library/WebKit/${BUNDLE_ID}"
  "${USER_HOME}/Library/Application Scripts/${BUNDLE_ID}"
  "${USER_HOME}/Library/Containers/${BUNDLE_ID}"
)

if [[ "${ASSUME_YES}" -ne 1 ]]; then
  cat <<EOF
This will delete HoldToTalk state for user ${APP_USER} (${USER_HOME}):
EOF
  for path in "${APP_PATHS[@]}"; do
    print_path "${path}"
  done
  print_path "TCC: Microphone, Accessibility, ListenEvent"
  printf 'Continue? [y/N] '
  read -r reply
  if [[ ! "${reply}" =~ ^[Yy]$ ]]; then
    echo "aborted"
    exit 0
  fi
fi

if [[ "$(id -un)" == "${APP_USER}" ]]; then
  pkill -x "${APP_NAME}" >/dev/null 2>&1 || true
  pkill -x "Autoupdate" >/dev/null 2>&1 || true
else
  pkill -u "${APP_USER}" -x "${APP_NAME}" >/dev/null 2>&1 || true
  pkill -u "${APP_USER}" -x "Autoupdate" >/dev/null 2>&1 || true
fi

for path in "${APP_PATHS[@]}"; do
  remove_path "${path}"
done

remove_matches "${USER_HOME}/Library/Preferences/ByHost" "${BUNDLE_ID}*"
remove_matches "${USER_HOME}/Library/Logs/DiagnosticReports" "${APP_NAME}*"

run_as_app_user defaults delete "${BUNDLE_ID}" >/dev/null 2>&1 || true
run_as_app_user tccutil reset Microphone "${BUNDLE_ID}" >/dev/null 2>&1 || true
run_as_app_user tccutil reset Accessibility "${BUNDLE_ID}" >/dev/null 2>&1 || true
run_as_app_user tccutil reset ListenEvent "${BUNDLE_ID}" >/dev/null 2>&1 || true
run_as_app_user killall cfprefsd >/dev/null 2>&1 || true

if [[ "${#FAILED_PATHS[@]}" -gt 0 ]]; then
  cat >&2 <<EOF
warning: some paths could not be removed:
EOF
  for path in "${FAILED_PATHS[@]}"; do
    print_path "${path}" >&2
  done
  cat >&2 <<EOF

The most common cause is macOS protecting sandbox container metadata under
~/Library/Containers. If that remains, grant Full Disk Access to your terminal
app, then rerun this script. Everything else was still cleaned up.
EOF
fi

cat <<EOF
Hold to Talk has been removed for ${APP_USER}.

Fresh-start test sequence:
  1. Install HoldToTalk.app again
  2. Launch it from /Applications
  3. Onboarding, models, and permissions should behave like first run
EOF
