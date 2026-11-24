#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# bootstrap/lib/scaffold.sh — shared by new-platform.sh and new-app.sh: render
# a template tree, resolve the versions a new repository pins, create the
# repository on GitHub and apply its settings, write the licence.
# Sourced after common.sh; performs no work on import.
# -----------------------------------------------------------------------------

# scaffold_render_tree SRC DST KEY=VALUE... — renders every file under SRC into
# DST at the same relative path, dropping a trailing ".template".
scaffold_render_tree() {
  local src="$1" dst="$2"; shift 2
  local f rel n=0
  while IFS= read -r -d '' f; do
    rel="${f#"$src"/}"; rel="${rel%.template}"
    render "$f" "$dst/$rel" -- "$@" || return 1
    n=$((n + 1))
  done < <(find "$src" -type f -print0 | sort -z)
  log_line "rendered $n file(s) from ${src#"$REPO_ROOT"/} into $dst"
}

# --- version resolution (network) ----------------------------------------------
# Each prints the value; resolve_into FILE KEY FUNC ARGS... appends KEY=VALUE.

# latest GitHub release tag of OWNER/REPO, PREFIX removed (default "v")
resolve_gh_release() {
  local repo="$1" prefix="${2-v}" tag
  tag=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$repo/releases/latest") || return 1
  tag="${tag##*/tag/}"
  [[ -n "$tag" && "$tag" != http* ]] || return 1
  printf '%s' "${tag#"$prefix"}"
}

# newest stable semver tag (vX.Y.Z) of a git repository, without the "v"
resolve_git_tag() {
  git ls-remote --tags --refs "$1" 2>/dev/null | awk -F/ '{print $NF}' \
    | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' | sed 's/^v//' | sort -V | tail -n 1 | grep .
}

# latest version on PyPI / npm
resolve_pypi() { curl -fsSL "https://pypi.org/pypi/$1/json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["info"]["version"], end="")'; }
resolve_npm() { curl -fsSL "https://registry.npmjs.org/$1/latest" | python3 -c 'import json,sys; print(json.load(sys.stdin)["version"], end="")'; }

# newest Docker Hub tag of IMAGE matching REGEX (e.g. ^[0-9]+\.[0-9]+$)
resolve_hub_tag() {
  curl -fsSL "https://hub.docker.com/v2/repositories/$1/tags?page_size=100&ordering=last_updated" \
    | python3 -c '
import json, re, sys
pat = re.compile(sys.argv[1])
tags = [t["name"] for t in json.load(sys.stdin)["results"] if pat.match(t["name"])]
key = lambda v: [int(p) for p in re.findall(r"\d+", v)]
print(max(tags, key=key), end="") if tags else sys.exit(1)' "$2"
}

# IMAGE:TAG → docker.io/IMAGE:TAG@sha256:… (multi-arch index digest)
resolve_digest() {
  local ref="$1" digest
  digest=$(docker buildx imagetools inspect "$ref" --format '{{json .Manifest.Digest}}' 2>/dev/null | tr -d '"') || return 1
  [[ "$digest" == sha256:* ]] || return 1
  [[ "$ref" == */*/* || "$ref" == ghcr.io/* ]] || ref="docker.io/$ref"
  printf '%s@%s' "$ref" "$digest"
}

# commit SHA a tag of a git repository points to (annotated tags dereferenced)
resolve_tag_commit() {
  local out
  out=$(git ls-remote "$1" "refs/tags/$2" "refs/tags/$2^{}") || return 1
  awk -v t="refs/tags/$2^{}" '$2 == t {print $1; f=1} END {exit !f}' <<< "$out" \
    || awk 'NR == 1 {print $1}' <<< "$out" | grep -E '^[0-9a-f]{40}$'
}

# resolve_into FILE KEY FUNC ARGS... — runs FUNC and appends KEY='value' to FILE.
resolve_into() {
  local file="$1" key="$2" value; shift 2
  value=$("$@") || { echo "couldn't resolve $key ($*)" >&2; return 1; }
  [[ -n "$value" ]] || { echo "empty value for $key ($*)" >&2; return 1; }
  printf "%s='%s'\n" "$key" "$value" >> "$file"
  echo "$key=$value"
}

# --- GitHub ---------------------------------------------------------------------
gh_logged_in() { gh api user --jq .login >/dev/null 2>&1; }
gh_repo_exists() { gh api "repos/$1" --silent >/dev/null 2>&1; }
gh_owner_is_org() { [[ "$(gh api "users/$1" --jq .type 2>/dev/null)" == Organization ]]; }
# owner from a git prefix like git@github.com:my-org or https://github.com/my-org
owner_from_prefix() { [[ "$1" =~ github\.com[:/]([^/]+)$ ]] && printf '%s' "${BASH_REMATCH[1]}"; }
valid_gh_name() { [[ "$1" =~ ^[A-Za-z0-9]([A-Za-z0-9._-]{0,98})$ ]]; }

# gh_setting LABEL -- gh api ARGS... : applies one repository setting; a refusal
# (plan or permissions) becomes a warning, never a failure (decision 6b).
gh_setting() {
  local label="$1"; shift; [[ "${1:-}" == "--" ]] && shift
  if ui_run --quiet-fail "$label" -- "$@"; then return 0; fi
  ui_warn "$label: not applied (GitHub plan or permissions?) — see the log; set it by hand if your plan allows."
  return 0
}

# gh_apply_repo_settings OWNER/REPO REQUIRED_CHECKS... — rulesets on main
# (DEL-REPO-005), private vulnerability reporting, staging/production
# environments with the current user as required reviewer (guide 503).
gh_apply_repo_settings() {
  local repo="$1"; shift
  local checks=("$@") me_id json c sep=""
  me_id=$(gh api user --jq .id)
  json='{"name":"main","target":"branch","enforcement":"active",'
  json+='"conditions":{"ref_name":{"include":["~DEFAULT_BRANCH"],"exclude":[]}},"rules":['
  json+='{"type":"deletion"},{"type":"non_fast_forward"},'
  json+='{"type":"pull_request","parameters":{"required_approving_review_count":1,'
  json+='"dismiss_stale_reviews_on_push":true,"require_code_owner_review":false,'
  json+='"require_last_push_approval":false,"required_review_thread_resolution":false}}'
  if (( ${#checks[@]} )); then
    json+=',{"type":"required_status_checks","parameters":{"strict_required_status_checks_policy":false,"required_status_checks":['
    for c in "${checks[@]}"; do json+="$sep{\"context\":\"$c\"}"; sep=","; done
    json+=']}}'
  fi
  json+=']}'
  _gh_json() { local method="$1" path="$2" body="$3"; printf '%s' "$body" | gh api -X "$method" "$path" --input - >/dev/null; }
  # Create the ruleset, or update it when a run before this one created it.
  local rs_id
  rs_id=$(gh api "repos/$repo/rulesets" --jq '.[] | select(.name == "main") | .id' 2>/dev/null | head -n 1)
  if [[ -n "$rs_id" ]]; then
    gh_setting "Ruleset on main (updated)" -- _gh_json PUT "repos/$repo/rulesets/$rs_id" "$json"
  else
    gh_setting "Ruleset on main (pull requests, review, green CI, no force-push)" -- _gh_json POST "repos/$repo/rulesets" "$json"
  fi
  # Other repositories of the owner may call these workflows. GitHub only has
  # this setting for private/internal repositories: public ones are open to all.
  local visibility owner="${repo%%/*}" access=user
  visibility=$(gh api "repos/$repo" --jq .visibility 2>/dev/null)
  if [[ "$visibility" == public ]]; then
    ui_ok "Actions: public repository, every repository can use its workflows"
  else
    gh_owner_is_org "$owner" && access=organization
    gh_setting "Actions: other repositories of $owner may use these workflows" -- \
      gh api -X PUT "repos/$repo/actions/permissions/access" -f access_level="$access" --silent
  fi
  gh_setting "Private vulnerability reporting" -- gh api -X PUT "repos/$repo/private-vulnerability-reporting" --silent
  local env
  for env in staging production; do
    gh_setting "Environment $env (required reviewer: you)" -- _gh_json PUT "repos/$repo/environments/$env" \
      "{\"reviewers\":[{\"type\":\"User\",\"id\":$me_id}],\"deployment_branch_policy\":null}"
  done
}

# --- licence --------------------------------------------------------------------
# shellcheck disable=SC2034  # used by the scripts that source this file
LICENSE_CHOICES=(
  "proprietary::Proprietary::All rights reserved; no licence granted"
  "mit::MIT::permissive, like Frappe"
  "apache-2.0::Apache 2.0::permissive, with a patent grant"
  "agpl-3.0::AGPL 3.0::copyleft, also over a network"
  "gpl-3.0::GPL 3.0::copyleft"
)
license_name() {
  case "$1" in
    proprietary) printf 'Proprietary (all rights reserved)' ;; mit) printf 'MIT' ;;
    apache-2.0) printf 'Apache-2.0' ;; agpl-3.0) printf 'AGPL-3.0' ;; gpl-3.0) printf 'GPL-3.0' ;;
  esac
}
# license_write KEY HOLDER YEAR FILE — text from GitHub's licence API (gh).
license_write() {
  local key="$1" holder="$2" year="$3" file="$4"
  if [[ "$key" == proprietary ]]; then
    printf 'Copyright (c) %s %s\n\nAll rights reserved. No licence is granted to use, copy, modify or\ndistribute this software without the written permission of the copyright\nholder.\n' "$year" "$holder" > "$file"
    return 0
  fi
  gh api "licenses/$key" --jq .body > "$file.tmp" || { rm -f "$file.tmp"; return 1; }
  python3 - "$file.tmp" "$file" "$year" "$holder" <<'PY'
import sys
src, dst, year, holder = sys.argv[1:]
text = open(src, encoding="utf-8").read()
for a, b in (("[year]", year), ("[yyyy]", year), ("[fullname]", holder),
             ("[name of copyright owner]", holder)):
    text = text.replace(a, b)
open(dst, "w", encoding="utf-8").write(text if text.endswith("\n") else text + "\n")
PY
  rm -f "$file.tmp"
}

# guide_version — version of the architecture guide in this repository
guide_version() { sed -n 's/.*\*\*Guide version:\*\* \([0-9.]*\).*/\1/p' "$REPO_ROOT/architecture/README.md" | head -n 1; }
