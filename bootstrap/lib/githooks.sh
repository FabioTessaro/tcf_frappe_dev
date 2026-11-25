#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# bootstrap/lib/githooks.sh — git hooks that work on the host AND in the frappe
# container. Shared by install.sh (host), initialize.sh through
# bootstrap/container/provision.sh (container), new-platform.sh and `just setup`.
#
# The host and the container share every .git directory (this repository,
# platform/, the custom apps in frappe-bench/apps/). `pre-commit install`
# writes the absolute path of ITS Python into the hook, so a hook installed on
# one side breaks on the other (e.g. "/usr/bin/python3: No module named
# pre_commit" in the container). The hook written here instead looks for
# pre-commit when it runs: on the PATH, in ~/.local/bin, then any python3 that
# can import pre_commit. Each side still needs pre-commit installed:
# install.sh (base) on the host, initialize.sh in the container.
#
#   git_hooks_types DIR     hook types of DIR's .pre-commit-config.yaml
#                           (default_install_hook_types, else pre-commit)
#   git_hooks_ok DIR        0 when every hook type has the current portable hook
#   git_hooks_install DIR   write the portable hooks (replaces pre-commit's)
#   git_hooks_repos ROOT    this repository, platform/ and the custom apps under
#                           ROOT that have a .pre-commit-config.yaml (one per line)
#
# The hooks keep pre-commit's "ID:" marker, so `pre-commit install` and
# `pre-commit uninstall` still treat them as their own (no *.legacy copies).
# -----------------------------------------------------------------------------

GIT_HOOKS_VERSION=1

git_hooks_types() {
  local cfg="$1/.pre-commit-config.yaml" types
  types=$(sed -n 's/^default_install_hook_types:[[:space:]]*\[\(.*\)\].*/\1/p' "$cfg" 2>/dev/null | tr ',' ' ')
  printf '%s' "${types:-pre-commit}" | xargs
}

# _git_hooks_dir DIR — absolute hooks directory of the repository in DIR.
_git_hooks_dir() {
  local h
  h=$(git -C "$1" rev-parse --git-path hooks 2>/dev/null) || return 1
  [[ "$h" == /* ]] || h="$1/$h"
  printf '%s' "$h"
}

# _git_hook_script TYPE — the portable hook for one hook type.
_git_hook_script() {
  cat <<EOF
#!/usr/bin/env bash
# Git hook written by frappe-dev (bootstrap/lib/githooks.sh, v$GIT_HOOKS_VERSION).
# Portable: finds pre-commit when it runs, so the same hook works on the host
# and in the frappe container, which share this .git directory.
# Reinstall: ./install.sh (host) or ./initialize.sh (container).
# ID: 138fd403232d2ddd5efb44317e38bf03
ARGS=(hook-impl --config=.pre-commit-config.yaml --hook-type=$1)
ARGS+=(--hook-dir "\$(cd "\$(dirname "\$0")" && pwd)" -- "\$@")
for pc in pre-commit "\$HOME/.local/bin/pre-commit" /usr/local/bin/pre-commit /usr/bin/pre-commit; do
  command -v "\$pc" >/dev/null 2>&1 && exec "\$pc" "\${ARGS[@]}"
done
for py in python3 /usr/bin/python3; do
  "\$py" -c 'import pre_commit' >/dev/null 2>&1 && exec "\$py" -m pre_commit "\${ARGS[@]}"
done
echo 'pre-commit not found: run ./install.sh --components base (host) or ./initialize.sh (container).' >&2
exit 1
EOF
}

git_hooks_ok() {
  local dir="$1" hooks t
  hooks=$(_git_hooks_dir "$dir") || return 1
  for t in $(git_hooks_types "$dir"); do
    [[ -x "$hooks/$t" && "$(cat "$hooks/$t")" == "$(_git_hook_script "$t")" ]] || return 1
  done
}

git_hooks_install() {
  local dir="$1" hooks t
  hooks=$(_git_hooks_dir "$dir") || { echo "$dir is not a git repository" >&2; return 1; }
  mkdir -p "$hooks" || return 1
  for t in $(git_hooks_types "$dir"); do
    _git_hook_script "$t" > "$hooks/$t" && chmod 755 "$hooks/$t" || return 1
    rm -f "$hooks/$t.legacy"
  done
}

git_hooks_repos() {
  local root="$1" d
  for d in "$root" "$root/platform" "$root"/frappe-bench/apps/*; do
    [[ -e "$d/.git" && -f "$d/.pre-commit-config.yaml" ]] || continue
    # Default (vendored) apps are third-party clones: leave their hooks alone.
    if [[ "$d" == "$root"/frappe-bench/apps/* ]] && ! _git_hooks_custom_app "$root" "${d##*/}"; then continue; fi
    printf '%s\n' "$d"
  done
}

# _git_hooks_custom_app ROOT NAME — NAME is listed in CUSTOM_APPS of ROOT/.env.
_git_hooks_custom_app() {
  local apps
  apps=$(sed -n 's/^[[:space:]]*CUSTOM_APPS[[:space:]]*=[[:space:]]*//p' "$1/.env" 2>/dev/null | tail -n 1 | tr -d "\"'")
  [[ " $apps " == *" $2 "* ]]
}
