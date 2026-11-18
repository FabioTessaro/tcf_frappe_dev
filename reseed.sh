#!/usr/bin/env bash
# reseed.sh — replace the VS Code Server inside the running frappe container.
#
# Usage: ./reseed.sh [options]
#
# Use it when your VS Code client updated (new commit), when "Attach to
# Running Container" hangs, or when the server inside the container is broken.
# The chosen build is downloaded on the host and copied into the container,
# replacing any existing copy of the same build.
#
# Without options a menu is shown every time, with the commit detected on
# this host (the client that last connected over Remote-SSH), the latest
# stable release for your client platform, and a free commit field.
#
# Options:
#   --detect             use the commit detected on this host
#   --latest             use the latest stable release (see --platform)
#   --commit HASH        use this 40-character commit (Help › About › Commit)
#   --platform NAME      client platform for --latest: win32-x64-user,
#                        win32-arm64-user, darwin-universal, linux-x64,
#                        linux-arm64, server-linux-x64 (remembered)
#   --purge              also delete every other build from the container
#   --keep-others        keep the other builds (don't ask)
#   -y, --yes            don't ask for confirmation
#   --trace              also write a bash execution trace into the log
#   -h, --help           show this help
#
# Requires running containers (start them with ./initialize.sh).
# After reseeding, reload any attached VS Code window (Developer: Reload Window).
set -o pipefail
# shellcheck source=bootstrap/lib/common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/bootstrap/lib/common.sh"
# shellcheck source=bootstrap/lib/vscode.sh
source "$LIB_DIR/vscode.sh"

VS_WANT=""; VS_WANT_COMMIT=""; VS_PLATFORM=""; PURGE=""; ASSUME_YES=false
for a in "$@"; do [[ "$a" == -h || "$a" == --help ]] && { usage_from_header "$0"; exit 0; }; done
script_init reseed "$@"
set -- "${SCRIPT_ARGS[@]}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --detect) VS_WANT=detect ;;
    --latest) VS_WANT=latest ;;
    --commit) VS_WANT=commit; VS_WANT_COMMIT="${2:-}"; shift ;;
    --commit=*) VS_WANT=commit; VS_WANT_COMMIT="${1#*=}" ;;
    --platform) VS_PLATFORM="${2:-}"; shift ;;
    --platform=*) VS_PLATFORM="${1#*=}" ;;
    --purge) PURGE=true ;;
    --keep-others) PURGE=false ;;
    -y|--yes) ASSUME_YES=true ;;
    *) ui_die "Unknown option: $1" "See ./reseed.sh --help" ;;
  esac
  shift
done

ui_banner "frappe-dev · reseed" "VS Code Server in the container"

[[ -f "$COMPOSE_FILE" ]] || ui_die "docker-compose.yml not found." "Configure and start the environment first: ./setup.sh && ./initialize.sh"
docker_require
frappe_running || ui_die "The frappe container isn't running." "Start the environment with ./initialize.sh, then run ./reseed.sh again."

vscode_choose reseed || { ui_info "Cancelled — nothing changed."; exit 0; }
[[ -n "$VS_COMMIT" ]] || { ui_info "Nothing to do."; exit 0; }

others=$(vscode_container_builds | grep -vx "$VS_COMMIT" | wc -l)
if [[ -z "$PURGE" ]]; then
  if (( others > 0 )); then
    ui_select "The container has $others other build(s). Remove them?" \
      "false::Keep them::windows attached with an older client keep working" \
      "true::Delete them::frees disk space; windows using them must be reloaded" || exit 1
    PURGE="$UI_VALUE"
  else
    PURGE=false
  fi
fi

ui_section "Reseed"
ui_kv "Commit" "$VS_COMMIT"
ui_kv "Source" "${VS_SOURCE}${VS_VERSION:+ ($VS_VERSION)}${VS_PLATFORM:+, platform $VS_PLATFORM}"
ui_kv "Other builds" "$([[ $PURGE == true ]] && echo "deleted ($others)" || echo "kept ($others)")"
if [[ "$ASSUME_YES" != true ]]; then ui_confirm "Replace the VS Code Server build in the container?" || { ui_info "Cancelled."; exit 0; }; fi

args=(--force); [[ "$PURGE" == true ]] && args+=(--purge)
vscode_seed "$VS_COMMIT" "${args[@]}" || ui_die "Reseeding failed." "See ${LOG_FILE_REL}"
ui_ok "Done. Reload any attached VS Code window (Developer: Reload Window)."
