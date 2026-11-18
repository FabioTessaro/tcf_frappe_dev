#!/usr/bin/env bash
# Shared terminal output helpers. Safe to source; no work happens until log_init.

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  _LOG_RESET=$'\033[0m'
  _LOG_BLUE=$'\033[34m'
  _LOG_GREEN=$'\033[32m'
  _LOG_YELLOW=$'\033[33m'
  _LOG_RED=$'\033[31m'
  _LOG_DIM=$'\033[2m'
else
  _LOG_RESET='' _LOG_BLUE='' _LOG_GREEN='' _LOG_YELLOW='' _LOG_RED='' _LOG_DIM=''
fi

log_info()    { printf '%s[INFO]%s %s\n' "$_LOG_BLUE" "$_LOG_RESET" "$*"; }
log_step()    { printf '\n%s==>%s %s\n' "$_LOG_BLUE" "$_LOG_RESET" "$*"; }
log_success() { printf '%s[ OK ]%s %s\n' "$_LOG_GREEN" "$_LOG_RESET" "$*"; }
log_warn()    { printf '%s[WARN]%s %s\n' "$_LOG_YELLOW" "$_LOG_RESET" "$*" >&2; }
log_error()   { printf '%s[FAIL]%s %s\n' "$_LOG_RED" "$_LOG_RESET" "$*" >&2; }
log_note()    { printf '%s       %s%s\n' "$_LOG_DIM" "$*" "$_LOG_RESET"; }

log_init() {
  local name="${1##*/}"
  printf '\n%s────────────────────────────────────────%s\n' "$_LOG_DIM" "$_LOG_RESET"
  printf '%s  %s%s\n' "$_LOG_BLUE" "$name" "$_LOG_RESET"
  printf '%s────────────────────────────────────────%s\n' "$_LOG_DIM" "$_LOG_RESET"
  trap 'log_finish "$?"' EXIT
  trap 'log_error "Command failed at line ${LINENO}: ${BASH_COMMAND}"' ERR
}

log_finish() {
  local status="$1"
  if (( status == 0 )); then
    log_success "Finished successfully."
  else
    log_error "Stopped with exit code $status. Review the message above and retry."
  fi
}
