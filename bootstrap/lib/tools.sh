#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# bootstrap/lib/tools.sh — download the latest Linux release of a developer
# tool. Shared by install.sh (host) and bootstrap/container/provision.sh
# (frappe container). The caller decides where the binary is installed.
#
#   tool_fetch NAME DIR   download NAME's latest binary to DIR/NAME
#                         NAME: gitleaks | lychee | hadolint | just | trivy | gh
#
# The tools are the ones decided in architecture/50-delivery/504-toolchain.md.
# Versions are not pinned: the development environment follows "latest".
# -----------------------------------------------------------------------------

tools_arch() {
  case "$(uname -m)" in
    x86_64 | amd64) printf 'x86_64' ;;
    aarch64 | arm64) printf 'aarch64' ;;
    *) return 1 ;;
  esac
}

# gh_latest_tag OWNER/REPO — tag of the latest GitHub release (no API token needed).
gh_latest_tag() {
  curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest" \
    | sed 's#.*/tag/##'
}

tool_fetch() {
  local name="$1" dir="$2" arch tag tmp
  arch=$(tools_arch) || { echo "unsupported architecture: $(uname -m)" >&2; return 1; }
  mkdir -p "$dir" || return 1
  tmp=$(mktemp -d) || return 1
  case "$name" in
    gitleaks)
      tag=$(gh_latest_tag gitleaks/gitleaks) || { rm -rf "$tmp"; return 1; }
      local a=x64; [[ "$arch" == aarch64 ]] && a=arm64
      curl -fsSL "https://github.com/gitleaks/gitleaks/releases/download/$tag/gitleaks_${tag#v}_linux_$a.tar.gz" \
        | tar -xz -C "$tmp" gitleaks ;;
    lychee)
      curl -fsSL "https://github.com/lycheeverse/lychee/releases/latest/download/lychee-$arch-unknown-linux-gnu.tar.gz" \
        | tar -xz -C "$tmp" ;;
    hadolint)
      local a=x86_64; [[ "$arch" == aarch64 ]] && a=arm64
      curl -fsSL -o "$tmp/hadolint" "https://github.com/hadolint/hadolint/releases/latest/download/hadolint-linux-$a" ;;
    just)
      curl --proto '=https' --tlsv1.2 -fsSL https://just.systems/install.sh \
        | bash -s -- --to "$tmp" >/dev/null 2>&1 ;;
    trivy)
      curl -fsSL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \
        | sh -s -- -b "$tmp" >/dev/null 2>&1 ;;
    gh)
      tag=$(gh_latest_tag cli/cli) || { rm -rf "$tmp"; return 1; }
      local a=amd64; [[ "$arch" == aarch64 ]] && a=arm64
      curl -fsSL "https://github.com/cli/cli/releases/download/$tag/gh_${tag#v}_linux_$a.tar.gz" \
        | tar -xz -C "$tmp" ;;
    *) echo "unknown tool: $name" >&2; rm -rf "$tmp"; return 1 ;;
  esac
  local bin
  bin=$(find "$tmp" -type f -name "$name" | head -n 1)
  if [[ -z "$bin" ]]; then
    echo "$name: download failed" >&2; rm -rf "$tmp"; return 1
  fi
  chmod 755 "$bin" && mv -f "$bin" "$dir/$name"
  local rc=$?
  rm -rf "$tmp"
  return "$rc"
}
