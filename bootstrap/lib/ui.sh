#!/usr/bin/env bash
# shellcheck disable=SC2034
# -----------------------------------------------------------------------------
# bootstrap/lib/ui.sh — minimal command-line user interface, pure bash.
# -----------------------------------------------------------------------------
# Sourced by bootstrap/lib/common.sh; performs no work on import.
#
# Output helpers   ui_banner ui_section ui_step ui_info ui_ok ui_warn ui_error
#                  ui_note ui_kv ui_rule ui_box
# Running things   ui_run   (spinner + live last line, output to the log)
#                  ui_exec  (interactive command, attached to the terminal)
# Asking things    ui_select ui_checklist ui_input ui_secret ui_confirm
#                  ui_confirm_typed ui_pause
#
# Every input helper stores its answer in a global (UI_VALUE, UI_INDEX,
# UI_SELECTED) instead of printing it, so no subshell is needed and the menus
# can draw straight to the terminal.
#
# Every message is also written to the current log file through log_line
# (bootstrap/lib/log.sh), with colours stripped and secrets redacted.
# -----------------------------------------------------------------------------

# --- terminal capabilities ----------------------------------------------------
UI_TTY_IN=false;  [[ -t 0 ]] && UI_TTY_IN=true
UI_TTY_OUT=false; [[ -t 1 ]] && UI_TTY_OUT=true
UI_FANCY=false
if [[ "$UI_TTY_IN" == true && "$UI_TTY_OUT" == true && "${TERM:-dumb}" != "dumb" ]]; then
  UI_FANCY=true
fi

if [[ "$UI_TTY_OUT" == true && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != "dumb" ]]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'; C_ITAL=$'\033[3m'
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'; C_MAGENTA=$'\033[35m'; C_CYAN=$'\033[36m'; C_GREY=$'\033[90m'
  C_INV=$'\033[7m'
else
  C_RESET=''; C_BOLD=''; C_DIM=''; C_ITAL=''
  C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_MAGENTA=''; C_CYAN=''; C_GREY=''
  C_INV=''
fi

if [[ "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" =~ [Uu][Tt][Ff]-?8 ]]; then
  G_OK='✔'; G_FAIL='✖'; G_WARN='▲'; G_INFO='●'; G_ARROW='➜'; G_DOT='·'
  G_ON='◉'; G_OFF='○'; G_BOX_ON='■'; G_BOX_OFF='□'; G_PTR='❯'; G_RULE='─'
  G_UP='▲'; G_DOWN='▼'
  UI_SPIN=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
else
  G_OK='OK'; G_FAIL='XX'; G_WARN='!!'; G_INFO='--'; G_ARROW='->'; G_DOT='.'
  G_ON='(*)'; G_OFF='( )'; G_BOX_ON='[x]'; G_BOX_OFF='[ ]'; G_PTR='>'; G_RULE='-'
  G_UP='^'; G_DOWN='v'
  UI_SPIN=('|' '/' '-' '\')
fi

# Warnings and errors collected during the run, printed by ui_summary.
UI_WARNINGS=()
UI_ERRORS=()

# Results of the input helpers.
UI_VALUE=""
UI_INDEX=-1
UI_SELECTED=()

# Set by ui_run: the file holding the last command's (redacted) output.
UI_LAST_OUTPUT=""

_ui_cols() {
  local c="${COLUMNS:-}"
  if [[ -z "$c" ]] && [[ "$UI_TTY_OUT" == true ]]; then
    c=$(tput cols 2>/dev/null || echo 80)
  fi
  [[ "$c" =~ ^[0-9]+$ ]] || c=80
  (( c > 100 )) && c=100
  printf '%s' "$c"
}

_ui_rows() {
  local r=""
  [[ "$UI_TTY_OUT" == true ]] && r=$(tput lines 2>/dev/null || echo 24)
  [[ "$r" =~ ^[0-9]+$ ]] || r=24
  printf '%s' "$r"
}

_ui_repeat() { local s="" i; for ((i = 0; i < $2; i++)); do s+="$1"; done; printf '%s' "$s"; }

_ui_cursor_hide() { [[ "$UI_FANCY" == true ]] && printf '\033[?25l'; return 0; }
_ui_cursor_show() { [[ "$UI_TTY_OUT" == true ]] && printf '\033[?25h'; return 0; }

# --- plain output -----------------------------------------------------------
ui_rule() {
  local cols; cols=$(_ui_cols)
  printf '%s%s%s\n' "$C_GREY" "$(_ui_repeat "$G_RULE" "$cols")" "$C_RESET"
}

# ui_banner TITLE [SUBTITLE] — big header printed once per script.
ui_banner() {
  local title="$1" sub="${2:-}" cols
  cols=$(_ui_cols)
  printf '\n%s%s%s\n' "$C_GREY" "$(_ui_repeat "$G_RULE" "$cols")" "$C_RESET"
  printf '  %s%s%s%s' "$C_BOLD" "$C_CYAN" "$title" "$C_RESET"
  [[ -n "$sub" ]] && printf '  %s%s%s' "$C_DIM" "$sub" "$C_RESET"
  printf '\n%s%s%s\n' "$C_GREY" "$(_ui_repeat "$G_RULE" "$cols")" "$C_RESET"
  log_line "=== $title${sub:+ — $sub}"
}

# ui_section TITLE — groups the steps that follow. Uses UI_STEP_TOTAL when set
# (e.g. "[3/8] Seeding VS Code Server").
UI_STEP_NO=0
UI_STEP_TOTAL=0
ui_section() {
  local title="$1" counter=""
  UI_STEP_NO=$((UI_STEP_NO + 1))
  (( UI_STEP_TOTAL > 0 )) && counter="[${UI_STEP_NO}/${UI_STEP_TOTAL}] "
  printf '\n%s%s%s %s%s%s%s\n' "$C_BLUE" "$C_BOLD" "$G_ARROW" "$counter" "$title" "$C_RESET" ""
  log_line ""
  log_line "### ${counter}${title}"
}

ui_info()  { printf '  %s%s%s %s\n' "$C_BLUE" "$G_INFO" "$C_RESET" "$*"; log_line "[info] $*"; }
ui_ok()    { printf '  %s%s%s %s\n' "$C_GREEN" "$G_OK" "$C_RESET" "$*"; log_line "[ ok ] $*"; }
ui_note()  { printf '    %s%s%s\n' "$C_DIM" "$*" "$C_RESET"; log_line "       $*"; }
ui_warn()  {
  printf '  %s%s %s%s\n' "$C_YELLOW" "$G_WARN" "$*" "$C_RESET" >&2
  log_line "[WARN] $*"
  UI_WARNINGS+=("$*")
}
ui_error() {
  printf '  %s%s%s %s%s\n' "$C_RED" "$C_BOLD" "$G_FAIL" "$*" "$C_RESET" >&2
  log_line "[FAIL] $*"
  UI_ERRORS+=("$*")
}

# ui_die MESSAGE [HINT...] — print an error (plus optional hints) and exit 1.
ui_die() {
  ui_error "$1"; shift
  local h; for h in "$@"; do ui_note "$h"; done
  exit 1
}

# ui_kv KEY VALUE [WIDTH] — aligned "key  value" line.
ui_kv() {
  local w="${3:-22}"
  printf '    %s%-*s%s %s\n' "$C_GREY" "$w" "$1" "$C_RESET" "$2"
  log_line "    $(printf '%-*s' "$w" "$1") $2"
}

# ui_box LINE... — highlighted block for important instructions.
ui_box() {
  local line
  printf '\n'
  for line in "$@"; do
    printf '  %s┃%s %s\n' "$C_CYAN" "$C_RESET" "$line"
    log_line "  | $line"
  done
  printf '\n'
}

_ui_fmt_duration() {
  local s="$1"
  if (( s >= 60 )); then printf '%dm%02ds' $((s / 60)) $((s % 60)); else printf '%ds' "$s"; fi
}

# --- running commands ---------------------------------------------------------
# ui_run [--quiet-fail] [--tail N] LABEL -- CMD [ARGS...]
#
# Runs CMD in the background with stdin from /dev/null, shows a spinner, the
# elapsed time and the command's latest output line, and streams the full,
# redacted output into the log file. On failure the last lines of output are
# shown on screen (unless --quiet-fail). Returns CMD's exit status; the
# output stays available in "$UI_LAST_OUTPUT" until the next ui_run.
ui_run() {
  local quiet_fail=false tail_n=15
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --quiet-fail) quiet_fail=true; shift ;;
      --tail) tail_n="$2"; shift 2 ;;
      *) break ;;
    esac
  done
  local label="$1"; shift
  [[ "${1:-}" == "--" ]] && shift

  [[ -n "$UI_LAST_OUTPUT" && -f "$UI_LAST_OUTPUT" ]] && rm -f "$UI_LAST_OUTPUT"
  UI_LAST_OUTPUT="$(mktemp "${STATE_TMP_DIR:-/tmp}/run.XXXXXX")"

  log_line ""
  log_line ">>> $label"
  log_line "\$ $(log_quote_cmd "$@")"

  local start=$SECONDS rc=0 pid
  (
    set +e
    "$@" < /dev/null 2>&1 | log_stream "$UI_LAST_OUTPUT"
    exit "${PIPESTATUS[0]}"
  ) &
  pid=$!

  if [[ "$UI_FANCY" == true ]]; then
    local i=0 cols last elapsed lw
    cols=$(_ui_cols)
    _ui_cursor_hide
    while kill -0 "$pid" 2>/dev/null; do
      elapsed=$(_ui_fmt_duration $((SECONDS - start)))
      last=$(tail -n 1 "$UI_LAST_OUTPUT" 2>/dev/null | tr -d '\r' | tr '\t' ' ' | sed 's/\x1b\[[0-9;]*[A-Za-z]//g')
      lw=$((cols - ${#label} - ${#elapsed} - 12))
      (( lw < 0 )) && lw=0
      (( ${#last} > lw )) && last="${last:0:lw}"
      printf '\r\033[K  %s%s%s %s %s%s%s  %s%s%s' \
        "$C_CYAN" "${UI_SPIN[i % ${#UI_SPIN[@]}]}" "$C_RESET" "$label" \
        "$C_GREY" "$elapsed" "$C_RESET" "$C_DIM" "$last" "$C_RESET"
      i=$((i + 1))
      sleep 0.12
    done
    wait "$pid" || rc=$?
    printf '\r\033[K'
    _ui_cursor_show
  else
    printf '  %s… %s%s\n' "$C_GREY" "$label" "$C_RESET"
    wait "$pid" || rc=$?
  fi

  local took; took=$(_ui_fmt_duration $((SECONDS - start)))
  log_line "<<< exit=$rc duration=$took"
  if (( rc == 0 )); then
    printf '  %s%s%s %s %s(%s)%s\n' "$C_GREEN" "$G_OK" "$C_RESET" "$label" "$C_GREY" "$took" "$C_RESET"
  else
    printf '  %s%s%s %s %s(exit %s after %s)%s\n' "$C_RED" "$G_FAIL" "$C_RESET" "$label" "$C_GREY" "$rc" "$took" "$C_RESET"
    if [[ "$quiet_fail" == false ]]; then
      printf '    %slast output:%s\n' "$C_GREY" "$C_RESET"
      tail -n "$tail_n" "$UI_LAST_OUTPUT" | sed "s/^/    ${C_DIM}│${C_RESET} /"
      printf '    %sfull log: %s%s\n' "$C_GREY" "${LOG_FILE_REL:-}" "$C_RESET"
    fi
  fi
  return "$rc"
}

# ui_exec LABEL -- CMD [ARGS...] — for commands that need the terminal
# (password prompts, ssh-keygen). Output is shown live and NOT captured.
ui_exec() {
  local label="$1"; shift
  [[ "${1:-}" == "--" ]] && shift
  log_line ""
  log_line ">>> $label (interactive, output not captured)"
  log_line "\$ $(log_quote_cmd "$@")"
  printf '  %s%s%s %s\n' "$C_CYAN" "$G_ARROW" "$C_RESET" "$label"
  local rc=0
  "$@" || rc=$?
  log_line "<<< exit=$rc"
  if (( rc == 0 )); then ui_ok "$label"; else ui_error "$label failed (exit $rc)"; fi
  return "$rc"
}

# --- asking things ------------------------------------------------------------
# ui_require_tty WHAT — abort with a clear message when no terminal is
# attached (a hidden prompt would otherwise hang forever).
ui_require_tty() {
  if [[ "$UI_TTY_IN" != true ]]; then
    ui_die "No interactive terminal: can't ask for $1." \
      "Run the script from a terminal, or pass the value with a flag/answers file (see --help)."
  fi
}

_ui_read_key() {
  # Sets _UI_KEY to: up down left right enter space esc or the character.
  local k rest
  IFS= read -rsn1 k || { _UI_KEY="eof"; return; }
  if [[ "$k" == $'\e' ]]; then
    IFS= read -rsn2 -t 0.02 rest || true
    case "$rest" in
      '[A'|'OA') _UI_KEY="up" ;;
      '[B'|'OB') _UI_KEY="down" ;;
      '[C'|'OC') _UI_KEY="right" ;;
      '[D'|'OD') _UI_KEY="left" ;;
      '[5') IFS= read -rsn1 -t 0.02 _ || true; _UI_KEY="pgup" ;;
      '[6') IFS= read -rsn1 -t 0.02 _ || true; _UI_KEY="pgdown" ;;
      '') _UI_KEY="esc" ;;
      *) _UI_KEY="other" ;;
    esac
  elif [[ -z "$k" ]]; then
    _UI_KEY="enter"
  elif [[ "$k" == " " ]]; then
    _UI_KEY="space"
  else
    _UI_KEY="$k"
  fi
}

# Items are "value::label" or "value::label::hint". Parsed into _UI_V/_UI_L/_UI_H.
_ui_parse_items() {
  _UI_V=(); _UI_L=(); _UI_H=()
  local it v rest l h
  for it in "$@"; do
    v="${it%%::*}"
    if [[ "$it" == *::* ]]; then rest="${it#*::}"; else rest="$v"; fi
    if [[ "$rest" == *::* ]]; then l="${rest%%::*}"; h="${rest#*::}"; else l="$rest"; h=""; fi
    _UI_V+=("$v"); _UI_L+=("$l"); _UI_H+=("$h")
  done
}

_ui_question() {
  printf '  %s?%s %s%s%s' "$C_MAGENTA" "$C_RESET" "$C_BOLD" "$1" "$C_RESET"
}

# ui_select [--initial VALUE] PROMPT ITEM... — single choice.
# Sets UI_VALUE (item value) and UI_INDEX. ESC / q cancels → returns 1.
ui_select() {
  local initial=""
  [[ "${1:-}" == "--initial" ]] && { initial="$2"; shift 2; }
  local prompt="$1"; shift
  _ui_parse_items "$@"
  local n=${#_UI_V[@]} cur=0 i
  (( n == 0 )) && { ui_error "ui_select: no options for '$prompt'"; return 1; }
  if [[ -n "$initial" ]]; then
    for ((i = 0; i < n; i++)); do [[ "${_UI_V[i]}" == "$initial" ]] && cur=$i; done
  fi
  ui_require_tty "\"$prompt\""

  if [[ "$UI_FANCY" != true ]]; then
    _ui_question "$prompt"; printf '\n'
    for ((i = 0; i < n; i++)); do
      printf '    %2d) %s%s\n' $((i + 1)) "${_UI_L[i]}" "${_UI_H[i]:+  — ${_UI_H[i]}}"
    done
    local ans
    while true; do
      read -r -p "    choice [1-$n]: " ans || return 1
      if [[ "$ans" =~ ^[0-9]+$ ]] && (( ans >= 1 && ans <= n )); then cur=$((ans - 1)); break; fi
    done
  else
    local rows max top=0 drawn=0 line
    rows=$(_ui_rows); max=$((rows - 6)); (( max > 15 )) && max=15; (( max < 3 )) && max=3
    _ui_cursor_hide
    _ui_question "$prompt"
    printf '  %s(↑↓ move · enter select · q cancel)%s\n' "$C_GREY" "$C_RESET"
    while true; do
      (( cur < top )) && top=$cur
      (( cur >= top + max )) && top=$((cur - max + 1))
      (( drawn > 0 )) && printf '\033[%dA' "$drawn"
      drawn=0
      if (( top > 0 )); then printf '\033[K    %s%s more%s\n' "$C_GREY" "$G_UP" "$C_RESET"; else printf '\033[K\n'; fi
      drawn=$((drawn + 1))
      for ((i = top; i < top + max && i < n; i++)); do
        if (( i == cur )); then
          line=$(printf '  %s%s %s%s' "$C_CYAN" "$G_PTR" "${_UI_L[i]}" "$C_RESET")
          [[ -n "${_UI_H[i]}" ]] && line+=$(printf '  %s%s%s' "$C_DIM" "${_UI_H[i]}" "$C_RESET")
        else
          line=$(printf '    %s' "${_UI_L[i]}")
          [[ -n "${_UI_H[i]}" ]] && line+=$(printf '  %s%s%s' "$C_GREY" "${_UI_H[i]}" "$C_RESET")
        fi
        printf '\033[K%s\n' "$line"
        drawn=$((drawn + 1))
      done
      if (( top + max < n )); then printf '\033[K    %s%s more%s\n' "$C_GREY" "$G_DOWN" "$C_RESET"; else printf '\033[K\n'; fi
      drawn=$((drawn + 1))
      _ui_read_key
      case "$_UI_KEY" in
        up|k) (( cur > 0 )) && cur=$((cur - 1)) || cur=$((n - 1)) ;;
        down|j) (( cur < n - 1 )) && cur=$((cur + 1)) || cur=0 ;;
        pgup) cur=$((cur - max)); (( cur < 0 )) && cur=0 ;;
        pgdown) cur=$((cur + max)); (( cur >= n )) && cur=$((n - 1)) ;;
        enter) break ;;
        q|esc|eof)
          printf '\033[%dA\033[J\033[1A\r\033[K' "$drawn"
          _ui_question "$prompt"; printf ' %scancelled%s\n' "$C_GREY" "$C_RESET"
          _ui_cursor_show; log_line "[ask ] $prompt -> (cancelled)"; return 1 ;;
        [1-9]) (( _UI_KEY <= n )) && cur=$((_UI_KEY - 1)) ;;
      esac
    done
    printf '\033[%dA\033[J\033[1A\r\033[K' "$drawn"
    _ui_question "$prompt"; printf ' %s%s%s\n' "$C_CYAN" "${_UI_L[cur]}" "$C_RESET"
    _ui_cursor_show
  fi
  UI_INDEX=$cur
  UI_VALUE="${_UI_V[cur]}"
  log_line "[ask ] $prompt -> ${_UI_L[cur]}"
  return 0
}

# ui_checklist [--on "v1 v2"] [--min N] PROMPT ITEM... — multiple choice.
# Sets UI_SELECTED (values, in item order). Returns 1 when cancelled.
ui_checklist() {
  local preset="" min=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --on) preset="$2"; shift 2 ;;
      --min) min="$2"; shift 2 ;;
      *) break ;;
    esac
  done
  local prompt="$1"; shift
  _ui_parse_items "$@"
  local n=${#_UI_V[@]} cur=0 i
  local -a on=()
  for ((i = 0; i < n; i++)); do
    if [[ " $preset " == *" ${_UI_V[i]} "* ]]; then on[i]=1; else on[i]=0; fi
  done
  ui_require_tty "\"$prompt\""

  if [[ "$UI_FANCY" != true ]]; then
    _ui_question "$prompt"; printf '\n'
    for ((i = 0; i < n; i++)); do
      printf '    %2d) %s%s\n' $((i + 1)) "${_UI_L[i]}" "${_UI_H[i]:+  — ${_UI_H[i]}}"
    done
    local ans tok ok
    while true; do
      read -r -p "    numbers separated by spaces (empty = none): " ans || return 1
      ok=true
      for ((i = 0; i < n; i++)); do on[i]=0; done
      for tok in $ans; do
        if [[ "$tok" =~ ^[0-9]+$ ]] && (( tok >= 1 && tok <= n )); then on[tok - 1]=1; else ok=false; fi
      done
      local cnt=0; for ((i = 0; i < n; i++)); do cnt=$((cnt + on[i])); done
      [[ "$ok" == true ]] && (( cnt >= min )) && break
      printf '    %sinvalid selection (minimum %s)%s\n' "$C_YELLOW" "$min" "$C_RESET"
    done
  else
    local rows max top=0 drawn=0 line box msg=""
    rows=$(_ui_rows); max=$((rows - 7)); (( max > 15 )) && max=15; (( max < 3 )) && max=3
    _ui_cursor_hide
    _ui_question "$prompt"
    printf '  %s(↑↓ move · space toggle · a all · n none · enter confirm · q cancel)%s\n' "$C_GREY" "$C_RESET"
    while true; do
      (( cur < top )) && top=$cur
      (( cur >= top + max )) && top=$((cur - max + 1))
      (( drawn > 0 )) && printf '\033[%dA' "$drawn"
      drawn=0
      if (( top > 0 )); then printf '\033[K    %s%s more%s\n' "$C_GREY" "$G_UP" "$C_RESET"; else printf '\033[K\n'; fi
      drawn=$((drawn + 1))
      for ((i = top; i < top + max && i < n; i++)); do
        if (( on[i] )); then box="${C_GREEN}${G_BOX_ON}${C_RESET}"; else box="${C_GREY}${G_BOX_OFF}${C_RESET}"; fi
        if (( i == cur )); then
          line=$(printf '  %s%s%s %s %s%s%s' "$C_CYAN" "$G_PTR" "$C_RESET" "$box" "$C_BOLD" "${_UI_L[i]}" "$C_RESET")
          [[ -n "${_UI_H[i]}" ]] && line+=$(printf '  %s%s%s' "$C_DIM" "${_UI_H[i]}" "$C_RESET")
        else
          line=$(printf '    %s %s' "$box" "${_UI_L[i]}")
          [[ -n "${_UI_H[i]}" ]] && line+=$(printf '  %s%s%s' "$C_GREY" "${_UI_H[i]}" "$C_RESET")
        fi
        printf '\033[K%s\n' "$line"
        drawn=$((drawn + 1))
      done
      if (( top + max < n )); then printf '\033[K    %s%s more%s' "$C_GREY" "$G_DOWN" "$C_RESET"; fi
      printf '\033[K  %s%s%s\n' "$C_YELLOW" "$msg" "$C_RESET"
      drawn=$((drawn + 1)); msg=""
      _ui_read_key
      case "$_UI_KEY" in
        up|k) (( cur > 0 )) && cur=$((cur - 1)) || cur=$((n - 1)) ;;
        down|j) (( cur < n - 1 )) && cur=$((cur + 1)) || cur=0 ;;
        pgup) cur=$((cur - max)); (( cur < 0 )) && cur=0 ;;
        pgdown) cur=$((cur + max)); (( cur >= n )) && cur=$((n - 1)) ;;
        space|x|right) on[cur]=$((1 - on[cur])) ;;
        a) for ((i = 0; i < n; i++)); do on[i]=1; done ;;
        n) for ((i = 0; i < n; i++)); do on[i]=0; done ;;
        enter)
          local cnt=0; for ((i = 0; i < n; i++)); do cnt=$((cnt + on[i])); done
          (( cnt >= min )) && break
          msg="select at least $min item(s)" ;;
        q|esc|eof)
          printf '\033[%dA\033[J\033[1A\r\033[K' "$drawn"
          _ui_question "$prompt"; printf ' %scancelled%s\n' "$C_GREY" "$C_RESET"
          _ui_cursor_show; log_line "[ask ] $prompt -> (cancelled)"; return 1 ;;
      esac
    done
    printf '\033[%dA\033[J\033[1A\r\033[K' "$drawn"
  fi

  UI_SELECTED=()
  local labels=()
  for ((i = 0; i < n; i++)); do
    if (( on[i] )); then UI_SELECTED+=("${_UI_V[i]}"); labels+=("${_UI_L[i]}"); fi
  done
  if [[ "$UI_FANCY" == true ]]; then
    _ui_question "$prompt"
    if (( ${#labels[@]} )); then
      printf ' %s%s%s\n' "$C_CYAN" "$(IFS=,; printf '%s' "${labels[*]}" | sed 's/,/, /g')" "$C_RESET"
    else
      printf ' %snone%s\n' "$C_GREY" "$C_RESET"
    fi
    _ui_cursor_show
  fi
  log_line "[ask ] $prompt -> ${labels[*]:-(none)}"
  return 0
}

# ui_input [--default VALUE] [--validate FUNC] [--error MSG] [--allow-empty] PROMPT
# Sets UI_VALUE. FUNC receives the value and returns 0 when valid.
ui_input() {
  local def="" validate="" err="invalid value" allow_empty=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --default) def="$2"; shift 2 ;;
      --validate) validate="$2"; shift 2 ;;
      --error) err="$2"; shift 2 ;;
      --allow-empty) allow_empty=true; shift ;;
      *) break ;;
    esac
  done
  local prompt="$1" ans
  ui_require_tty "\"$prompt\""
  while true; do
    _ui_question "$prompt"
    [[ -n "$def" ]] && printf ' %s[%s]%s' "$C_GREY" "$def" "$C_RESET"
    printf ' '
    IFS= read -r ans || ans=""
    [[ -z "$ans" ]] && ans="$def"
    ans="${ans#"${ans%%[![:space:]]*}"}"; ans="${ans%"${ans##*[![:space:]]}"}"
    if [[ -z "$ans" && "$allow_empty" == false ]]; then
      printf '    %sa value is required%s\n' "$C_YELLOW" "$C_RESET"; continue
    fi
    if [[ -n "$ans" && -n "$validate" ]] && ! "$validate" "$ans"; then
      printf '    %s%s%s\n' "$C_YELLOW" "$err" "$C_RESET"; continue
    fi
    break
  done
  UI_VALUE="$ans"
  log_line "[ask ] $prompt -> $ans"
}

# ui_secret [--generate CMD] [--keep] [--validate FUNC] [--error MSG] PROMPT
# Hidden input, typed twice. With --generate, an empty answer runs CMD and
# uses its output; with --keep, an empty answer returns UI_VALUE="" and
# UI_SECRET_KEPT=true. Sets UI_VALUE; the value is registered for redaction.
UI_SECRET_KEPT=false
ui_secret() {
  local gen="" keep=false validate="" err="invalid value"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --generate) gen="$2"; shift 2 ;;
      --keep) keep=true; shift ;;
      --validate) validate="$2"; shift 2 ;;
      --error) err="$2"; shift 2 ;;
      *) break ;;
    esac
  done
  local prompt="$1" a b hint=""
  UI_SECRET_KEPT=false
  ui_require_tty "\"$prompt\""
  if [[ "$keep" == true ]]; then hint="enter = keep current"
  elif [[ -n "$gen" ]]; then hint="enter = generate random"; fi
  while true; do
    _ui_question "$prompt"
    [[ -n "$hint" ]] && printf ' %s[%s]%s' "$C_GREY" "$hint" "$C_RESET"
    printf ' '
    IFS= read -rs a || a=""; printf '\n'
    if [[ -z "$a" ]]; then
      if [[ "$keep" == true ]]; then
        UI_VALUE=""; UI_SECRET_KEPT=true
        printf '    %skept the current value%s\n' "$C_GREY" "$C_RESET"
        log_line "[ask ] $prompt -> (kept)"; return 0
      elif [[ -n "$gen" ]]; then
        UI_VALUE="$(eval "$gen")"
        log_add_secret "$UI_VALUE"
        printf '    %sgenerated a random value (%d characters)%s\n' "$C_GREY" "${#UI_VALUE}" "$C_RESET"
        log_line "[ask ] $prompt -> (generated)"; return 0
      fi
      printf '    %sa value is required%s\n' "$C_YELLOW" "$C_RESET"; continue
    fi
    if [[ -n "$validate" ]] && ! "$validate" "$a"; then
      printf '    %s%s%s\n' "$C_YELLOW" "$err" "$C_RESET"; continue
    fi
    _ui_question "Repeat to confirm"; printf ' '
    IFS= read -rs b || b=""; printf '\n'
    if [[ "$a" != "$b" ]]; then
      printf '    %sthe two values differ — try again%s\n' "$C_YELLOW" "$C_RESET"; continue
    fi
    break
  done
  UI_VALUE="$a"
  log_add_secret "$UI_VALUE"
  log_line "[ask ] $prompt -> (typed, hidden)"
}

# ui_confirm QUESTION [y|n] — yes/no. Without a default an explicit answer is
# required. Returns 0 for yes.
ui_confirm() {
  local q="$1" def="${2:-}" ans hint="y/n"
  ui_require_tty "a confirmation (\"$q\")"
  [[ "$def" == y ]] && hint="Y/n"
  [[ "$def" == n ]] && hint="y/N"
  while true; do
    _ui_question "$q"; printf ' %s[%s]%s ' "$C_GREY" "$hint" "$C_RESET"
    IFS= read -r ans || ans=""
    [[ -z "$ans" ]] && ans="$def"
    case "${ans,,}" in
      y|yes) log_line "[ask ] $q -> yes"; return 0 ;;
      n|no) log_line "[ask ] $q -> no"; return 1 ;;
    esac
    printf '    %splease answer y or n%s\n' "$C_YELLOW" "$C_RESET"
  done
}

# ui_confirm_typed QUESTION PHRASE — returns 0 only if PHRASE is typed exactly.
ui_confirm_typed() {
  local q="$1" phrase="$2" ans
  ui_require_tty "a confirmation (\"$q\")"
  _ui_question "$q"
  printf '\n    %stype %s%s%s%s to confirm, anything else cancels:%s ' "$C_GREY" "$C_RESET$C_BOLD$C_RED" "$phrase" "$C_RESET" "$C_GREY" "$C_RESET"
  IFS= read -r ans || ans=""
  if [[ "$ans" == "$phrase" ]]; then log_line "[ask ] $q -> confirmed"; return 0; fi
  log_line "[ask ] $q -> not confirmed"
  return 1
}

ui_pause() {
  ui_require_tty "a key press"
  printf '  %s%s%s ' "$C_GREY" "${1:-Press enter to continue…}" "$C_RESET"
  IFS= read -r _ || true
}

# ui_summary — final block: warnings, errors and the log path.
ui_summary() {
  local rc="${1:-0}" w
  printf '\n'
  ui_rule
  if (( ${#UI_WARNINGS[@]} )); then
    printf '  %s%s %d warning(s):%s\n' "$C_YELLOW" "$G_WARN" "${#UI_WARNINGS[@]}" "$C_RESET"
    for w in "${UI_WARNINGS[@]}"; do printf '    %s%s%s %s\n' "$C_YELLOW" "$G_DOT" "$C_RESET" "$w"; done
  fi
  if (( ${#UI_ERRORS[@]} )); then
    printf '  %s%s %d error(s):%s\n' "$C_RED" "$G_FAIL" "${#UI_ERRORS[@]}" "$C_RESET"
    for w in "${UI_ERRORS[@]}"; do printf '    %s%s%s %s\n' "$C_RED" "$G_DOT" "$C_RESET" "$w"; done
  fi
  if (( rc == 0 )); then
    printf '  %s%s%s %sFinished%s' "$C_GREEN" "$G_OK" "$C_RESET" "$C_BOLD" "$C_RESET"
  elif (( rc == 130 )); then
    printf '  %s%s%s %sInterrupted%s' "$C_YELLOW" "$G_WARN" "$C_RESET" "$C_BOLD" "$C_RESET"
  else
    printf '  %s%s%s %sStopped with exit code %s%s' "$C_RED" "$G_FAIL" "$C_RESET" "$C_BOLD" "$rc" "$C_RESET"
  fi
  [[ -n "${LOG_FILE_REL:-}" ]] && printf '  %slog: %s%s' "$C_GREY" "$LOG_FILE_REL" "$C_RESET"
  printf '\n'
  ui_rule
}
