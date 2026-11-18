#!/usr/bin/env bash
# shellcheck disable=SC2034
# -----------------------------------------------------------------------------
# bootstrap/lib/log.sh — verbose per-run log files.
# -----------------------------------------------------------------------------
# log_init NAME ARGS...   create logs/NAME-<timestamp>.log (+ NAME-latest.log
#                         symlink), rotate old runs (LOG_KEEP in settings.conf),
#                         write a diagnostic header and install exit traps.
# log_line TEXT           append one timestamped line (colours stripped).
# log_stream [COPY]       filter stdin into the log (and COPY), redacting secrets.
# log_add_secret VALUE    never write VALUE to the log (replaced by ****).
# log_trace_on            bash xtrace into the log (--trace flag of every script).
#
# Log files are created with mode 600: they can contain hostnames, usernames
# and paths. Known secrets are redacted, but treat the logs as private anyway.
# -----------------------------------------------------------------------------

LOG_FILE=""
LOG_FILE_REL=""
_LOG_SECRETS=()

log_quote_cmd() {
  local out="" a
  for a in "$@"; do
    if [[ "$a" =~ ^[A-Za-z0-9_./:=,@%+-]+$ ]]; then out+="$a "; else out+="$(printf '%q' "$a") "; fi
  done
  _log_redact "${out% }"
}

log_add_secret() {
  local v="$1"
  # Very short values (e.g. "admin") would also hide ordinary words such as
  # "mariadb-admin" all over the log, so they aren't redacted (logs are mode 600).
  [[ ${#v} -ge 6 ]] || { log_line "note: a secret shorter than 6 characters is not redacted in this log"; return 0; }
  local s; for s in "${_LOG_SECRETS[@]}"; do [[ "$s" == "$v" ]] && return 0; done
  _LOG_SECRETS+=("$v")
}

_log_redact() {
  local text="$1" s
  for s in "${_LOG_SECRETS[@]}"; do text="${text//"$s"/****}"; done
  printf '%s' "$text"
}

log_line() {
  [[ -n "$LOG_FILE" ]] || return 0
  local text="$*"
  text="$(_log_redact "$text")"
  text="$(printf '%s' "$text" | sed 's/\x1b\[[0-9;?]*[A-Za-z]//g')"
  printf '%s %s\n' "$(date '+%H:%M:%S')" "$text" >> "$LOG_FILE"
}

# log_stream [COPY_FILE] — copies stdin into the log file (and COPY_FILE),
# stripping ANSI sequences and replacing every registered secret by ****.
# Implemented with awk so large outputs (bench init) stay fast.
log_stream() {
  local copy="${1:-/dev/null}" list=""
  local s; for s in "${_LOG_SECRETS[@]}"; do list+="$s"$'\n'; done
  LOG_REDACT_LIST="$list" awk -v logf="${LOG_FILE:-/dev/null}" -v copy="$copy" '
    BEGIN {
      n = split(ENVIRON["LOG_REDACT_LIST"], sec, "\n")
    }
    {
      line = $0
      gsub(/\033\[[0-9;?]*[A-Za-z]/, "", line)
      gsub(/\r/, "", line)
      for (i = 1; i <= n; i++) {
        if (sec[i] == "") continue
        out = ""
        while ((p = index(line, sec[i])) > 0) {
          out = out substr(line, 1, p - 1) "****"
          line = substr(line, p + length(sec[i]))
        }
        line = out line
      }
      print "         | " line >> logf
      print line >> copy
      fflush(logf); fflush(copy)
    }'
}

_log_rotate() {
  local name="$1" keep="${LOG_KEEP:-5}" f i=0
  [[ "$keep" =~ ^[0-9]+$ ]] || keep=5
  while IFS= read -r f; do
    i=$((i + 1))
    (( i > keep )) && rm -f -- "$f"
  done < <(ls -1t -- "$LOG_DIR/$name"-2*.log 2>/dev/null)
}

log_init() {
  local name="$1"; shift
  mkdir -p "$LOG_DIR"
  chmod 700 "$LOG_DIR" 2>/dev/null || true
  LOG_FILE="$LOG_DIR/${name}-$(date '+%Y%m%d-%H%M%S').log"
  # Two runs in the same second: add a suffix rather than clobbering.
  [[ -e "$LOG_FILE" ]] && LOG_FILE="${LOG_FILE%.log}-$$.log"
  : > "$LOG_FILE"
  chmod 600 "$LOG_FILE"
  LOG_FILE_REL="${LOG_FILE#"$REPO_ROOT"/}"
  ln -sfn "$(basename "$LOG_FILE")" "$LOG_DIR/${name}-latest.log"
  _log_rotate "$name"

  {
    echo "=================================================================="
    echo " $name — $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "=================================================================="
    echo "command      : $0 $(log_quote_cmd "$@")"
    echo "repo         : $REPO_ROOT"
    echo "git commit   : $(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo n/a) ($(git -C "$REPO_ROOT" status --porcelain 2>/dev/null | wc -l | tr -d ' ') changed files)"
    echo "user         : $(id -un 2>/dev/null) (uid $(id -u), groups: $(id -Gn 2>/dev/null))"
    echo "host         : $(hostname 2>/dev/null) — $(uname -srm 2>/dev/null)"
    echo "os           : $( (. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME") || echo unknown)"
    echo "bash         : $BASH_VERSION"
    echo "terminal     : TERM=${TERM:-unset} tty_in=$UI_TTY_IN tty_out=$UI_TTY_OUT fancy=$UI_FANCY lang=${LANG:-unset}"
    echo "docker       : $(docker --version 2>/dev/null || echo 'not installed')"
    echo "compose      : $(docker compose version 2>/dev/null || echo 'n/a (or needs sudo)')"
    echo "python3      : $(python3 --version 2>/dev/null || echo 'not installed')"
    echo "disk (repo)  : $(df -h "$REPO_ROOT" 2>/dev/null | awk 'NR==2 {print $4 " free of " $2}')"
    echo "memory       : $(free -h 2>/dev/null | awk '/^Mem:/ {print $7 " available of " $2}')"
    echo "settings     : $(grep -vE '^[[:space:]]*(#|$)' "$SETTINGS_FILE" 2>/dev/null | tr '\n' ' ')"
    echo "=================================================================="
  } >> "$LOG_FILE"
}

log_trace_on() {
  [[ -n "$LOG_FILE" ]] || return 0
  exec {_LOG_TRACE_FD}>> "$LOG_FILE"
  BASH_XTRACEFD=$_LOG_TRACE_FD
  PS4='+ [trace ${BASH_SOURCE[0]##*/}:${LINENO}] '
  set -x
}
