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
2. Calls the private bootstrap helper `bootstrap/setup-env.sh` to create `.env` when it does not already exist.
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

Then open the repository in VS Code over Remote - SSH and run **Dev Containers: Reopen in Container**. The Dev Container's `postCreateCommand` provisions the bench and common development tools. When more than one custom app is installed, select the core app afterwards from the container terminal:

```bash
./setup-env.sh
```

## Configuration

`install.sh` creates `.env` on the first run by calling `bootstrap/setup-env.sh`. That helper is an internal part of initial installation; run `./install.sh` rather than invoking it manually. The root-level `./setup-env.sh` has a different responsibility: it installs and configures the development pipeline inside the Dev Container and never changes `.env`. After initial installation, `./new-app.sh` is the only workflow that updates `.env`: it adds the new app to `TCF_APPS` only after the app has been successfully pushed. The file contains credentials, service settings, app versions and custom-app configuration. **Do not commit `.env`.**

Important settings:

- `TCF_SITE_NAME`: Frappe site name (default `tcf.local`).
- `TCF_APPS`: space-separated custom app names to clone and install.
- `TCF_APPS_GIT_PREFIX`: Git URL prefix used to clone custom apps.
- `*_VERSION`: Git tags or branches for the Frappe and dependency apps.
- `WEBRTC_ANNOUNCED_IP`: address advertised by the Meet SFU to WebRTC clients.

Custom app folders are cloned into `frappe-bench/apps/`. Add or create apps with `./new-app.sh <app-name>`; successful pushes are added to `TCF_APPS` so future bench provisioning can restore them.

## Common commands

Run the root scripts from the repository directory. They resolve paths relative to their own location, so the current working directory does not otherwise matter.

| Command | Purpose |
|---|---|
| `./install.sh` | Initial setup or repair; accepts `--attach` (default) or `--reopen`. |
| `./setup-env.sh` | Set up or repair the development pipeline inside the Dev Container: Node.js, pnpm, frontend dependencies, Playwright and workspace tooling. Does not modify `.env`. |
| `./startup.sh` | Start the services and offer to repair an incomplete bench. Safe to repeat. |
| `./shutdown.sh` | Stop the services. Optional cleanup tiers: `--clean`, `--volumes`, `--images`, `--all`. |
| `./reseed.sh` | Re-download and seed the VS Code Server build in the `frappe` container. |
| `./new-app.sh <app-name>` | Create and optionally install a custom Frappe app, create its Git remote and add it to `TCF_APPS` in `.env` after a successful push. |
| `./check-env.sh` | Read-only development-environment audit. Run inside the Dev Container. |

The pipeline setup is separate from the read-only audit script and can be re-run when repairing or updating the container toolchain:

```bash
./setup-env.sh
```

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
├── install.sh           # Initial setup and orchestration
├── setup-env.sh         # Development pipeline toolchain setup
├── startup.sh           # Start services
├── shutdown.sh          # Stop services and optional cleanup
├── reseed.sh            # VS Code Server recovery
├── new-app.sh           # Custom Frappe app scaffolding
└── check-env.sh         # Read-only environment audit
```

## License

See [LICENSE](./LICENSE).
