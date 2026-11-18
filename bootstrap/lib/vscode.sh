#!/usr/bin/env bash
# shellcheck disable=SC2034
# -----------------------------------------------------------------------------
# bootstrap/lib/vscode.sh — pick and pre-seed the VS Code Server build.
# -----------------------------------------------------------------------------
# Why: "Dev Containers: Attach to Running Container" normally streams the
# ~200 MB VS Code Server tarball into the container through `docker exec`
# stdin, which hangs intermittently on some Docker Engine versions. Instead
# we download the tarball with curl on the host and `docker cp` it into
# ~/.vscode-server/bin/<commit> inside the container. VS Code then finds the
# server already there and attaches instantly.
#
# The build must match the COMMIT of the VS Code client you connect from
# (Help › About › Commit). Sources, best first:
#   detected  ~/.vscode-server on this host: the server your client installed
#             when it connected over Remote-SSH (newest one wins).
#   latest    Microsoft's update API: the latest stable commit for the
#             platform your client runs on (asked once, cached in .state).
#   commit    a commit you type.
#
# vscode_choose      interactive menu (or flags) → VS_COMMIT, VS_SOURCE
# vscode_seed HASH   copy the build into the container (idempotent)
# vscode_extensions HASH  install the extensions from templates/vscode
# -----------------------------------------------------------------------------

VS_PLATFORMS=(
  "win32-x64-user::Windows (x64)"
  "win32-arm64-user::Windows (ARM64)"
  "darwin-universal::macOS (Intel or Apple Silicon)"
  "linux-x64::Linux (x64)"
  "linux-arm64::Linux (ARM64)"
  "server-linux-x64::Not sure — latest Linux server build"
)
VS_PLATFORM_CACHE="$STATE_DIR/vscode-platform"
VS_COMMIT_STATE="$STATE_DIR/vscode-commit"
VS_CACHE_DIR="$STATE_DIR/cache/vscode-server"
VS_CONTAINER_BIN="${CONTAINER_HOME:-/home/frappe}/.vscode-server/bin"

VS_COMMIT=""; VS_SOURCE=""; VS_VERSION=""
VS_HOST_COMMIT=""; VS_HOST_WHEN=""

_vs_platform_valid() {
  local p; for p in "${VS_PLATFORMS[@]}"; do [[ "${p%%::*}" == "$1" ]] && return 0; done; return 1
}

# vscode_detect_host — newest server your client installed on this host.
vscode_detect_host() {
  VS_HOST_COMMIT=""; VS_HOST_WHEN=""
  local best="" best_t=0 d t h
  for d in "$HOME"/.vscode-server/cli/servers/Stable-* "$HOME"/.vscode-server/bin/*; do
    [[ -d "$d" ]] || continue
    h="${d##*/}"; h="${h#Stable-}"
    valid_commit "$h" || continue
    t=$(stat -c %Y "$d" 2>/dev/null || echo 0)
    if (( t > best_t )); then best_t=$t; best=$h; fi
  done
  # code-<hash> launcher next to cli/ (newer Remote-SSH layout)
  for d in "$HOME"/.vscode-server/code-*; do
    [[ -e "$d" ]] || continue
    h="${d##*/code-}"
    valid_commit "$h" || continue
    t=$(stat -c %Y "$d" 2>/dev/null || echo 0)
    if (( t > best_t )); then best_t=$t; best=$h; fi
  done
  if [[ -n "$best" ]]; then
    VS_HOST_COMMIT="$best"
    VS_HOST_WHEN="$(date -d "@$best_t" '+%Y-%m-%d %H:%M' 2>/dev/null)"
  fi
  log_line "vscode host detection: commit=${VS_HOST_COMMIT:-none} when=${VS_HOST_WHEN:-n/a}"
}

# vscode_latest PLATFORM — sets VS_LATEST_COMMIT and VS_LATEST_VERSION.
vscode_latest() {
  VS_LATEST_COMMIT=""; VS_LATEST_VERSION=""
  local json
  json=$(curl -fsSL --max-time 20 "https://update.code.visualstudio.com/api/update/$1/stable/latest" 2>>"$LOG_FILE") \
    || json=$(curl -fsSL --max-time 20 "https://update.code.visualstudio.com/api/latest/$1/stable" 2>>"$LOG_FILE") \
    || return 1
  VS_LATEST_COMMIT=$(printf '%s' "$json" | grep -oE '"version"[[:space:]]*:[[:space:]]*"[0-9a-f]{40}"' | head -1 | grep -oE '[0-9a-f]{40}')
  VS_LATEST_VERSION=$(printf '%s' "$json" | grep -oE '"productVersion"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | sed -E 's/.*"([^"]+)"$/\1/')
  log_line "vscode latest for $1: ${VS_LATEST_COMMIT:-?} (${VS_LATEST_VERSION:-?})"
  valid_commit "$VS_LATEST_COMMIT"
}

# vscode_container_builds — builds already present inside the container.
vscode_container_builds() {
  cx sh -c "for d in '$VS_CONTAINER_BIN'/*; do [ -f \"\$d/product.json\" ] && basename \"\$d\"; done 2>/dev/null" 2>/dev/null | tr -d '\r'
}

vscode_ask_platform() {
  ui_select --initial "$(cat "$VS_PLATFORM_CACHE" 2>/dev/null)" \
    "Which platform does your LOCAL VS Code client run on?" "${VS_PLATFORMS[@]}" || return 1
  VS_PLATFORM="$UI_VALUE"
  printf '%s\n' "$VS_PLATFORM" > "$VS_PLATFORM_CACHE"
}

# vscode_choose CONTEXT — CONTEXT is "initialize" or "reseed".
# Honours (when set by the caller's flags) VS_WANT=detect|latest|commit|skip,
# VS_WANT_COMMIT, VS_PLATFORM. Without them shows the menu every time.
# Sets VS_COMMIT (empty when skipped) and VS_SOURCE. Returns 1 if cancelled.
vscode_choose() {
  local context="$1"
  VS_COMMIT=""; VS_SOURCE=""; VS_VERSION=""
  [[ -z "${VS_PLATFORM:-}" && -f "$VS_PLATFORM_CACHE" ]] && VS_PLATFORM="$(cat "$VS_PLATFORM_CACHE")"
  if [[ -n "${VS_PLATFORM:-}" ]] && ! _vs_platform_valid "$VS_PLATFORM"; then
    ui_warn "Unknown VS Code platform '$VS_PLATFORM' — ignoring it."; VS_PLATFORM=""
  fi

  vscode_detect_host

  # Non-interactive choices from flags.
  case "${VS_WANT:-}" in
    skip) VS_SOURCE="skip"; return 0 ;;
    commit)
      VS_WANT_COMMIT="$(printf '%s' "$VS_WANT_COMMIT" | tr -d '[:space:]' | tr 'A-F' 'a-f')"
      valid_commit "$VS_WANT_COMMIT" || ui_die "'$VS_WANT_COMMIT' is not a 40-character VS Code commit."
      VS_COMMIT="$VS_WANT_COMMIT"; VS_SOURCE="commit"; return 0 ;;
    detect)
      [[ -n "$VS_HOST_COMMIT" ]] || ui_die "No VS Code Server found in ~/.vscode-server on this host." \
        "Connect to this host once with VS Code Remote-SSH, or use --vscode-latest / --vscode-commit."
      VS_COMMIT="$VS_HOST_COMMIT"; VS_SOURCE="detected"; return 0 ;;
    latest)
      if [[ -z "${VS_PLATFORM:-}" ]]; then vscode_ask_platform || return 1; fi
      vscode_latest "$VS_PLATFORM" || ui_die "Couldn't query the latest VS Code release (no internet access to update.code.visualstudio.com?)."
      VS_COMMIT="$VS_LATEST_COMMIT"; VS_VERSION="$VS_LATEST_VERSION"; VS_SOURCE="latest"; return 0 ;;
  esac

  # Interactive menu.
  ui_info "VS Code Server for the container"
  if [[ -n "$VS_HOST_COMMIT" ]]; then
    ui_kv "Detected on this host" "${VS_HOST_COMMIT:0:12}…  (last used ${VS_HOST_WHEN})"
  else
    ui_kv "Detected on this host" "none — you haven't connected with VS Code Remote-SSH yet"
  fi
  if [[ -n "${VS_PLATFORM:-}" ]]; then
    if vscode_latest "$VS_PLATFORM"; then
      ui_kv "Latest stable" "${VS_LATEST_VERSION:-?}  ${VS_LATEST_COMMIT:0:12}…  ($VS_PLATFORM)"
    else
      ui_kv "Latest stable" "couldn't be queried (offline?)"
    fi
  fi
  if frappe_running; then
    local builds; builds=$(vscode_container_builds | sed 's/^\(.\{12\}\).*/\1…/' | paste -sd' ')
    ui_kv "Already in container" "${builds:-none}"
  fi

  local items=()
  if [[ -n "$VS_HOST_COMMIT" ]]; then
    items+=("detected::Use the commit detected on this host::recommended — matches the client that connected")
  fi
  if [[ -n "${VS_PLATFORM:-}" && -n "${VS_LATEST_COMMIT:-}" ]]; then
    items+=("latest::Use the latest stable release (${VS_LATEST_VERSION:-?}, $VS_PLATFORM)")
    items+=("platform::Latest stable for a different platform…")
  else
    items+=("platform::Use the latest stable release…::asks which platform your client runs on")
  fi
  items+=("commit::Enter a commit by hand…::VS Code › Help › About › Commit")
  if [[ "$context" == initialize ]]; then
    items+=("skip::Skip — don't pre-seed now::run ./reseed.sh later")
  else
    items+=("cancel::Cancel")
  fi

  ui_select "Which VS Code Server build should be seeded?" "${items[@]}" || return 1
  case "$UI_VALUE" in
    detected) VS_COMMIT="$VS_HOST_COMMIT"; VS_SOURCE="detected" ;;
    latest) VS_COMMIT="$VS_LATEST_COMMIT"; VS_VERSION="$VS_LATEST_VERSION"; VS_SOURCE="latest" ;;
    platform)
      vscode_ask_platform || return 1
      vscode_latest "$VS_PLATFORM" || ui_die "Couldn't query the latest VS Code release (offline?)."
      VS_COMMIT="$VS_LATEST_COMMIT"; VS_VERSION="$VS_LATEST_VERSION"; VS_SOURCE="latest" ;;
    commit)
      ui_input --validate valid_commit --error "expected 40 lowercase hex characters" "Commit"
      VS_COMMIT="${UI_VALUE,,}"; VS_SOURCE="commit" ;;
    skip) VS_SOURCE="skip" ;;
    cancel) return 1 ;;
  esac
  return 0
}

# _vscode_tarball HASH — path of the cached tarball. Derived from the hash
# (not stored in a variable) because ui_run runs steps in a subshell.
_vscode_tarball() { printf '%s/vscode-server-%s.tar.gz' "$VS_CACHE_DIR" "$1"; }

# vscode_download HASH — downloads into the cache (kept between runs).
vscode_download() {
  local hash="$1" VS_TARBALL
  mkdir -p "$VS_CACHE_DIR"
  VS_TARBALL="$(_vscode_tarball "$hash")"
  if [[ -s "$VS_TARBALL" ]] && tar -tzf "$VS_TARBALL" >/dev/null 2>&1; then
    log_line "using cached $VS_TARBALL"; return 0
  fi
  rm -f "$VS_TARBALL"
  echo "downloading https://update.code.visualstudio.com/commit:$hash/server-linux-x64/stable"
  curl -fsSL --show-error --retry 3 --connect-timeout 20 -o "$VS_TARBALL.part" \
    "https://update.code.visualstudio.com/commit:$hash/server-linux-x64/stable" || { rm -f "$VS_TARBALL.part"; return 1; }
  echo "downloaded $(du -h "$VS_TARBALL.part" | cut -f1)"
  tar -tzf "$VS_TARBALL.part" >/dev/null || { echo "downloaded archive is corrupt"; rm -f "$VS_TARBALL.part"; return 1; }
  mv "$VS_TARBALL.part" "$VS_TARBALL"
  # Keep only the 3 most recent tarballs.
  ls -1t "$VS_CACHE_DIR"/vscode-server-*.tar.gz 2>/dev/null | tail -n +4 | xargs -r rm -f
}

# _vscode_copy HASH FORCE — extract the cached tarball into the container.
_vscode_copy() {
  local hash="$1" force="$2" target="$VS_CONTAINER_BIN/$1" tmp src entries tarball
  tarball="$(_vscode_tarball "$hash")"
  [[ -s "$tarball" ]] || { echo "cached tarball missing: $tarball"; return 1; }
  tmp=$(mktemp -d "$STATE_TMP_DIR/vscode.XXXXXX")
  echo "extracting $tarball"
  tar -xzf "$tarball" -C "$tmp" || return 1
  src="$tmp"
  entries=$(find "$tmp" -mindepth 1 -maxdepth 1)
  if [[ $(printf '%s\n' "$entries" | wc -l) -eq 1 && -d "$entries" ]]; then src="$entries"; fi
  if [[ "$force" == true ]]; then
    echo "removing the existing copy of $hash"
    cx_root sh -c "rm -rf '$target' '$VS_CONTAINER_BIN/${hash}'_*" || return 1
  fi
  cx_root mkdir -p "$target" || return 1
  echo "copying into frappe:$target"
  dc cp "$src/." "frappe:$target/" || return 1
  cx_root chown -R "$CONTAINER_USER:$CONTAINER_USER" "${CONTAINER_HOME}/.vscode-server" || return 1
  rm -rf "$tmp"
  cx test -f "$target/product.json" || { echo "product.json missing after copy"; return 1; }
}

# vscode_seed HASH [--force] [--purge] — idempotent unless --force.
vscode_seed() {
  local hash="$1" force=false purge=false a
  shift
  for a in "$@"; do
    case "$a" in --force) force=true ;; --purge) purge=true ;; esac
  done
  if [[ "$force" == false ]] && cx test -f "$VS_CONTAINER_BIN/$hash/product.json" 2>/dev/null; then
    ui_ok "VS Code Server ${hash:0:12}… is already in the container"
  else
    ui_run "Downloading VS Code Server ${hash:0:12}…" -- vscode_download "$hash" \
      || { ui_error "Download failed — is $hash a real VS Code commit, and is update.code.visualstudio.com reachable?"; return 1; }
    ui_run "Copying VS Code Server into the container" -- _vscode_copy "$hash" "$force" \
      || { ui_error "Copying the VS Code Server into the container failed."; return 1; }
  fi
  printf '%s\n' "$hash" > "$VS_COMMIT_STATE"
  if [[ "$purge" == true ]]; then
    ui_run "Removing other VS Code Server builds from the container" -- \
      cx_root sh -c "find '$VS_CONTAINER_BIN' -mindepth 1 -maxdepth 1 ! -name '$hash' -exec rm -rf {} +"
  fi
  return 0
}

# vscode_extensions HASH — install templates/vscode/extensions.list into the
# container's VS Code Server, so they're ready on the first attach.
vscode_extensions() {
  local hash="$1" list="$TEMPLATE_DIR/vscode/extensions.list" ext cli failed=()
  cli="$VS_CONTAINER_BIN/$hash/bin/code-server"
  [[ -f "$list" ]] || return 0
  if ! cx test -x "$cli" 2>/dev/null; then
    ui_warn "VS Code Server ${hash:0:12}… not found in the container — skipping extension installation."
    return 0
  fi
  local installed
  installed=$(cx "$cli" --list-extensions 2>/dev/null | tr 'A-Z' 'a-z' | tr -d '\r')
  while IFS= read -r ext || [[ -n "$ext" ]]; do
    ext="${ext%%#*}"; ext="${ext//[[:space:]]/}"
    [[ -z "$ext" ]] && continue
    if printf '%s\n' "$installed" | grep -qxF "${ext,,}"; then
      log_line "extension already installed: $ext"; continue
    fi
    ui_run --quiet-fail "Installing extension $ext" -- cx "$cli" --install-extension "$ext" || failed+=("$ext")
  done < "$list"
  if (( ${#failed[@]} )); then
    ui_warn "Some VS Code extensions couldn't be installed: ${failed[*]} (VS Code will offer them as workspace recommendations)."
  else
    ui_ok "VS Code extensions are installed in the container"
  fi
}
