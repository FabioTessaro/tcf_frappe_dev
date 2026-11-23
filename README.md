# TCF Frappe Development

A Docker Compose development environment for Frappe Framework and custom
Frappe apps on a remote Ubuntu server. You connect to it with VS Code
(Remote-SSH, then **Attach to Running Container**) and run `bench start`
inside the container.

The repository holds the environment and its lifecycle scripts only. Custom
app source code lives in its own repositories; the scripts clone it into
`frappe-bench/apps/`.

## Architecture

The platform architecture is defined by the
**[Platform Architecture Guide](./architecture/README.md)**, the authoritative
source of truth for every app built on this environment. It covers:

- the system and its app kinds (core app, feature apps, public website app) and
  the dependency rules between them
- the domain foundations (Party model, capabilities, classification, settings)
- the contracts between frontend and backend
- the Vue frontend and the Python backend
- security and compliance, testing, delivery (CI/CD and the decided
  toolchain) and operations
- the compliance framework for the targeted norms
- playbooks for common changes

Start with [How to read this guide](./architecture/00-foundations/00-how-to-read.md).
AI agents must follow the rules in the guide's
[Read this first](./architecture/README.md#read-this-first-humans-and-ai-agents)
section. The guide can also be built as a PDF and an EPUB (for Kindle) with
`architecture/book/build.sh`; see
[Book version](./architecture/README.md#book-version-pdf-and-epub).

The scripts here provision the development environment. They don't generate
the application itself.

## Requirements

**Remote host:** Ubuntu or Debian with sudo rights. Everything else
(Docker, git, locale, …) is installed by `./install.sh`. Run the scripts as
your normal user (uid 1000 matches the container's `frappe` user best).

**Your machine:** Visual Studio Code with the **Remote - SSH** and
**Dev Containers** extensions (or the *Remote Development* extension pack).

## Quick start

```bash
git clone https://github.com/FabioTessaro/tcf_frappe_dev.git frappe-dev
cd frappe-dev
./install.sh      # 1. prepare the host: Docker, git identity + SSH key, FTP
./setup.sh        # 2. choose apps, versions, secrets, site and custom apps
./initialize.sh   # 3. build and start everything
```

Then:

1. On the machine you browse from, add the sites to its hosts file:
   `<server-ip>  <site> test.<site> test-minimal.<site>`
2. In VS Code: **Remote-SSH** into the server, then **Dev Containers: Attach
   to Running Container…** and pick `tcf-frappe-dev-frappe-1`.
3. Open `/workspace/.vscode/dev.code-workspace`.
4. In a container terminal: `cd /workspace/frappe-bench && bench start`.
5. Browse to `http://<site>:8000` (user `Administrator`, password
   `ADMIN_PASSWORD` from `.env`).

Every script can be run again at any time. Each one checks the current state
and only does what is missing.

## The scripts

All scripts share the same terminal UI: arrow-key menus, checklists, spinners
with the live output line, colour-coded ✔ / ▲ / ✖ messages and a final
summary of warnings and errors. All of them accept `-h/--help` (full option
list) and `--trace` (adds a bash execution trace to the log).

### `install.sh` — prepare the host

A checklist of components; each one fixes only what is missing or wrong.

| Component | What it ensures |
|---|---|
| `base` | apt prerequisites (curl, git, python3, openssl, pre-commit, …), the `en_US.UTF-8` locale as system default, **gitleaks**, **lychee** and **just** (latest releases, in `/usr/local/bin`) and this repository's git hooks (see [Git hooks](#git-hooks)) |
| `docker` | Docker Engine and the Compose plugin, Docker enabled at boot, your user in the `docker` group |
| `git` | `user.name` / `user.email`, an ed25519 SSH key (with or without passphrase), correct `~/.ssh` permissions, and a check that GitHub / GitLab / Bitbucket / another server accepts the key |
| `ftp` | vsftpd for one system user, configured from `bootstrap/templates/ftp.conf`, UFW rules when UFW is active |

| Option | Meaning |
|---|---|
| `--components base,docker,git,ftp` / `--all` | skip the menu |
| `--git-name`, `--git-email` | git identity without prompting |
| `--git-host HOST` | server to verify the SSH key against, or `skip` |
| `--ssh-passphrase` / `--no-ssh-passphrase` | how a new key is generated. Custom-app clones inside the container need a key **without** passphrase |
| `--ftp-user USER` | FTP user without prompting |

### `setup.sh` — configure the project

Writes `.env` (mode 600) and `docker-compose.yml`. The first run goes
through five sections:

1. **Default apps and versions.** Pick the Frappe version, then the default
   apps (`erpnext`, `hrms`, `raven`, `meet`, `drive`, `insights`, `wiki`).
   Dependencies are added automatically (`hrms` → `erpnext`). Each version is
   picked from the tags and branches of the app's git repository. For apps
   that follow Frappe's numbering, tags of the same major version are shown
   first.
2. **Secrets.** Administrator password, MariaDB root user and password,
   SeaweedFS keys and, only when Meet is selected, the SFU secret and the
   announced address. Typing shows `*` per character and every value is
   asked twice. **Press enter to generate a random value.** Short values or
   values with spaces get a warning you can override; only a single quote
   `'` and line breaks are refused (`.env` can't store them).
3. **Storage and services.** SeaweedFS buckets (pre-filled from
   `bootstrap/templates/buckets.list`; untick or add any) and whether
   MariaDB's port 3306 is published on the host.
4. **Site.** The site name. The test sites are always `test.<site>` (every
   app installed) and `test-minimal.<site>` (Frappe and the core app only);
   both have developer mode and `allow_tests` on (they're meant for Playwright
   and `bench run-tests`). You choose whether the main site has developer
   mode on.
5. **Custom apps.** *Empty shell* (no custom apps: setup.sh writes `.env` and
   exits) or *custom apps*: a git prefix (`git@github.com:my-org`), any
   number of app names, an optional full git URL per app, and the
   mandatory **core app** chosen from that list. Each repository is checked
   with `git ls-remote` using your SSH key.

**On re-runs**, setup.sh shows the current configuration and a menu to edit
single sections. Before saving it lists what changed and what
`./initialize.sh` will have to do about it, compared with the last
successful initialization. The levels are:

- `●` applied automatically
- `▲` initialize.sh asks first
- `✖` needs a rebuild or manual action, for example a different Frappe
  version or a different MariaDB root user

Running containers read `.env` when they start, so setup.sh offers to stop
them first. It never changes `.env` while they run.

| Option | Meaning |
|---|---|
| `--answers FILE` | take answers from a KEY=VALUE file (same keys as `.env`; secrets may be `@generate`). Missing keys are asked, or kept on a re-run. Example: `bootstrap/templates/answers.example.conf` |
| `--section NAME` | edit one section and save: `apps`, `secrets`, `storage`, `site`, `custom` |
| `--show` | print the configuration with secrets masked |
| `-y, --yes` | no final confirmation; stop running containers without asking |

### `initialize.sh` — build and start

Requires `.env`; without it the script stops and tells you to run
`./setup.sh`.

| Step | What happens |
|---|---|
| VS Code Server | Menu: the commit **detected on this host** (the VS Code client that last connected over Remote-SSH, recommended), the **latest stable** for your client's platform, a commit typed by hand, or skip |
| Containers | renders `docker-compose.yml`, pulls images, `docker compose up -d` |
| VS Code Server | downloads the build on the host and copies it into the container (avoids attach hangs) |
| Container tools | apt packages; uv, pre-commit and the developer toolchain of the architecture guide (ruff, mypy, shellcheck, gitleaks, lychee, hadolint, just, trivy, markdownlint-cli2, all latest, in `~/.local/bin`); waits for MariaDB and SeaweedFS, then for ClamAV (only warns if it isn't ready); checks the MariaDB root password |
| Bench | `bench init` with `FRAPPE_VERSION` (external Redis, no Redis in the Procfile) |
| Apps | fetches the default apps at their versions, clones the custom apps |
| Sites | creates `<site>`, `test.<site>` and `test-minimal.<site>`, installs the apps in order (dependencies, then core app, then feature apps; on `test-minimal.<site>` only the core app), merges `bootstrap/templates/site-config/*.json.template` into each `site_config.json` |
| Buckets | creates missing SeaweedFS buckets. Buckets no longer listed are **never deleted**, only reported |
| Assets | `bench build`, **one app at a time**. A failing app is reported and skipped, so Frappe and the other apps still work |
| Extras | Claude Code CLI (optional, the choice is remembered), `.vscode/` workspace files, VS Code extensions installed into the container |

A custom app that fails to clone, install or build is reported in red, and
the run continues without it.

**Reconcile.** When the bench differs from `.env`, initialize.sh explains the
difference and asks before changing anything. The cases are: another app
version (switch and migrate), an app removed from `.env` (uninstall and
archive), a renamed site (create the new one, drop the old), a changed
Administrator or MariaDB root password (apply it), a different Frappe version
(full rebuild, which requires typing `REBUILD`).

| Option | Meaning |
|---|---|
| `--vscode-detect` / `--vscode-latest` / `--vscode-commit HASH` / `--skip-vscode` | VS Code choice without the menu |
| `--platform NAME` | client platform for `--vscode-latest` (`win32-x64-user`, `win32-arm64-user`, `darwin-universal`, `linux-x64`, `linux-arm64`, `server-linux-x64`) |
| `--with-claude` / `--no-claude` | install the Claude Code CLI in the container (remembered) |
| `--reconcile ask\|apply\|skip` | how differences are handled (`skip` without a terminal) |
| `--no-build` | skip `bench build` |
| `--no-extensions` | don't install VS Code extensions in the container |

### `reseed.sh` — refresh the VS Code Server

Run it when your VS Code client updated, when *Attach* hangs, or when the
server in the container is broken. It shows the same menu as initialize.sh
every time, replaces the chosen build in the running container, and offers
to delete the other builds.

| Option | Meaning |
|---|---|
| `--detect` / `--latest` / `--commit HASH` | build choice without the menu |
| `--platform NAME` | platform for `--latest` (remembered) |
| `--purge` / `--keep-others` | delete or keep the other builds |
| `-y, --yes` | no confirmation |

### `teardown.sh` — stop and clean

A checklist, or flags. Running it with `--all` returns the folder to a fresh
clone. Deleting data (database or files volumes, `frappe-bench/`, `.env`)
requires typing `DELETE`. It warns about custom-app clones with uncommitted
or unpushed work. Host setup from install.sh is never touched.

| Target | Removes |
|---|---|
| `--stop` | nothing: only stops the containers (`./initialize.sh` restarts them) |
| `--containers` | containers and network |
| `--volumes[=mariadb,seaweedfs,clamav,vscode,claude]` | named volumes: all, or the listed ones |
| `--images` | the project's images |
| `--prune` | dangling images, unused networks, build cache (system-wide) |
| `--bench` | `frappe-bench/` |
| `--workspace` | the generated `.vscode/` files |
| `--config` | `.env` and `docker-compose.yml` (a backup stays in `.state/backups` unless `--state`) |
| `--state` | `.state/` |
| `--logs` | `logs/` |
| `--all` | all of the above |

Options: `--dry-run` (show the plan only), `-y` (skip "continue?"),
`--force` (also skip the typed confirmations; automation only).

## Configuration

`.env` is written by setup.sh from `bootstrap/templates/env.template`.

| Key | Meaning |
|---|---|
| `SITE_NAME`, `TEST_SITE_NAME`, `TEST_MINIMAL_SITE_NAME` | main site, `test.<site>` (all apps) and `test-minimal.<site>` (core app only) |
| `MAIN_SITE_DEVELOPER_MODE` | `1`/`0` |
| `ADMIN_PASSWORD` | Administrator password of both sites |
| `MARIADB_ROOT_USERNAME`, `MARIADB_ROOT_PASSWORD`, `MARIADB_EXPOSE_PORT` | database |
| `SEAWEEDFS_ACCESS_KEY`, `SEAWEEDFS_SECRET_KEY`, `SEAWEEDFS_BUCKETS` | S3 storage. SeaweedFS requires these keys on its S3 API (anonymous S3 requests are refused) |
| `CLAMAV_HOST`, `CLAMAV_PORT` | antivirus (clamd), written into every `site_config.json` as `clamav_host` / `clamav_port` |
| `FRAPPE_VERSION`, `DEFAULT_APPS`, `<APP>_VERSION` | framework and default apps (tag or branch) |
| `JWT_SECRET`, `WEBRTC_ANNOUNCED_IP`, `MEDIASOUP_ANNOUNCED_IP` | Meet SFU (only with Meet) |
| `APPS_MODE` | `shell` or `custom` |
| `CUSTOM_APPS_GIT_PREFIX`, `CUSTOM_APPS`, `CUSTOM_APP_URLS`, `CORE_APP` | custom apps; the core app is listed first |

## Customizing

Every generated file comes from a template in `bootstrap/templates/`.
Templates use `@@KEY@@` placeholders, `@@IF KEY@@ … @@ENDIF KEY@@` blocks
and `@@# comment` lines (stripped).

| Template | Generates / controls |
|---|---|
| `apps.catalog` | the default apps offered by setup.sh: repository, dependencies, flags (`follows-frappe`, `sfu`), description |
| `env.template` | `.env` |
| `docker-compose.yml.template` | `docker-compose.yml`: images, ports, volumes, services (meet-sfu and the MariaDB port are conditional) |
| `site-config/main.json.template`, `site-config/test.json.template` | keys merged into each site's `site_config.json` on every initialize |
| `buckets.list` | buckets suggested by setup.sh |
| `answers.example.conf` | example for `setup.sh --answers` |
| `vscode/extensions.list` | extensions installed in the container and recommended by the workspace |
| `vscode/*.template` | `.vscode/dev.code-workspace`, `settings.json`, `extensions.json` |
| `claude/*.template` | `frappe-bench/.claude/settings.json` and `frappe-bench/CLAUDE.md` |
| `ftp.conf` | vsftpd settings applied by install.sh |

Script-level knobs are in `bootstrap/settings.conf`: compose project name,
log retention, service wait timeout, container user, and the number of tags
shown by the version picker.

## Git hooks

The repository's checks run as git hooks through
[pre-commit](https://pre-commit.com). `./install.sh` installs them on the
host (base component) and `./initialize.sh` in the frappe container.

| Hook | Checks |
|---|---|
| pre-commit-hooks | whitespace, end of files, merge markers, JSON/TOML/YAML syntax, shebangs |
| gitleaks | secrets in the staged changes |
| conventional-pre-commit | commit messages follow Conventional Commits (`feat: …`, `fix: …`, `docs: …`) |
| shellcheck | Bash scripts |
| ruff | Python lint (incl. security rules) and format, settings in `ruff.toml` |
| markdownlint-cli2 | Markdown style, settings in `.markdownlint-cli2.yaml` |
| lychee | links between Markdown files and to their headings (offline) |
| guide consistency | architecture guide: rule IDs unique and defined, links valid |

Run every check by hand with `pre-commit run --all-files` (or `just lint`).

## Common tasks

The `justfile` holds the repository's tasks (`just` lists them). `just` is
installed on the host by `./install.sh` and in the container by
`./initialize.sh`.

| Command | Does |
|---|---|
| `just setup` | installs the git hooks and their environments (not `./setup.sh`) |
| `just fmt` | formats Python and fixes whitespace and end of files |
| `just lint` | every git-hook check on every file |
| `just scan` | secret scan of the whole git history |
| `just check-guide` | architecture guide: rule IDs and links |
| `just book` | builds the guide as PDF and EPUB (host only: needs Docker) |
| `just ci` | `lint` + `scan` |

Decisions about this repository are recorded in [`docs/adr/`](docs/adr/README.md);
how to report a vulnerability is in [`SECURITY.md`](SECURITY.md).

## Logs and state

- `logs/<script>-<timestamp>.log`: one verbose log per run. It records the
  host, OS, Docker and git details, every question and answer, every command
  with its full output, exit codes and timings. Known secrets are replaced
  by `****`. The last 5 runs per script are kept (`LOG_KEEP`), and
  `logs/<script>-latest.log` points to the newest one.
- `.state/` holds runtime state:
  - `initialized.env`: snapshot of the last successful initialize, used by
    setup.sh's change warnings
  - the cached VS Code Server tarballs, platform and commit
  - `backups/`: the 10 most recent backups of each generated file
  - initialize.sh preferences
- `frappe-bench/.frappe-dev/state` records which apps and sites the scripts
  manage. Reconcile only ever offers to remove those.

## Local access and ports

| Port | Service |
|---|---|
| 8000-8005 | bench web server (`http://<site>:8000`) |
| 9000-9005 | socket.io |
| 5173 | Vite dev server |
| 3306 | MariaDB (only if published) |
| 8333 / 8888 / 9333 / 8080 / 7333 | SeaweedFS S3 (keys required) / filer / master / volume / WebDAV |
| — | ClamAV (clamd on `clamav:3310`, inside the compose network only) |
| 3000 TCP, 40000-40099 UDP | Meet SFU (only with Meet) |
| 21, 40000-50000 TCP | FTP (only with the ftp component) |

## Repository layout

```text
.
├── install.sh                 # host preparation
├── setup.sh                   # configuration → .env, docker-compose.yml
├── initialize.sh              # build & start
├── reseed.sh                  # VS Code Server refresh
├── teardown.sh                # stop & clean
├── bootstrap/
│   ├── settings.conf          # script-level settings
│   ├── lib/                   # shared code: ui, log, common, apps, project, vscode, tools, render.py
│   ├── container/
│   │   └── provision.sh       # runs inside the frappe container, step by step
│   └── templates/             # every generated file starts here
├── architecture/              # Platform Architecture Guide (authoritative)
├── docs/adr/                  # decisions about this repository (ADRs)
├── justfile                   # common tasks (see Common tasks)
├── SECURITY.md                # how to report a vulnerability
├── .pre-commit-config.yaml    # git hooks (see Git hooks)
├── .markdownlint-cli2.yaml    # Markdown style settings
└── ruff.toml                  # Python lint/format settings
```

`new-app.sh`, `check-env.sh` and the frontend toolchain setup (`setup-env.sh`)
of the previous scripts will be rebuilt on this structure.

## License

See [LICENSE](./LICENSE).
