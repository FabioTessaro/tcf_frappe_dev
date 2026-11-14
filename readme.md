# TCF Frappe Development

A Docker Compose-based development environment for Frappe Framework and custom TCF apps. It provisions a Frappe bench, supporting services, and a VS Code Dev Container so development can happen in a consistent environment on a remote Ubuntu server.

The repository contains the environment and lifecycle scripts. **Custom Frappe app source code is cloned separately** and is not stored in this repository.

## Architecture

The intended frontend architecture is documented in **[Frappe Multi-app Vue Architecture](./Frappe%20Multi-app%20Vue%20Architecture.md)**. It describes the division of responsibilities between:

- **Core app:** Vue 3 portal shell, authentication pages, launcher, shared UI, design tokens, typography and frontend SDK.
- **Feature apps:** independently owned feature slices, backend APIs and permissions, composed into the core portal at build time.
- **Public website app:** a conventional Frappe website app, separate from the Vue portal.

The document is an architecture reference; the scripts in this repository provision the development environment and do not generate the complete Vue application implementation.

## What gets provisioned

- Frappe bench and the apps configured in `.env`.
- MariaDB, Redis, SeaweedFS and the Frappe Meet SFU through Docker Compose.
- Node.js, Corepack, pnpm and the frontend development toolchain inside the Dev Container.
- VS Code workspace settings and extension recommendations.
- Playwright and Chromium for browser-based end-to-end tests.

## Requirements

On the remote development host:

- Ubuntu Server (the bootstrap scripts target Debian/Ubuntu).
- Git, Python 3, curl, sudo privileges and an SSH key with access to the custom app repositories.
- Docker Engine and the Docker Compose plugin. `install.sh` installs Docker when it is missing.

On your local development machine:

- Visual Studio Code.
- **Remote - SSH** (`ms-vscode-remote.remote-ssh`).
- **Dev Containers** (`ms-vscode-remote.remote-containers`).

The extensions are also available together in the [Remote Development extension pack](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.vscode-remote-extensionpack).

## Quick start

Clone the repository on the remote host and run the installer:

```bash
git clone https://github.com/FabioTessaro/tcf_frappe_dev.git frappe-dev
cd frappe-dev
./install.sh
```

The installer:

1. Checks Git identity and SSH access.
2. Creates `.env` through the internal `bootstrap/setup-env.sh` helper if it does not already exist.
3. Generates the Dev Container configuration from the checked-in template.
4. Installs Docker when required and starts the project services.
5. Provisions the Frappe bench and configured apps.
6. Installs the container-side development toolchain and prepares Playwright.

`install.sh` defaults to the **Attach to Running Container** workflow. Use `./install.sh --reopen` to prepare the **Reopen in Container** workflow instead.

## Connect with VS Code

### Attach to Running Container (default)

1. Connect to the remote host using Remote - SSH.
2. Open the `frappe-dev` repository folder.
3. Run **Dev Containers: Attach to Running Container...**.
4. Select the `frappe` container.
5. Open `.vscode/dev.code-workspace` from inside the container.

The first attach can require VS Code Server to transfer a large server bundle. The installer attempts to pre-seed the matching server build in the container to avoid transfer hangs.

### Reopen in Container

Run:

```bash
./install.sh --reopen
```

Then open the repository in VS Code over Remote - SSH and run **Dev Containers: Reopen in Container**. The Dev Container's `postCreateCommand` provisions the bench and common development tools. The pipeline can be checked or repaired from the container terminal with `./check-env.sh` and `./setup-env.sh`.

## Root scripts: what they do and when to use them

The scripts in the repository root are the supported commands for operating the development environment. Run them from a terminal in the repository; they resolve paths relative to their own location.

### On the remote host

| Script | What it does | When to use it |
|---|---|---|
| `./install.sh` | First-time setup and orchestration. Creates `.env` when needed, configures Docker and Compose, starts services, provisions the bench and prepares the development container. | Run once for a new environment, or again to repair/re-run setup. Defaults to `--attach`; use `--reopen` for the Reopen in Container workflow. Optional flags: `--with-agents`, `--no-default-apps` and `--with-ftp`. |
| `./startup.sh` | Starts the Compose services and checks whether the bench is provisioned. It can offer to repair an incomplete bench. | Run when you want to start or resume development after shutting the environment down. |
| `./shutdown.sh` | Stops and removes the project containers. | Run when finished working. By default, it preserves data volumes and images. |
| `./reseed.sh` | Re-downloads and copies the matching VS Code Server build into the `frappe` container. | Use when VS Code **Attach to Running Container** hangs, the server installation is incomplete, or the VS Code client has updated. |
| `./new-app.sh <app-name>` | Creates a Frappe app, optionally installs it, helps create and push its Git remote, and adds it to `TCF_APPS` after a successful push. It also updates the VS Code workspace when present. | Use after the bench has been provisioned when adding another custom app. `--no-install` skips site installation; `--no-push` skips the remote/push step and does not update `TCF_APPS`. It can be run on the host (with the containers running) or inside the `frappe` container. |

Useful examples:

```bash
./install.sh --reopen
./startup.sh
./shutdown.sh --clean
./new-app.sh tcf_projects
./reseed.sh --auto
```

`shutdown.sh` offers increasingly destructive cleanup options:

- `--clean`: also prunes unused Docker resources and build cache; project data volumes are preserved.
- `--volumes`: also deletes the MariaDB and SeaweedFS data volumes. **This deletes the development database and uploaded files.**
- `--images`: also removes the project images; data volumes are preserved.
- `--all`: removes containers, volumes, images and the local `frappe-bench/` directory, returning the environment to a fresh-install state.

`reseed.sh` is interactive when run without options. For non-interactive use it supports `--auto`, `--latest`, `--commit <hash>`, `--platform <name>`, `--purge` and `--yes`. `--purge` removes other VS Code Server builds in the container and can interrupt windows attached with those builds.

### Inside the Dev Container

| Script | What it does | When to use it |
|---|---|---|
| `./setup-env.sh` | Installs or repairs the development pipeline: system prerequisites, Node.js, Corepack, pnpm, frontend dependencies, Playwright and development tooling. **It does not create or modify `.env`.** | Run from the `frappe` container terminal after provisioning, or whenever you need to repair/update the frontend toolchain. It is safe to re-run. |
| `./check-env.sh` | Performs a read-only audit of the development environment and reports missing tools or configuration. | Run before or after `setup-env.sh` to diagnose the container. It does not install or change anything. |

Typical container-side workflow:

```bash
./check-env.sh
./setup-env.sh
./check-env.sh
```

### `.env` ownership

The internal `bootstrap/setup-env.sh` helper creates the project `.env` during `./install.sh` only. Do not run that helper directly. The root `./setup-env.sh` is unrelated to `.env`: it configures the development pipeline inside the container. After initial installation, `./new-app.sh` is the workflow that adds a newly created app to `TCF_APPS` in `.env`, and only after its push succeeds. Do not commit `.env`.

## Configuration

The `.env` file contains credentials, service settings, app versions and custom-app configuration.

Important settings:

- `TCF_SITE_NAME`: Frappe site name (default `tcf.local`).
- `TCF_APPS`: space-separated custom app names to clone and install.
- `TCF_APPS_GIT_PREFIX`: Git URL prefix used to clone custom apps.
- `*_VERSION`: Git tags or branches for the Frappe and dependency apps.
- `WEBRTC_ANNOUNCED_IP`: address advertised by the Meet SFU to WebRTC clients.

Custom app folders are cloned into `frappe-bench/apps/`. Add apps with `./new-app.sh <app-name>`; successful pushes are added to `TCF_APPS` so future bench provisioning can restore them.

## Local access

Add the following entry to the hosts file of the machine from which you access the site, replacing `<remote-host-ip>` with the host's LAN address:

```text
<remote-host-ip>  tcf.local
```

Then open [http://tcf.local:8000](http://tcf.local:8000). The Administrator password is stored in `.env` as `ADMIN_PASSWORD`.

MariaDB is exposed on port `3306` for local database tools such as DBeaver. The Meet SFU uses TCP port `3000` and UDP ports `40000-40099`; make sure any intervening firewall allows the required traffic when testing calls from another machine.

## Repository layout

```text
.
├── bootstrap/
│   ├── setup-env.sh     # Internal .env generation; called by install.sh only
│   ├── templates/       # Templates for generated configuration files
│   └── *.sh             # Provisioning and configuration helpers
├── .devcontainer/       # Docker Compose development services
├── install.sh           # First-time setup and orchestration (host)
├── startup.sh           # Start services (host)
├── shutdown.sh          # Stop services and optional cleanup (host)
├── reseed.sh            # VS Code Server recovery (host)
├── new-app.sh           # Create and register a custom Frappe app
├── setup-env.sh         # Install/repair the pipeline toolchain (container)
└── check-env.sh         # Read-only environment audit (container)
```

## License

See [LICENSE](./LICENSE).
