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
  G_UP='▲'; G_DOWN='▼'; G_ELL='…'
  UI_SPIN=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
else
  G_OK='OK'; G_FAIL='XX'; G_WARN='!!'; G_INFO='--'; G_ARROW='->'; G_DOT='.'
  G_ON='(*)'; G_OFF='( )'; G_BOX_ON='[x]'; G_BOX_OFF='[ ]'; G_PTR='>'; G_RULE='-'
  G_UP='^'; G_DOWN='v'; G_ELL='~'
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

# _ui_term_size — current terminal size into _UI_COLS / _UI_ROWS. Asks the
# terminal itself (stty on /dev/tty): inside $(…) stdout is a pipe, so tput
# would silently fall back to 80 columns.
_UI_COLS=80; _UI_ROWS=24
_ui_term_size() {
  local s=""
  [[ "$UI_TTY_OUT" == true || "$UI_TTY_IN" == true ]] && s=$(stty size < /dev/tty 2>/dev/null)
  if [[ "$s" =~ ^([0-9]+)\ ([0-9]+)$ ]] && (( BASH_REMATCH[2] > 0 )); then
    _UI_ROWS=${BASH_REMATCH[1]}; _UI_COLS=${BASH_REMATCH[2]}
  else
    _UI_COLS=$(tput cols 2>/dev/null || echo 80); _UI_ROWS=$(tput lines 2>/dev/null || echo 24)
    [[ "$_UI_COLS" =~ ^[0-9]+$ ]] || _UI_COLS=80
    [[ "$_UI_ROWS" =~ ^[0-9]+$ ]] || _UI_ROWS=24
  fi
  (( _UI_COLS < 20 )) && _UI_COLS=20
  (( _UI_ROWS < 8 )) && _UI_ROWS=8
  return 0
}

# _ui_cols — width for rules and wrapping (terminal width, at most 100).
_ui_cols() {
  _ui_term_size
  local c=$_UI_COLS; (( c > 100 )) && c=100
  printf '%s' "$c"
}

_ui_rows() { _ui_term_size; printf '%s' "$_UI_ROWS"; }

# _ui_trunc TEXT MAX — TEXT cut to MAX visible characters (ANSI colour codes
# don't count) with an ellipsis. Result in _UI_T (no subshell: used per frame).
_ui_trunc() {
  local s="$1" max="$2" plain="$1" re=$'\e''\[[0-9;?]*[A-Za-z]'
  while [[ "$plain" =~ $re ]]; do plain="${plain/"${BASH_REMATCH[0]}"/}"; done
  if (( ${#plain} <= max )); then _UI_T="$s"; return 0; fi
  local out="" vis=0 i=0 len=${#s} keep=$((max - 1)) c esc
  (( keep < 0 )) && keep=0
  while (( i < len )); do
    c="${s:i:1}"
    if [[ "$c" == $'\e' ]]; then
      esc="$c"; i=$((i + 1))
      while (( i < len )); do c="${s:i:1}"; esc+="$c"; i=$((i + 1)); [[ "$c" == [A-Za-z] ]] && break; done
      out+="$esc"; continue
    fi
    if (( vis < keep )); then out+="$c"; vis=$((vis + 1)); fi
    i=$((i + 1))
  done
  _UI_T="${out}${G_ELL}${C_RESET}"
}

# _ui_wrapped FIRST CONT WIDTH SUFFIX TEXT — prints TEXT wrapped to the
# terminal: the first line after the (coloured) prefix FIRST, following lines
# after CONT; both prefixes are WIDTH characters wide. SUFFIX ends every line.
# Without a terminal the text is printed on one line.
_ui_wrapped() {
  local first="$1" cont="$2" pw="$3" suffix="$4" text="$5" w line n=0
  if [[ "$UI_TTY_OUT" != true ]]; then printf '%s%s%s\n' "$first" "$text" "$suffix"; return 0; fi
  w=$(( $(_ui_cols) - pw - 1 )); (( w < 10 )) && w=10
  while IFS= read -r line || [[ -n "$line" ]]; do
    if (( n == 0 )); then printf '%s%s%s\n' "$first" "$line" "$suffix"; else printf '%s%s%s\n' "$cont" "$line" "$suffix"; fi
    n=$((n + 1))
  done < <(printf '%s\n' "$text" | fold -s -w "$w" | sed 's/[[:space:]]*$//')
  (( n == 0 )) && printf '%s%s\n' "$first" "$suffix"
  return 0
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

ui_info()  { _ui_wrapped "  $C_BLUE$G_INFO$C_RESET " "    " 4 "" "$*"; log_line "[info] $*"; }
ui_ok()    { _ui_wrapped "  $C_GREEN$G_OK$C_RESET " "    " 4 "" "$*"; log_line "[ ok ] $*"; }
ui_note()  { _ui_wrapped "    $C_DIM" "    $C_DIM" 4 "$C_RESET" "$*"; log_line "       $*"; }
ui_warn()  {
  _ui_wrapped "  $C_YELLOW$G_WARN " "  $C_YELLOW  " 4 "$C_RESET" "$*" >&2
  log_line "[WARN] $*"
  UI_WARNINGS+=("$*")
}
ui_error() {
  _ui_wrapped "  $C_RED$C_BOLD$G_FAIL$C_RESET $C_RED" "    $C_RED" 4 "$C_RESET" "$*" >&2
  log_line "[FAIL] $*"
  UI_ERRORS+=("$*")
}

# ui_die MESSAGE [HINT...] — print an error (plus optional hints) and exit 1.
ui_die() {
  ui_error "$1"; shift
  local h; for h in "$@"; do ui_note "$h"; done
  exit 1
}

# ui_kv KEY VALUE [WIDTH] — aligned "key  value" line (value wraps under itself;
# on narrow terminals the value moves below the key).
ui_kv() {
  local w="${3:-22}" k="$1" pad
  log_line "    $(printf '%-*s' "$w" "$k") $2"
  if [[ "$UI_TTY_OUT" == true ]] && (( $(_ui_cols) - w - 6 < 20 )); then
    printf '    %s%s%s\n' "$C_GREY" "$k" "$C_RESET"
    _ui_wrapped "      " "      " 6 "" "$2"; return 0
  fi
  pad=$(printf '%*s' $((w + 5)) '')
  _ui_wrapped "$(printf '    %s%-*s%s ' "$C_GREY" "$w" "$k" "$C_RESET")" "$pad" $((w + 5)) "" "$2"
}

# ui_box LINE... — highlighted block for important instructions.
ui_box() {
  local line
  printf '\n'
  for line in "$@"; do
    _ui_wrapped "  $C_CYAN┃$C_RESET " "  $C_CYAN┃$C_RESET   " 4 "" "$line"
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
    local i=0 last elapsed frame
    _ui_cursor_hide
    while kill -0 "$pid" 2>/dev/null; do
      (( i % 8 == 0 )) && _ui_term_size          # follow terminal resizes
      elapsed=$(_ui_fmt_duration $((SECONDS - start)))
      last=$(tail -n 1 "$UI_LAST_OUTPUT" 2>/dev/null | tr -d '\r' | tr '\t' ' ' | sed 's/\x1b\[[0-9;?]*[A-Za-z]//g')
      frame="  $C_CYAN${UI_SPIN[i % ${#UI_SPIN[@]}]}$C_RESET $label $C_GREY$elapsed$C_RESET  $C_DIM$last$C_RESET"
      _ui_trunc "$frame" $((_UI_COLS - 1))
      printf '\r\033[K%s' "$_UI_T"
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
    _ui_wrapped "  $C_GREEN$G_OK$C_RESET " "    " 4 "" "$label $C_GREY($took)$C_RESET"
  else
    _ui_wrapped "  $C_RED$G_FAIL$C_RESET " "    " 4 "" "$label $C_GREY(exit $rc after $took)$C_RESET"
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
  # _ui_read_key [TIMEOUT] — sets _UI_KEY to: up down left right pgup pgdown
  # enter space esc eof, "tick" when TIMEOUT expired, or the character.
  local k rest rc=0
  if [[ -n "${1:-}" ]]; then
    IFS= read -rsn1 -t "$1" k || rc=$?
    if (( rc > 128 )); then _UI_KEY="tick"; return 0; fi
    (( rc != 0 )) && { _UI_KEY="eof"; return 0; }
  else
    IFS= read -rsn1 k || { _UI_KEY="eof"; return 0; }
  fi
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

# _ui_answer PROMPT ANSWER_COLOURED — final "? prompt answer" line (wraps).
_ui_answer() {
  _ui_wrapped "  $C_MAGENTA?$C_RESET " "    " 4 "" "$C_BOLD$1$C_RESET $2$C_RESET"
}

# --- shared menu engine ----------------------------------------------------------
# Uses the caller's locals (bash dynamic scoping): _mkind (select|check),
# _mprompt, n, cur, top, max, drawn, on[] and msg (checklist only).
# Every row is truncated to the terminal width so it occupies exactly one
# screen line; that keeps the "move up N lines and redraw" arithmetic exact.
_ui_menu_header() {
  local hint
  if [[ "$_mkind" == select ]]; then
    if (( _UI_COLS >= 72 )); then hint="(↑↓ move · enter select · q cancel)"; else hint="(↑↓ · enter · q)"; fi
  else
    if (( _UI_COLS >= 104 )); then hint="(↑↓ move · space toggle · a all · n none · enter confirm · q cancel)"
    else hint="(↑↓ · space · a/n · enter · q)"; fi
  fi
  _ui_trunc "  $C_MAGENTA?$C_RESET $C_BOLD$_mprompt$C_RESET  $C_GREY$hint$C_RESET" $((_UI_COLS - 1))
  printf '\r\033[K%s\n' "$_UI_T"
}

_ui_menu_max() {
  local reserve=6; [[ "$_mkind" == check ]] && reserve=7
  max=$((_UI_ROWS - reserve)); (( max > 15 )) && max=15; (( max < 3 )) && max=3
  return 0
}

_ui_menu_render() {
  local i line box w=$((_UI_COLS - 1))
  (( cur < top )) && top=$cur
  (( cur >= top + max )) && top=$((cur - max + 1))
  (( drawn > 0 )) && printf '\033[%dA' "$drawn"
  drawn=0
  line=""; (( top > 0 )) && line="    $C_GREY$G_UP more$C_RESET"
  printf '\033[K%s\n' "$line"; drawn=$((drawn + 1))
  for ((i = top; i < top + max && i < n; i++)); do
    box=""
    if [[ "$_mkind" == check ]]; then
      if (( on[i] )); then box="$C_GREEN$G_BOX_ON$C_RESET "; else box="$C_GREY$G_BOX_OFF$C_RESET "; fi
    fi
    if (( i == cur )); then
      line="  $C_CYAN$G_PTR$C_RESET $box$C_CYAN$C_BOLD${_UI_L[i]}$C_RESET"
      [[ -n "${_UI_H[i]}" ]] && line+="  $C_DIM${_UI_H[i]}$C_RESET"
    else
      line="    $box${_UI_L[i]}"
      [[ -n "${_UI_H[i]}" ]] && line+="  $C_GREY${_UI_H[i]}$C_RESET"
    fi
    _ui_trunc "$line" "$w"
    printf '\033[K%s\n' "$_UI_T"; drawn=$((drawn + 1))
  done
  line=""; (( top + max < n )) && line="    $C_GREY$G_DOWN more$C_RESET"
  [[ -n "${msg:-}" ]] && line+="  $C_YELLOW$msg$C_RESET"
  _ui_trunc "$line" "$w"
  printf '\033[K%s\n' "$_UI_T"; drawn=$((drawn + 1))
}

# _ui_menu_clear — removes the menu and its header line.
_ui_menu_clear() { printf '\033[%dA\033[J\033[1A\r\033[K' "$drawn"; }

# _ui_menu_loop — runs the key loop; returns 0 on enter, 1 on cancel.
_ui_menu_loop() {
  local sc sr redraw=1 cnt j
  _ui_term_size; sc=$_UI_COLS; sr=$_UI_ROWS
  _ui_menu_max
  _ui_cursor_hide
  _ui_menu_header
  while true; do
    (( redraw )) && _ui_menu_render
    redraw=1
    _ui_read_key 0.25
    case "$_UI_KEY" in
      tick)
        _ui_term_size
        if (( _UI_COLS != sc || _UI_ROWS != sr )); then
          # Resized: wrapped/reflowed lines make relative moves unreliable,
          # so start from a clean screen.
          sc=$_UI_COLS; sr=$_UI_ROWS
          printf '\033[2J\033[H'; drawn=0
          _ui_menu_max; _ui_menu_header
        else
          redraw=0
        fi ;;
      up|k) (( cur > 0 )) && cur=$((cur - 1)) || cur=$((n - 1)) ;;
      down|j) (( cur < n - 1 )) && cur=$((cur + 1)) || cur=0 ;;
      pgup) cur=$((cur - max)); (( cur < 0 )) && cur=0 ;;
      pgdown) cur=$((cur + max)); (( cur >= n )) && cur=$((n - 1)) ;;
      enter)
        if [[ "$_mkind" == check ]]; then
          cnt=0; for ((j = 0; j < n; j++)); do cnt=$((cnt + on[j])); done
          (( cnt >= min )) && return 0
          msg="select at least $min item(s)"
        else
          return 0
        fi ;;
      q|esc|eof) return 1 ;;
      *)
        if [[ "$_mkind" == check ]]; then
          case "$_UI_KEY" in
            space|x|right) on[cur]=$((1 - on[cur])); msg="" ;;
            a) for ((j = 0; j < n; j++)); do on[j]=1; done; msg="" ;;
            n) for ((j = 0; j < n; j++)); do on[j]=0; done; msg="" ;;
            *) redraw=0 ;;
          esac
        elif [[ "$_UI_KEY" == [1-9] ]] && (( _UI_KEY <= n )); then
          cur=$((_UI_KEY - 1))
        else
          redraw=0
        fi ;;
    esac
  done
}

# ui_select [--initial VALUE] PROMPT ITEM... — single choice.
# Sets UI_VALUE (item value) and UI_INDEX. ESC / q cancels → returns 1.
ui_select() {
  local initial=""
  [[ "${1:-}" == "--initial" ]] && { initial="$2"; shift 2; }
  local _mprompt="$1" _mkind=select; shift
  _ui_parse_items "$@"
  local n=${#_UI_V[@]} cur=0 i top=0 max=3 drawn=0
  (( n == 0 )) && { ui_error "ui_select: no options for '$_mprompt'"; return 1; }
  if [[ -n "$initial" ]]; then
    for ((i = 0; i < n; i++)); do [[ "${_UI_V[i]}" == "$initial" ]] && cur=$i; done
  fi
  ui_require_tty "\"$_mprompt\""

  if [[ "$UI_FANCY" != true ]]; then
    _ui_question "$_mprompt"; printf '\n'
    for ((i = 0; i < n; i++)); do
      printf '    %2d) %s%s\n' $((i + 1)) "${_UI_L[i]}" "${_UI_H[i]:+  — ${_UI_H[i]}}"
    done
    local ans
    while true; do
      read -r -p "    choice [1-$n]: " ans || return 1
      if [[ "$ans" =~ ^[0-9]+$ ]] && (( ans >= 1 && ans <= n )); then cur=$((ans - 1)); break; fi
    done
  else
    if ! _ui_menu_loop; then
      _ui_menu_clear; _ui_answer "$_mprompt" "${C_GREY}cancelled"
      _ui_cursor_show; log_line "[ask ] $_mprompt -> (cancelled)"; return 1
    fi
    _ui_menu_clear; _ui_answer "$_mprompt" "$C_CYAN${_UI_L[cur]}"
    _ui_cursor_show
  fi
  UI_INDEX=$cur
  UI_VALUE="${_UI_V[cur]}"
  log_line "[ask ] $_mprompt -> ${_UI_L[cur]}"
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
  local _mprompt="$1" _mkind=check msg=""; shift
  _ui_parse_items "$@"
  local n=${#_UI_V[@]} cur=0 i top=0 max=3 drawn=0
  local -a on=()
  for ((i = 0; i < n; i++)); do
    if [[ " $preset " == *" ${_UI_V[i]} "* ]]; then on[i]=1; else on[i]=0; fi
  done
  ui_require_tty "\"$_mprompt\""

  if [[ "$UI_FANCY" != true ]]; then
    _ui_question "$_mprompt"; printf '\n'
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
  elif ! _ui_menu_loop; then
    _ui_menu_clear; _ui_answer "$_mprompt" "${C_GREY}cancelled"
    _ui_cursor_show; log_line "[ask ] $_mprompt -> (cancelled)"; return 1
  else
    _ui_menu_clear
  fi

  UI_SELECTED=()
  local labels=()
  for ((i = 0; i < n; i++)); do
    if (( on[i] )); then UI_SELECTED+=("${_UI_V[i]}"); labels+=("${_UI_L[i]}"); fi
  done
  if [[ "$UI_FANCY" == true ]]; then
    if (( ${#labels[@]} )); then
      _ui_answer "$_mprompt" "$C_CYAN$(join , "${labels[@]}" | sed 's/,/, /g')"
    else
      _ui_answer "$_mprompt" "${C_GREY}none"
    fi
    _ui_cursor_show
  fi
  log_line "[ask ] $_mprompt -> ${labels[*]:-(none)}"
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

# _ui_read_masked — reads a line echoing "*" per character (backspace works).
# Result in _UI_MASKED. Falls back to a silent read without a full terminal.
_ui_read_masked() {
  _UI_MASKED=""
  if [[ "$UI_FANCY" != true ]]; then IFS= read -rs _UI_MASKED || true; printf '\n'; return 0; fi
  local c rest
  while IFS= read -rsn1 c; do
    if [[ -z "$c" ]]; then break                                  # enter
    elif [[ "$c" == $'\x7f' || "$c" == $'\b' ]]; then             # backspace
      if (( ${#_UI_MASKED} )); then _UI_MASKED="${_UI_MASKED%?}"; printf '\b \b'; fi
    elif [[ "$c" == $'\x15' ]]; then                              # ctrl-u: clear
      while (( ${#_UI_MASKED} )); do _UI_MASKED="${_UI_MASKED%?}"; printf '\b \b'; done
    elif [[ "$c" == $'\e' ]]; then IFS= read -rsn2 -t 0.02 rest || true   # ignore arrows
    else _UI_MASKED+="$c"; printf '*'
    fi
  done
  printf '\n'
}

# ui_secret [--generate CMD] [--keep] [--validate FUNC] [--error MSG] [--weak FUNC] PROMPT
# Input shown as "*", typed twice. With --generate, an empty answer runs CMD
# and uses its output; with --keep, an empty answer returns UI_VALUE="" and
# UI_SECRET_KEPT=true. --validate is a hard rule (value refused); --weak FUNC
# prints a reason when the value is weak, and the user may keep it anyway.
# Sets UI_VALUE; the value is registered for redaction in the logs.
UI_SECRET_KEPT=false
ui_secret() {
  local gen="" keep=false validate="" err="invalid value" weak=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --generate) gen="$2"; shift 2 ;;
      --keep) keep=true; shift ;;
      --validate) validate="$2"; shift 2 ;;
      --error) err="$2"; shift 2 ;;
      --weak) weak="$2"; shift 2 ;;
      *) break ;;
    esac
  done
  local prompt="$1" a b hint="" reason
  UI_SECRET_KEPT=false
  ui_require_tty "\"$prompt\""
  if [[ "$keep" == true ]]; then hint="enter = keep current"
  elif [[ -n "$gen" ]]; then hint="enter = generate random"; fi
  while true; do
    _ui_question "$prompt"
    [[ -n "$hint" ]] && printf ' %s[%s]%s' "$C_GREY" "$hint" "$C_RESET"
    printf ' '
    _ui_read_masked; a="$_UI_MASKED"
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
    _ui_read_masked; b="$_UI_MASKED"
    if [[ "$a" != "$b" ]]; then
      printf '    %sthe two values differ — try again%s\n' "$C_YELLOW" "$C_RESET"; continue
    fi
    if [[ -n "$weak" ]]; then
      reason="$("$weak" "$a")"
      if [[ -n "$reason" ]]; then
        printf '    %s%s %s%s\n' "$C_YELLOW" "$G_WARN" "$reason" "$C_RESET"
        ui_confirm "Use it anyway?" || continue
        log_line "[ask ] $prompt -> weak value accepted ($reason)"
      fi
    fi
    break
  done
  UI_VALUE="$a"
  log_add_secret "$UI_VALUE"
  log_line "[ask ] $prompt -> (typed, ${#a} characters)"
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
