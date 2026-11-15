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
- Frontend dependencies for the configured core app.
- Bench application assets, compiled after the frontend toolchain is installed.
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

On the first run, the installer asks for the environment configuration, including:

- Frappe and dependency app versions.
- Site and service credentials.
- The core app that owns the Vue frontend (`CORE_APP`, default `tcf_core`).
- Additional custom apps to clone and install.

The core app is automatically included in `TCF_APPS`, so it does not need to be entered again as an additional app.

The installer then:

1. Checks Git identity and SSH access.
2. Creates `.env` from the checked-in template, or migrates missing core-app configuration in an existing `.env`.
3. Generates the Dev Container configuration from the checked-in template.
4. Installs Docker when required and starts the project services in Attach mode.
5. Provisions the Frappe bench and configured apps. Asset compilation is deferred at this stage.
6. Installs the container-side development toolchain, including Node.js, Corepack and pnpm.
7. Selects `CORE_APP`, installs its frontend dependencies and builds the Bench assets.
8. Installs Playwright browsers and configures the development tools.

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

Then open the repository in VS Code over Remote - SSH and run **Dev Containers: Reopen in Container**.

The Dev Container's `postCreateCommand` automatically provisions the Bench, installs the Node.js and pnpm toolchain, prepares the core frontend, and builds the application assets.

The configured `CORE_APP` is read from `.env`, so no interactive core-app selection or manual provisioning command is required after reopening.

## Configuration

`install.sh` creates `.env` on the first run by calling `bootstrap/setup-env.sh`. That helper is an internal part of installation; run `./install.sh` rather than invoking it manually.

The root-level `./setup-env.sh` has a different responsibility: it installs and configures the development pipeline inside the Dev Container. It does not create or modify `.env`.

The file contains credentials, service settings, app versions and custom-app configuration. **Do not commit `.env`.**

### Important settings

- `TCF_SITE_NAME`: Frappe site name (default `tcf.local`).
- `CORE_APP`: custom Frappe app that owns the Vue portal and its frontend development pipeline (default `tcf_core`).
- `TCF_APPS`: space-separated custom app names to clone and install. The core app is included automatically.
- `TCF_APPS_GIT_PREFIX`: Git URL prefix used to clone custom apps.
- `*_VERSION`: Git tags or branches for the Frappe and dependency apps.
- `WEBRTC_ANNOUNCED_IP`: address advertised by the Meet SFU to WebRTC clients.

`CORE_APP` must identify one of the apps included in `TCF_APPS`. The selected app must also be cloned into `frappe-bench/apps/` and installed on the configured Frappe site.

`CORE_APP` and `TCF_APPS` may both be empty (answer `none` at the `CORE_APP` prompt, or pass `--no-custom-apps`): no custom app is fetched or installed and the pipeline only builds the Bench assets. Inside the container, `.env` is authoritative for these two keys, so a container created from an older `.env` doesn't bring stale values back.

For an existing `.env` without a `CORE_APP` key, `install.sh` adds the default `tcf_core` setting and ensures that the core app is included in `TCF_APPS`, preserving the other environment settings.

Custom app folders are cloned into `frappe-bench/apps/`. Add or create apps with `./new-app.sh <app-name>`. It first asks whether you are creating a **feature app** (appended to the end of `TCF_APPS`; `CORE_APP` is untouched) or a **new core app** (set as `CORE_APP` and placed first in `TCF_APPS`; any previous core app stays in `TCF_APPS`). Pass `--feature` or `--core` to skip the question. `.env` is only updated after a successful push, so future bench provisioning can restore the app.

## Common commands

Run the root scripts from the repository directory. They resolve paths relative to their own location, so the current working directory does not otherwise matter.

| Command | Purpose |
|---|---|
| `./install.sh` | Initial setup using Attach to Running Container mode. |
| `./install.sh --attach` | Explicitly use Attach to Running Container mode. |
| `./install.sh --reopen` | Prepare the Reopen in Container workflow. |
| `./install.sh --no-default-apps` | Skip the default dependency apps during Attach-mode provisioning. |
| `./install.sh --no-custom-apps` | Install without any custom (TCF) apps, not even the core app: empties `CORE_APP` and `TCF_APPS` in `.env` and skips the core-frontend setup. Combine with `--no-default-apps` for a bare Frappe bench. |
| `./setup-env.sh` | Set up or repair the development pipeline inside the Dev Container: Node.js, pnpm, frontend dependencies, Bench assets, Playwright and workspace tooling. Does not modify `.env`. |
| `./startup.sh` | Start the services and offer to repair an incomplete Bench. Safe to repeat. |
| `./shutdown.sh` | Stop the services. Optional cleanup tiers: `--clean`, `--volumes`, `--images`, `--all`. |
| `./reseed.sh` | Re-download and seed the VS Code Server build in the `frappe` container. |
| `./new-app.sh [--feature\|--core] <app-name>` | Create and optionally install a custom Frappe app (feature app or new core app), create its Git remote and update `.env` after a successful push: a feature app is appended to `TCF_APPS`; a core app becomes `CORE_APP` and is put first in `TCF_APPS`. |
| `./check-env.sh` | Read-only development-environment audit. Run inside the Dev Container. |

The pipeline setup is separate from the read-only audit script. It can be re-run when repairing or updating the container toolchain:

```bash
./setup-env.sh
```

The frontend dependency installer maintains the core app's frontend package manifest and uses pnpm for frontend dependencies. The Frappe app root remains compatible with Bench's Yarn-based app installation.

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
│   ├── setup-env.sh       # Internal .env creation and migration helper
│   ├── templates/         # Templates for generated configuration files
│   └── *.sh               # Provisioning and configuration helpers
├── .devcontainer/         # Docker Compose and Dev Container configuration
├── install.sh             # Initial setup and orchestration
├── setup-env.sh           # Development pipeline toolchain setup
├── startup.sh             # Start services
├── shutdown.sh            # Stop services and optional cleanup
├── reseed.sh              # VS Code Server recovery
├── new-app.sh             # Custom Frappe app scaffolding
└── check-env.sh           # Read-only environment audit
```

## License

See [LICENSE](./LICENSE).
