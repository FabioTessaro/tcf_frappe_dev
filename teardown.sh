#!/usr/bin/env bash
# teardown.sh — stop the environment and clean it, up to a blank folder.
#
# Usage: ./teardown.sh [targets] [options]
#
# Without targets a checklist is shown. Targets (combine freely):
#   --stop               only stop the containers (they keep their state;
#                        ./initialize.sh starts them again)
#   --containers         stop and remove the containers and the network
#   --volumes[=LIST]     delete named volumes — all, or a comma list of:
#                        mariadb, seaweedfs, clamav, vscode, claude
#                        (mariadb = database, seaweedfs = uploaded files)
#   --images             remove the images used by this project
#   --prune              docker: remove dangling images, unused networks and
#                        the build cache (SYSTEM-WIDE, not only this project)
#   --bench              delete frappe-bench/ (apps, custom-app clones, sites)
#   --platform           delete platform/ (the platform repository checkout)
#                        and its Docker leftovers (CI tool-cache volume, local
#                        CI / platform images, end-to-end stack volumes)
#   --workspace          delete the generated .vscode/ files
#   --config             delete .env and docker-compose.yml
#   --untracked          delete every other file git doesn't track in this
#                        repository (caches, answers files, .claude/, book
#                        output, your new uncommitted files)
#   --state              delete .state/ (VS Code cache, snapshots, backups)
#   --logs               delete logs/ (including this run's log)
#   --all                everything above except --stop: back to a fresh
#                        clone — only the files git tracks stay (your edits
#                        to them included)
#
# Work that exists only on this machine — uncommitted or untracked files,
# commits on no remote, stashes — in platform/, in the custom-app clones and
# (with --untracked) in this repository is listed and needs its own typed
# confirmation before anything is deleted.
#
# Options:
#   --dry-run            show what would be removed, change nothing
#   -y, --yes            skip the "continue?" question (typed confirmations
#                        for data deletion are still asked)
#   --force              also skip the typed confirmations (automation only!)
#   --trace              also write a bash execution trace into the log
#   -h, --help           show this help
#
# Running it again is always safe: missing things are reported and skipped.
# Host-level setup from ./install.sh (Docker, git, SSH key, FTP) is never
# touched.
set -o pipefail
# shellcheck source=bootstrap/lib/common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/bootstrap/lib/common.sh"

ALL_TARGETS=(containers volumes images prune bench platform workspace config untracked state logs)
PLATFORM_DIR="$REPO_ROOT/platform"
# Paths owned by a target of their own: --untracked never touches them.
OWNED_PATHS=(.env docker-compose.yml logs/ .state/ frappe-bench/ platform/ .vscode/)
declare -A T=()
VOLUME_LIST=""; DRY_RUN=false; ASSUME_YES=false; FORCE=false; STOP_ONLY=false
VOLUME_KEYS=(mariadb seaweedfs clamav vscode claude)
declare -A VOLUME_NAME=([mariadb]=mariadb-data [seaweedfs]=seaweedfs-data [clamav]=clamav-db [vscode]=vscode-server [claude]=claude-config)
declare -A VOLUME_DESC=([mariadb]="database (all sites' data)" [seaweedfs]="uploaded files / buckets" [clamav]="antivirus signatures (downloaded again on start)" [vscode]="VS Code Server + extensions" [claude]="Claude Code settings & login")

for a in "$@"; do [[ "$a" == -h || "$a" == --help ]] && { usage_from_header "$0"; exit 0; }; done
script_init teardown "$@"
set -- "${SCRIPT_ARGS[@]}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --stop) STOP_ONLY=true ;;
    --containers|--images|--prune|--bench|--platform|--workspace|--config|--untracked|--state|--logs) T[${1#--}]=1 ;;
    --volumes) T[volumes]=1; VOLUME_LIST=all ;;
    --volumes=*) T[volumes]=1; VOLUME_LIST="${1#*=}" ;;
    --all) for t in "${ALL_TARGETS[@]}"; do T[$t]=1; done; VOLUME_LIST=all ;;
    --dry-run) DRY_RUN=true ;;
    -y|--yes) ASSUME_YES=true ;;
    --force) FORCE=true; ASSUME_YES=true ;;
    *) ui_die "Unknown option: $1" "See ./teardown.sh --help" ;;
  esac
  shift
done

ui_banner "frappe-dev · teardown" "$([[ $DRY_RUN == true ]] && echo "dry run — nothing is changed" || echo "stop & clean")"

docker_detect
HAVE_DOCKER=false; [[ "$DOCKER_STATUS" == 0 ]] && HAVE_DOCKER=true
[[ "$HAVE_DOCKER" == true ]] || ui_warn "Docker isn't reachable — container, volume and image targets will be skipped."

# --- what exists ---------------------------------------------------------------
existing_volumes() {
  [[ "$HAVE_DOCKER" == true ]] || return 0
  dk volume ls -q --filter "label=com.docker.compose.project=$COMPOSE_PROJECT_NAME" 2>/dev/null
}
count_lines() { grep -c . <<< "$1"; }
CONTAINERS=""; VOLUMES=""; RUNNING=""
if [[ "$HAVE_DOCKER" == true ]]; then
  CONTAINERS=$(project_containers 2>/dev/null)
  RUNNING=$(project_running_services | paste -sd' ')
  VOLUMES=$(existing_volumes)
fi
du_h() { du -sh "$1" 2>/dev/null | cut -f1; }

# repo_work DIR — work that exists only in this clone: uncommitted or
# untracked files, commits on no remote (any branch), stashes. Empty if none.
repo_work() {
  local d="$1" dirty unpushed stash out=""
  dirty=$(git -C "$d" status --porcelain 2>/dev/null | wc -l)
  unpushed=$(git -C "$d" log --oneline --branches --not --remotes 2>/dev/null | wc -l)
  stash=$(git -C "$d" stash list 2>/dev/null | wc -l)
  (( dirty )) && out+="$dirty uncommitted/untracked file(s), "
  (( unpushed )) && out+="$unpushed commit(s) on no remote, "
  (( stash )) && out+="$stash stash(es), "
  printf '%s' "${out%, }"
}

# Files git doesn't track in this repository, outside OWNED_PATHS:
# UNTRACKED_ALL (everything) and UNTRACKED_WORK (not ignored = your files).
UNTRACKED_ALL=(); UNTRACKED_WORK=()
_owned() { local p="$1" o; for o in "${OWNED_PATHS[@]}"; do [[ "$p" == "$o" || "$p" == "$o"* ]] && return 0; done; return 1; }
while IFS= read -r -d '' f; do _owned "$f" || UNTRACKED_ALL+=("$f"); done \
  < <(git -C "$REPO_ROOT" ls-files --others --directory -z 2>/dev/null)
while IFS= read -r -d '' f; do _owned "$f" || UNTRACKED_WORK+=("$f"); done \
  < <(git -C "$REPO_ROOT" ls-files --others --exclude-standard --directory -z 2>/dev/null)

# Docker leftovers of the platform recipes (see platform/justfile).
platform_docker_leftovers() {
  [[ "$HAVE_DOCKER" == true ]] || return 0
  local url owner repo
  url=$(git -C "$PLATFORM_DIR" remote get-url origin 2>/dev/null)
  if [[ -z "$url" && -f "$ENV_FILE" ]]; then url=$(sed -n "s/^PLATFORM_URL='\{0,1\}\([^']*\)'\{0,1\}$/\1/p" "$ENV_FILE"); fi
  if [[ "$url" =~ github\.com[:/]([^/]+)/([^/]+)$ ]]; then
    owner="${BASH_REMATCH[1],,}"; repo="${BASH_REMATCH[2]%.git}"; repo="${repo,,}"
    dk image ls --format '{{.Repository}}:{{.Tag}}' | grep -E "^ghcr\.io/$owner/(ci|$repo):" | sed 's/^/image /'
  fi
  dk volume inspect platform-ci-cache >/dev/null 2>&1 && echo "volume platform-ci-cache"
  dk volume ls -q --filter "label=com.docker.compose.project=platform-e2e" | sed 's/^/volume /'
}

# --- stop only ----------------------------------------------------------------
if [[ "$STOP_ONLY" == true ]]; then
  (( ${#T[@]} )) && ui_die "--stop can't be combined with other targets."
  [[ "$HAVE_DOCKER" == true ]] || exit 0
  if [[ -z "$RUNNING" ]]; then ui_ok "No project containers are running."; exit 0; fi
  [[ "$DRY_RUN" == true ]] && { ui_info "Would stop: $RUNNING"; exit 0; }
  # shellcheck disable=SC2046
  ui_run "Stopping $RUNNING" -- dk stop $(project_containers --running) || ui_die "docker stop failed."
  ui_info "Start them again with ./initialize.sh"
  exit 0
fi

# --- interactive selection ------------------------------------------------------
if (( ${#T[@]} == 0 )); then
  ui_checklist --min 1 "What should be removed?" \
    "containers::Containers and network::$(count_lines "$CONTAINERS") container(s)$([[ -n $RUNNING ]] && echo ", running: $RUNNING")" \
    "volumes::Docker volumes…::$(count_lines "$VOLUMES") volume(s) — database, files, antivirus, VS Code, Claude" \
    "images::Project images::re-downloaded on the next ./initialize.sh" \
    "prune::Docker prune::dangling images, unused networks, build cache (system-wide)" \
    "bench::frappe-bench/::$( [[ -d $BENCH_DIR ]] && echo "$(du_h "$BENCH_DIR") — apps, custom-app clones, sites" || echo "not present")" \
    "platform::platform/::$( [[ -d $PLATFORM_DIR ]] && echo "$(du_h "$PLATFORM_DIR") — platform repository checkout + its Docker leftovers" || echo "not present")" \
    "workspace::.vscode/ generated files::$( [[ -d $VSCODE_DIR ]] && echo present || echo "not present")" \
    "config::.env and docker-compose.yml::$( [[ -f $ENV_FILE ]] && echo ".env present (secrets!)" || echo "not present")" \
    "untracked::Other files git doesn't track::${#UNTRACKED_ALL[@]} path(s) — caches, answers files, .claude/, ${#UNTRACKED_WORK[@]} of yours" \
    "state::.state/::$( [[ -d $STATE_DIR ]] && echo "$(du_h "$STATE_DIR") — VS Code cache, snapshots, .env backups" || echo "not present")" \
    "logs::logs/::$( [[ -d $LOG_DIR ]] && echo "$(du_h "$LOG_DIR")" || echo "not present")" || exit 1
  for t in "${UI_SELECTED[@]}"; do T[$t]=1; done
fi

# Volumes: which ones.
SEL_VOLUMES=()
if [[ -n "${T[volumes]:-}" ]]; then
  if [[ -z "$VOLUME_LIST" ]]; then
    items=()
    for k in "${VOLUME_KEYS[@]}"; do
      full="${COMPOSE_PROJECT_NAME}_${VOLUME_NAME[$k]}"
      grep -qx "$full" <<< "$VOLUMES" && items+=("$k::${VOLUME_NAME[$k]}::${VOLUME_DESC[$k]}")
    done
    if (( ${#items[@]} )); then
      ui_checklist --min 1 "Which volumes should be deleted?" "${items[@]}" || exit 1
      SEL_VOLUMES=("${UI_SELECTED[@]}")
    fi
  elif [[ "$VOLUME_LIST" == all ]]; then
    SEL_VOLUMES=("${VOLUME_KEYS[@]}")
  else
    IFS=',' read -r -a SEL_VOLUMES <<< "$VOLUME_LIST"
    for k in "${SEL_VOLUMES[@]}"; do
      [[ -n "${VOLUME_NAME[$k]:-}" ]] || ui_die "Unknown volume '$k'." "Valid: ${VOLUME_KEYS[*]}"
    done
  fi
fi
# Removing volumes or images requires removing the containers first.
if [[ ${#SEL_VOLUMES[@]} -gt 0 || -n "${T[images]:-}" ]]; then T[containers]=1; fi

# --- plan ---------------------------------------------------------------------------
UI_STEP_TOTAL=0
ui_section "Plan"
DESTRUCTIVE=(); AT_RISK=()
plan() { ui_kv "$1" "$2" 14; }
[[ -n "${T[containers]:-}" ]] && plan "containers" "$( [[ -n $CONTAINERS ]] && echo "remove $(count_lines "$CONTAINERS") container(s) + network" || echo "none found")"
if (( ${#SEL_VOLUMES[@]} )); then
  for k in "${SEL_VOLUMES[@]}"; do
    full="${COMPOSE_PROJECT_NAME}_${VOLUME_NAME[$k]}"
    if grep -qx "$full" <<< "$VOLUMES"; then
      plan "volume" "$full — ${VOLUME_DESC[$k]}"
      [[ "$k" == mariadb || "$k" == seaweedfs ]] && DESTRUCTIVE+=("volume $full (${VOLUME_DESC[$k]})")
    else
      plan "volume" "$full — not present"
    fi
  done
fi
[[ -n "${T[images]:-}" ]] && plan "images" "remove the images of this project"
[[ -n "${T[prune]:-}" ]] && plan "prune" "dangling images, unused networks, build cache (system-wide)"
if [[ -n "${T[bench]:-}" ]]; then
  if [[ -d "$BENCH_DIR" ]]; then
    plan "bench" "delete frappe-bench/ ($(du_h "$BENCH_DIR"))"; DESTRUCTIVE+=("frappe-bench/ (custom-app clones included)")
    # Work that exists only in the custom-app clones?
    for d in "$BENCH_DIR"/apps/*/; do
      [[ -d "$d/.git" ]] || continue
      n=$(basename "$d"); w=$(repo_work "$d")
      [[ -n "$w" ]] && AT_RISK+=("frappe-bench/apps/$n: $w")
    done
  else plan "bench" "frappe-bench/ — not present"; fi
fi
if [[ -n "${T[platform]:-}" ]]; then
  if [[ -d "$PLATFORM_DIR" ]]; then
    plan "platform" "delete platform/ ($(du_h "$PLATFORM_DIR"))"; DESTRUCTIVE+=("platform/ (platform repository checkout)")
    if [[ -d "$PLATFORM_DIR/.git" ]]; then
      w=$(repo_work "$PLATFORM_DIR"); [[ -n "$w" ]] && AT_RISK+=("platform/: $w")
    fi
  else plan "platform" "platform/ — not present"; fi
  mapfile -t PLATFORM_DOCKER < <(platform_docker_leftovers)
  for x in "${PLATFORM_DOCKER[@]}"; do plan "platform" "docker $x"; done
  ui_note "Only the local checkout: the GitHub repository and its packages (ghcr.io CI and platform images) stay." \
    "Deleting the repository on GitHub keeps its packages too: delete them as well, or link them to the new repository (./new-platform.sh shows how)."
fi
[[ -n "${T[workspace]:-}" ]] && plan "workspace" "$( [[ -d $VSCODE_DIR ]] && echo "delete generated .vscode/ files" || echo ".vscode/ — not present")"
if [[ -n "${T[config]:-}" ]]; then
  plan "config" "delete .env and docker-compose.yml"
  [[ -f "$ENV_FILE" ]] && DESTRUCTIVE+=(".env (your secrets$([[ -z ${T[state]:-} ]] && echo "; a copy stays in .state/backups"))")
fi
if [[ -n "${T[untracked]:-}" ]]; then
  if (( ${#UNTRACKED_ALL[@]} )); then
    plan "untracked" "delete ${#UNTRACKED_ALL[@]} path(s) git doesn't track: $(printf '%s ' "${UNTRACKED_ALL[@]:0:6}")$( (( ${#UNTRACKED_ALL[@]} > 6 )) && echo "…")"
    DESTRUCTIVE+=("${#UNTRACKED_ALL[@]} untracked/ignored path(s) of this repository")
    (( ${#UNTRACKED_WORK[@]} )) && AT_RISK+=("this repository: ${#UNTRACKED_WORK[@]} file(s) not in git: $(printf '%s ' "${UNTRACKED_WORK[@]:0:6}")$( (( ${#UNTRACKED_WORK[@]} > 6 )) && echo "…")")
  else plan "untracked" "nothing outside git"; fi
fi
[[ -n "${T[state]:-}" ]] && plan "state" "$( [[ -d $STATE_DIR ]] && echo "delete .state/ ($(du_h "$STATE_DIR"))" || echo ".state/ — not present")"
[[ -n "${T[logs]:-}" ]] && plan "logs" "delete logs/ (this run's log included)"

if (( ${#AT_RISK[@]} )); then
  ui_warn "Work that exists ONLY on this machine would be lost (commit and push it first to keep it):"
  for d in "${AT_RISK[@]}"; do ui_note "• $d"; done
fi

if [[ "$DRY_RUN" == true ]]; then ui_info "Dry run — nothing changed."; exit 0; fi

if [[ "$ASSUME_YES" != true ]]; then ui_confirm "Continue?" || { ui_info "Nothing changed."; exit 0; }; fi
if (( ${#DESTRUCTIVE[@]} )) && [[ "$FORCE" != true ]]; then
  ui_warn "This permanently deletes:"
  for d in "${DESTRUCTIVE[@]}"; do ui_note "• $d"; done
  ui_confirm_typed "Delete this data?" "DELETE" || { ui_info "Cancelled — nothing changed."; exit 0; }
fi
# Work that exists only here: its own confirmation, even with -y.
if (( ${#AT_RISK[@]} )) && [[ "$FORCE" != true ]]; then
  ui_confirm_typed "Delete it anyway?" "DELETE MY WORK" || { ui_info "Cancelled — nothing changed."; exit 0; }
fi

# --- execute -------------------------------------------------------------------------
ui_section "Removing"
IMAGES=""
if [[ "$HAVE_DOCKER" == true ]]; then
  if [[ -n "${T[images]:-}" ]]; then
    IMAGES=$( { dk ps -a --filter "label=com.docker.compose.project=$COMPOSE_PROJECT_NAME" --format '{{.Image}}'
                [[ -f "$COMPOSE_FILE" ]] && dc config --images 2>/dev/null; } | sort -u)
  fi
  if [[ -n "${T[containers]:-}" ]]; then
    if [[ -z "$CONTAINERS" ]]; then ui_ok "No containers to remove"
    elif [[ -f "$COMPOSE_FILE" ]]; then
      ui_run "Removing containers and network" -- dc down --remove-orphans || ui_error "docker compose down failed."
    else
      _rm_by_label() {
        local ids; ids=$(project_containers)
        [[ -n "$ids" ]] && dk rm -f $ids
        dk network ls -q --filter "label=com.docker.compose.project=$COMPOSE_PROJECT_NAME" | xargs -r "${DOCKER[@]}" network rm
      }
      ui_run "Removing containers and network" -- _rm_by_label || ui_error "Removing the containers failed."
    fi
  fi
  for k in "${SEL_VOLUMES[@]}"; do
    full="${COMPOSE_PROJECT_NAME}_${VOLUME_NAME[$k]}"
    if dk volume inspect "$full" >/dev/null 2>&1; then
      ui_run "Deleting volume $full" -- dk volume rm "$full" || ui_error "Couldn't delete $full (still in use?)."
    else
      ui_ok "Volume $full already gone"
    fi
  done
  if [[ -n "${T[images]:-}" ]]; then
    if [[ -z "$IMAGES" ]]; then ui_ok "No project images found"; fi
    for img in $IMAGES; do
      if dk image inspect "$img" >/dev/null 2>&1; then
        ui_run --quiet-fail "Removing image $img" -- dk image rm "$img" || ui_warn "Image $img not removed (used by another container?)."
      fi
    done
  fi
  if [[ -n "${T[prune]:-}" ]]; then
    ui_run "Pruning dangling images" -- dk image prune -f
    ui_run "Pruning unused networks" -- dk network prune -f
    ui_run "Pruning the build cache" -- dk builder prune -f
  fi
fi

remove_path() {
  # remove_path PATH LABEL — falls back to sudo for files created by the
  # container user (uid 1000) when that isn't you.
  local p="$1" label="$2"
  if [[ ! -e "$p" && ! -L "$p" ]]; then ui_ok "$label already gone"; return 0; fi
  if ui_run --quiet-fail "Deleting $label" -- rm -rf -- "$p"; then return 0; fi
  ui_warn "Some files in $label belong to another user — retrying with sudo."
  sudo_prime "delete $label"
  ui_run "Deleting $label (sudo)" -- "${SUDO[@]}" rm -rf -- "$p" || ui_error "Couldn't delete $label."
}

[[ -n "${T[bench]:-}" ]] && remove_path "$BENCH_DIR" "frappe-bench/"
if [[ -n "${T[platform]:-}" ]]; then
  remove_path "$PLATFORM_DIR" "platform/"
  for x in "${PLATFORM_DOCKER[@]}"; do
    kind="${x%% *}"; name="${x#* }"
    ui_run --quiet-fail "Removing $kind $name" -- dk "$kind" rm "$name" || ui_warn "$kind $name not removed (in use?)."
  done
fi
if [[ -n "${T[workspace]:-}" ]]; then
  for f in dev.code-workspace settings.json extensions.json; do
    [[ -e "$VSCODE_DIR/$f" ]] && rm -f "$VSCODE_DIR/$f" && ui_ok "Deleted .vscode/$f"
  done
  rm -f "$VSCODE_DIR"/*.bak 2>/dev/null
  rmdir "$VSCODE_DIR" 2>/dev/null && ui_ok "Removed the empty .vscode/"
  [[ -d "$VSCODE_DIR" ]] && ui_note ".vscode/ kept: it contains files that weren't generated."
fi
if [[ -n "${T[config]:-}" ]]; then
  for f in "$ENV_FILE" "$COMPOSE_FILE"; do
    if [[ -e "$f" ]]; then rm -f "$f" && ui_ok "Deleted ${f#"$REPO_ROOT"/}"; else ui_ok "${f#"$REPO_ROOT"/} already gone"; fi
  done
fi
if [[ -n "${T[untracked]:-}" ]]; then
  for f in "${UNTRACKED_ALL[@]}"; do remove_path "$REPO_ROOT/${f%/}" "$f"; done
  # With --workspace too, whatever is left in .vscode/ goes as well.
  [[ -n "${T[workspace]:-}" && -d "$VSCODE_DIR" ]] && remove_path "$VSCODE_DIR" ".vscode/"
fi
# State and logs last: this script uses both while it runs.
if [[ -n "${T[state]:-}" ]]; then
  [[ -n "$UI_LAST_OUTPUT" ]] && rm -f "$UI_LAST_OUTPUT"; UI_LAST_OUTPUT=""
  if [[ -d "$STATE_DIR" ]]; then rm -rf "$STATE_DIR" && ui_ok "Deleted .state/"; else ui_ok ".state/ already gone"; fi
fi
if [[ -n "${T[logs]:-}" ]]; then
  if [[ -d "$LOG_DIR" ]]; then
    rm -rf "$LOG_DIR"; LOG_FILE=""; LOG_FILE_REL=""
    ui_ok "Deleted logs/ (this run's log included)"
  else ui_ok "logs/ already gone"; fi
fi

UI_STEP_TOTAL=0
ui_section "Done"
if [[ -n "${T[config]:-}" ]]; then ui_info "Start again with ./setup.sh"
elif [[ -n "${T[containers]:-}" || -n "${T[bench]:-}" ]]; then ui_info "Rebuild with ./initialize.sh"; fi
