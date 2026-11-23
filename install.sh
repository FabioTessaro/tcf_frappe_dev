#!/usr/bin/env bash
# install.sh — prepare THIS HOST (the Ubuntu server) for frappe-dev.
#
# Usage: ./install.sh [options]
#
# Components (choose in the menu, or with --components):
#   base     apt prerequisites (curl, git, python3, openssl, pre-commit, …),
#            the en_US.UTF-8 locale, gitleaks and lychee (latest releases, in
#            /usr/local/bin) and this repository's git hooks (pre-commit:
#            secret scanning, Markdown and Python checks, commit messages)
#   docker   Docker Engine + Compose plugin, enabled at boot, your user in
#            the "docker" group
#   git      git identity (user.name / user.email), an ed25519 SSH key and a
#            check that your git server accepts it
#   ftp      vsftpd FTP server for one system user (settings in
#            bootstrap/templates/ftp.conf)
#
# Every component checks the current state first and only fixes what is
# missing or wrong, so running install.sh again is always safe.
#
# Options:
#   --components LIST   comma-separated components to run, e.g. base,docker,git
#                       (skips the menu)
#   --all               all components (same as --components base,docker,git,ftp)
#   --git-name NAME     git user.name   (otherwise asked if not configured)
#   --git-email EMAIL   git user.email  (otherwise asked if not configured)
#   --git-host HOST     verify the SSH key against HOST: github.com, gitlab.com,
#                       bitbucket.org, any other ssh host, or "skip"
#   --ssh-passphrase    generate the SSH key WITH a passphrase (asked by
#                       ssh-keygen). Note: custom-app clones inside the
#                       container need a key without passphrase.
#   --no-ssh-passphrase generate the SSH key without a passphrase
#   --ftp-user USER     system user allowed to log in over FTP
#   --trace             also write a bash execution trace into the log
#   -h, --help          show this help
#
# Log: logs/install-<timestamp>.log  (logs/install-latest.log → newest)
# Next step: ./setup.sh
set -o pipefail
# shellcheck source=bootstrap/lib/common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/bootstrap/lib/common.sh"
# shellcheck source=bootstrap/lib/tools.sh
source "$LIB_DIR/tools.sh"

ALL_COMPONENTS=(base docker git ftp)
# Binary tools the git hooks of this repository need on the host.
HOST_TOOLS=(gitleaks lychee)
COMPONENTS=""
GIT_NAME=""; GIT_EMAIL=""; GIT_HOST=""; SSH_PASSPHRASE=""; FTP_USER=""

for a in "$@"; do [[ "$a" == -h || "$a" == --help ]] && { usage_from_header "$0"; exit 0; }; done
script_init install "$@"
set -- "${SCRIPT_ARGS[@]}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --components) COMPONENTS="${2:-}"; shift ;;
    --components=*) COMPONENTS="${1#*=}" ;;
    --all) COMPONENTS="$(join , "${ALL_COMPONENTS[@]}")" ;;
    --git-name) GIT_NAME="${2:-}"; shift ;;
    --git-email) GIT_EMAIL="${2:-}"; shift ;;
    --git-host) GIT_HOST="${2:-}"; shift ;;
    --ssh-passphrase) SSH_PASSPHRASE=yes ;;
    --no-ssh-passphrase) SSH_PASSPHRASE=no ;;
    --ftp-user) FTP_USER="${2:-}"; shift ;;
    *) ui_die "Unknown option: $1" "See ./install.sh --help" ;;
  esac
  shift
done

ui_banner "frappe-dev · install" "host preparation"

if [[ $EUID -eq 0 ]]; then
  ui_die "Run install.sh as your normal user, not as root (it uses sudo where needed)." \
    "The containers mount YOUR ~/.ssh and ~/.gitconfig, so the setup must belong to you."
fi
[[ -r /etc/os-release ]] && . /etc/os-release
if [[ "${ID:-}" != ubuntu && "${ID:-}" != debian && "${ID_LIKE:-}" != *debian* ]]; then
  ui_die "Unsupported OS: ${PRETTY_NAME:-unknown}. install.sh supports Ubuntu/Debian."
fi

# --- component status (shown in the menu) ------------------------------------
status_base() {
  local p missing=0
  for p in ca-certificates curl git python3 openssl locales pre-commit iproute2; do
    [[ "$(dpkg-query -W -f='${db:Status-Status}' "$p" 2>/dev/null)" == installed ]] || missing=$((missing + 1))
  done
  for p in "${HOST_TOOLS[@]}"; do command -v "$p" >/dev/null 2>&1 || missing=$((missing + 1)); done
  [[ -f "$REPO_ROOT/.git/hooks/commit-msg" ]] || missing=$((missing + 1))
  if (( missing )); then printf '%d item(s) missing' "$missing"; else printf 'installed'; fi
}
status_docker() {
  if ! command -v docker >/dev/null 2>&1; then printf 'not installed'
  elif ! id -nG | grep -qw docker; then printf 'installed, user not in docker group'
  else printf 'installed'; fi
}
status_git() {
  local n e
  n=$(git config --global user.name 2>/dev/null); e=$(git config --global user.email 2>/dev/null)
  if [[ -z "$n" || -z "$e" ]]; then printf 'identity not set'
  elif [[ ! -f "$HOME/.ssh/id_ed25519" ]]; then printf '%s <%s>, no SSH key' "$n" "$e"
  else printf '%s <%s>, key present' "$n" "$e"; fi
}
status_ftp() {
  if [[ "$(dpkg-query -W -f='${db:Status-Status}' vsftpd 2>/dev/null)" == installed ]]; then
    printf 'vsftpd installed'; else printf 'not installed'; fi
}

# --- choose components ------------------------------------------------------------
if [[ -z "$COMPONENTS" ]]; then
  ui_checklist --min 1 --on "base docker git" "Which components should be installed or checked?" \
    "base::Base packages & locale::$(status_base)" \
    "docker::Docker Engine & Compose::$(status_docker)" \
    "git::Git identity & SSH key::$(status_git)" \
    "ftp::FTP server (vsftpd)::$(status_ftp)" || exit 1
  SELECTED=("${UI_SELECTED[@]}")
else
  IFS=',' read -r -a SELECTED <<< "$COMPONENTS"
  for c in "${SELECTED[@]}"; do
    contains "$c" "${ALL_COMPONENTS[@]}" || ui_die "Unknown component '$c'." "Valid: ${ALL_COMPONENTS[*]}"
  done
fi
UI_STEP_TOTAL=${#SELECTED[@]}
log_line "components: ${SELECTED[*]}"

sudo_prime "install system packages and configure services"

APT_UPDATED=false
apt_install() {
  local missing=() p
  for p in "$@"; do
    [[ "$(dpkg-query -W -f='${db:Status-Status}' "$p" 2>/dev/null)" == installed ]] || missing+=("$p")
  done
  if (( ${#missing[@]} == 0 )); then ui_ok "Packages already installed: $*"; return 0; fi
  if [[ "$APT_UPDATED" == false ]]; then
    ui_run "Updating the apt package index" -- "${SUDO[@]}" apt-get update || return 1
    APT_UPDATED=true
  fi
  ui_run "Installing ${missing[*]}" -- "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
}

# =============================================================================
component_base() {
  ui_section "Base packages & locale"
  apt_install ca-certificates curl git python3 openssl locales pre-commit iproute2 \
    || ui_die "Couldn't install the base packages."

  if locale -a 2>/dev/null | grep -qiE '^en_US\.utf-?8$'; then
    ui_ok "Locale en_US.UTF-8 is available"
  else
    ui_run "Generating the en_US.UTF-8 locale" -- "${SUDO[@]}" locale-gen en_US.UTF-8 \
      || ui_die "locale-gen failed."
  fi
  local current
  current=$(sed -n 's/^LANG=//p' /etc/default/locale 2>/dev/null | tr -d '"')
  if [[ "$current" == en_US.UTF-8 ]]; then
    ui_ok "System default locale is en_US.UTF-8"
  else
    ui_run "Setting the system default locale to en_US.UTF-8 (was: ${current:-unset})" -- \
      "${SUDO[@]}" update-locale LANG=en_US.UTF-8 || ui_die "update-locale failed."
    ui_note "Applies to new login sessions."
  fi

  # gitleaks (secret scanning) and lychee (link checking) are called by the git
  # hooks of this repository; the frappe container gets its own copies.
  local t tmp
  for t in "${HOST_TOOLS[@]}"; do
    if command -v "$t" >/dev/null 2>&1; then
      ui_ok "$t is installed ($("$t" --version 2>/dev/null | head -n 1))"
      continue
    fi
    tmp=$(mktemp -d)
    ui_run "Downloading $t (latest release)" -- tool_fetch "$t" "$tmp" \
      && ui_run "Installing $t into /usr/local/bin" -- "${SUDO[@]}" install -m 755 "$tmp/$t" "/usr/local/bin/$t" \
      || { rm -rf "$tmp"; ui_die "Couldn't install $t."; }
    rm -rf "$tmp"
  done

  # Git hooks of this repository (types from .pre-commit-config.yaml:
  # pre-commit and commit-msg). Hook environments are built on first use.
  if [[ -f "$REPO_ROOT/.git/hooks/pre-commit" && -f "$REPO_ROOT/.git/hooks/commit-msg" ]]; then
    ui_ok "Git hooks are installed in this repository"
  else
    _install_hooks() { cd "$REPO_ROOT" && pre-commit install; }
    ui_run "Installing the git hooks of this repository" -- _install_hooks \
      || ui_die "pre-commit install failed."
  fi
}

# =============================================================================
component_docker() {
  ui_section "Docker Engine & Compose"
  if command -v docker >/dev/null 2>&1; then
    ui_ok "Docker is installed ($(docker --version 2>/dev/null | sed 's/,.*//'))"
  else
    local script="$STATE_TMP_DIR/get-docker.sh"
    ui_run "Downloading the official Docker install script" -- curl -fsSL -o "$script" https://get.docker.com \
      || ui_die "Couldn't download https://get.docker.com"
    ui_run "Installing Docker Engine (this takes a few minutes)" -- "${SUDO[@]}" sh "$script" \
      || ui_die "Docker installation failed."
  fi

  if "${SUDO[@]}" docker compose version >/dev/null 2>&1; then
    ui_ok "Docker Compose plugin is installed ($("${SUDO[@]}" docker compose version --short 2>/dev/null))"
  else
    apt_install docker-compose-plugin || ui_die "Couldn't install the Docker Compose plugin."
  fi

  local unit
  for unit in docker.service containerd.service; do
    if systemctl is-enabled --quiet "$unit" 2>/dev/null; then
      ui_ok "$unit starts at boot"
    else
      ui_run "Enabling $unit at boot" -- "${SUDO[@]}" systemctl enable "$unit" || ui_warn "Couldn't enable $unit at boot."
    fi
  done
  if systemctl is-active --quiet docker 2>/dev/null; then
    ui_ok "Docker daemon is running"
  else
    ui_run "Starting the Docker daemon" -- "${SUDO[@]}" systemctl start docker || ui_die "Docker didn't start (see: journalctl -u docker)."
  fi

  local me; me=$(id -un)
  if id -nG "$me" | grep -qw docker; then
    ui_ok "User $me is in the docker group"
  elif getent group docker | cut -d: -f4 | tr ',' '\n' | grep -qx "$me"; then
    ui_ok "User $me was added to the docker group"
    ui_warn "Log out and back in (or run 'newgrp docker') so docker works without sudo. Until then the scripts use sudo."
  else
    ui_run "Adding $me to the docker group" -- "${SUDO[@]}" usermod -aG docker "$me" || ui_die "usermod failed."
    ui_warn "Log out and back in (or run 'newgrp docker') so docker works without sudo. Until then the scripts use sudo."
  fi
  if [[ "$(id -u)" != 1000 ]]; then
    ui_warn "Your uid is $(id -u), the container user's is 1000: files created in the container (frappe-bench/) will belong to uid 1000 and ~/.ssh may not be readable inside it."
  fi
}

# =============================================================================
ssh_check_host() {
  local host="$1" out
  out=$(ssh -T -o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new "git@$host" 2>&1)
  log_line "ssh -T git@$host: $out"
  grep -qiE "successfully authenticated|welcome to gitlab|logged in as|authenticated (via|as)|you've successfully" <<< "$out"
}

component_git() {
  ui_section "Git identity & SSH key"
  local name email
  name=$(git config --global user.name 2>/dev/null); email=$(git config --global user.email 2>/dev/null)
  if [[ -n "$GIT_NAME" || -n "$GIT_EMAIL" ]]; then
    [[ -n "$GIT_NAME" ]] && name="$GIT_NAME"
    [[ -n "$GIT_EMAIL" ]] && email="$GIT_EMAIL"
  elif [[ -n "$name" && -n "$email" ]]; then
    ui_select "Git identity is \"$name <$email>\"" \
      "keep::Keep it" "change::Change it" || exit 1
    if [[ "$UI_VALUE" == change ]]; then name=""; email=""; fi
  fi
  if [[ -z "$name" ]]; then ui_input "Git user name (user.name)"; name="$UI_VALUE"; fi
  if [[ -z "$email" ]]; then
    ui_input --validate _valid_email --error "doesn't look like an e-mail address" "Git e-mail (user.email)"
    email="$UI_VALUE"
  fi
  [[ "$(git config --global user.name)" == "$name" ]] || git config --global user.name "$name"
  [[ "$(git config --global user.email)" == "$email" ]] || git config --global user.email "$email"
  ui_ok "Git identity: $name <$email>"
  [[ -f "$HOME/.gitconfig" ]] && ui_ok "$HOME/.gitconfig exists (mounted read-only into the container)"

  # SSH key ---------------------------------------------------------------------
  local key="$HOME/.ssh/id_ed25519"
  mkdir -p "$HOME/.ssh"
  if [[ -f "$key" ]] && ssh-keygen -l -f "$key" >/dev/null 2>&1; then
    ui_ok "SSH key found: ~/.ssh/id_ed25519 ($(ssh-keygen -l -f "$key" | awk '{print $2}'))"
    if ! ssh-keygen -y -P "" -f "$key" >/dev/null 2>&1; then
      ui_warn "The SSH key has a passphrase: custom-app clones inside the container (unattended) will fail with it."
    fi
  else
    if [[ -f "$key" ]]; then
      local bad; bad="$key.invalid-$(date +%Y%m%d%H%M%S)"
      mv "$key" "$bad"; [[ -f "$key.pub" ]] && mv "$key.pub" "$bad.pub"
      ui_warn "$key was not a valid key — moved to $bad."
    fi
    if [[ -z "$SSH_PASSPHRASE" ]]; then
      ui_select "No SSH key yet — how should it be generated?" \
        "no::Without a passphrase::needed for unattended custom-app clones in the container" \
        "yes::With a passphrase::more secure; clones inside the container will fail" || exit 1
      SSH_PASSPHRASE="$UI_VALUE"
    fi
    if [[ "$SSH_PASSPHRASE" == yes ]]; then
      ui_exec "Generating an ed25519 SSH key" -- ssh-keygen -t ed25519 -C "$email" -f "$key" || ui_die "ssh-keygen failed."
    else
      ui_run "Generating an ed25519 SSH key (no passphrase)" -- ssh-keygen -q -t ed25519 -C "$email" -f "$key" -N "" \
        || ui_die "ssh-keygen failed."
    fi
  fi
  local want path
  for path in "$HOME/.ssh:700" "$key:600" "$key.pub:644"; do
    want="${path##*:}"; path="${path%:*}"
    [[ -e "$path" ]] || continue
    if [[ "$(stat -c %a "$path")" != "$want" ]]; then chmod "$want" "$path"; ui_ok "Fixed permissions of ${path/#$HOME/\~} → $want"; fi
  done

  # Verify against the git server ----------------------------------------------------
  local host="$GIT_HOST"
  if [[ -z "$host" ]]; then
    ui_select "Check that your git server accepts this key?" \
      "github.com::GitHub (github.com)" "gitlab.com::GitLab (gitlab.com)" \
      "bitbucket.org::Bitbucket (bitbucket.org)" "other::Another SSH git server…" \
      "skip::Skip the check" || exit 1
    host="$UI_VALUE"
    if [[ "$host" == other ]]; then
      ui_input --validate valid_hostname --error "enter a host name like git.example.com" "Git server host name"
      host="$UI_VALUE"
    fi
  fi
  if [[ "$host" == skip ]]; then ui_note "SSH key check skipped."; return 0; fi

  while ! ui_run --quiet-fail "Testing SSH authentication with $host" -- ssh_check_host "$host"; do
    if [[ "$UI_TTY_IN" != true ]]; then ui_die "$host doesn't accept the SSH key yet." "Add ~/.ssh/id_ed25519.pub to your account and re-run."; fi
    local add_url="your account's SSH keys page"
    case "$host" in
      github.com) add_url="https://github.com/settings/ssh/new  (Key type: Authentication Key)" ;;
      gitlab.com) add_url="https://gitlab.com/-/user_settings/ssh_keys" ;;
      bitbucket.org) add_url="https://bitbucket.org/account/settings/ssh-keys/" ;;
    esac
    ui_info "Add this public key to $host — $add_url"
    ui_box "$(cat "$key.pub")"
    ui_select "Then:" "retry::I've added it — test again" "skip::Skip the check for now" || exit 1
    if [[ "$UI_VALUE" == skip ]]; then ui_warn "SSH key not verified with $host."; return 0; fi
  done
  ui_ok "$host accepts your SSH key"
}
_valid_user() { [[ "$1" =~ ^[a-z_][a-z0-9_.-]*$ ]]; }
_valid_email() { [[ "$1" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]]; }

# =============================================================================
component_ftp() {
  ui_section "FTP server (vsftpd)"
  local user="$FTP_USER" me; me=$(id -un)
  if [[ -z "$user" ]]; then
    local current=""
    [[ -f /etc/vsftpd.userlist ]] && current=$(grep -vE '^\s*(#|$)' /etc/vsftpd.userlist 2>/dev/null | head -1)
    local items=("$me::$me (you)")
    [[ -n "$current" && "$current" != "$me" ]] && items+=("$current::$current (currently configured)")
    items+=("=other::Another system user…")
    ui_select "Which system user may log in over FTP?" "${items[@]}" || exit 1
    user="$UI_VALUE"
    if [[ "$user" == "=other" ]]; then ui_input --validate _valid_user --error "not a valid user name" "System user name"; user="$UI_VALUE"; fi
  fi
  id "$user" >/dev/null 2>&1 || ui_die "System user '$user' doesn't exist." "Create it first: sudo adduser $user"

  apt_install vsftpd || ui_die "Couldn't install vsftpd."

  local conf=/etc/vsftpd.conf changed=false line key value
  if [[ -f "$conf" && ! -f "$conf.frappe-dev.orig" ]]; then
    "${SUDO[@]}" cp "$conf" "$conf.frappe-dev.orig"; ui_ok "Backed up the original $conf → $conf.frappe-dev.orig"
  fi
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
    key="${line%%=*}"; value="${line#*=}"
    if "${SUDO[@]}" grep -qxF "$key=$value" "$conf"; then continue; fi
    if "${SUDO[@]}" grep -qE "^[#[:space:]]*$key=" "$conf"; then
      "${SUDO[@]}" sed -i "s|^[#[:space:]]*$key=.*|$key=$value|" "$conf"
    else
      printf '%s=%s\n' "$key" "$value" | "${SUDO[@]}" tee -a "$conf" >/dev/null
    fi
    log_line "vsftpd: $key=$value"; changed=true
  done < "$TEMPLATE_DIR/ftp.conf"
  if [[ "$changed" == true ]]; then ui_ok "Updated $conf from bootstrap/templates/ftp.conf"; else ui_ok "$conf already matches the template"; fi

  local list; list=$(sed -n 's/^userlist_file=//p' "$TEMPLATE_DIR/ftp.conf"); list="${list:-/etc/vsftpd.userlist}"
  if [[ "$(cat "$list" 2>/dev/null)" == "$user" ]]; then
    ui_ok "$list allows: $user"
  else
    printf '%s\n' "$user" | "${SUDO[@]}" tee "$list" >/dev/null; "${SUDO[@]}" chmod 644 "$list"
    ui_ok "$list now allows: $user"; changed=true
  fi

  local pmin pmax
  pmin=$(sed -n 's/^pasv_min_port=//p' "$TEMPLATE_DIR/ftp.conf"); pmax=$(sed -n 's/^pasv_max_port=//p' "$TEMPLATE_DIR/ftp.conf")
  if command -v ufw >/dev/null 2>&1 && "${SUDO[@]}" ufw status 2>/dev/null | grep -q "Status: active"; then
    ui_run "Opening FTP ports in UFW (20-21, $pmin-$pmax)" -- \
      bash -c "${SUDO[*]} ufw allow 20:21/tcp && ${SUDO[*]} ufw allow $pmin:$pmax/tcp" || ui_warn "Couldn't update UFW rules."
  else
    ui_note "UFW not active — if a cloud firewall protects this host, open TCP 21 and $pmin-$pmax."
  fi

  systemctl is-enabled --quiet vsftpd 2>/dev/null || ui_run "Enabling vsftpd at boot" -- "${SUDO[@]}" systemctl enable vsftpd
  if [[ "$changed" == true ]] || ! systemctl is-active --quiet vsftpd; then
    ui_run "Restarting vsftpd" -- "${SUDO[@]}" systemctl restart vsftpd || ui_die "vsftpd didn't start (see: journalctl -u vsftpd)."
  else
    ui_ok "vsftpd is running with the current configuration"
  fi
  ui_ok "FTP ready: user '$user' logs in on port 21 with their system password"
}

# =============================================================================
for c in "${ALL_COMPONENTS[@]}"; do
  contains "$c" "${SELECTED[@]}" && "component_$c"
done

UI_STEP_TOTAL=0
ui_section "Next step"
ui_info "Host ready. Configure the project with:  ./setup.sh"
