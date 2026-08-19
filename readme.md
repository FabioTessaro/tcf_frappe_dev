# TCF FRAPPE DEVELOPMENT

Container orchestration and bootstrap scripts for the TCF Frappe Development
environment. Meant to run on a dedicated Ubuntu Server (reachable at `<your-server-ip>` on the LAN) that you develop against
remotely via VS Code Remote-SSH.

## Prerequisites

On the machine you'll develop **from** (not the VM), install these VS Code
extensions:

- **Remote - SSH** (`ms-vscode-remote.remote-ssh`)
- **Dev Containers** (`ms-vscode-remote.remote-containers`)

Both come bundled together in the **Remote Development** extension pack
(`ms-vscode-remote.vscode-remote-extensionpack`) if you'd rather install one
thing.

Before running `install.sh`, connect to the VM once with plain **Remote-SSH**
(just opening a folder over SSH — not "Attach to Running Container", since
the containers don't exist yet). This installs VS Code Server on the VM host
under `~/.vscode-server/`, which is exactly what `bootstrap/setup-vscode.sh`
looks for later to pre-seed the container's copy automatically, skipping the
guesswork entirely (see [VS Code Server pre-seeding](#vs-code-server-pre-seeding)
below).

## Quickstart

This assumes a valid ssh configuration is already set up for git (or, if not,
`install.sh` will walk you through generating and registering a key).

    git clone https://github.com/FabioTessaro/tcf_frappe_dev.git frappe-dev
    cd frappe-dev
    ./install.sh

`install.sh` runs the full first-time setup: git identity/SSH check, `.env`
generation, installing Docker if it's missing, pulling and starting the 5
containers (`mariadb`, `redis-cache`, `redis-queue`, `seaweedfs`, `frappe`),
pre-seeding the VS Code Server build inside the `frappe` container (see
[VS Code Server pre-seeding](#vs-code-server-pre-seeding) below), and running
`bootstrap/setup-bench.sh` inside the frappe container — which initializes
bench, fetches erpnext/hrms and the apps listed in `TCF_APPS`, and creates
`tcf.local` with developer_mode enabled.

Containers run with a `restart: unless-stopped` policy, so they come back up
automatically after a Docker/VM restart — you shouldn't need to re-run
`install.sh` for that.

## Connecting from VS Code

1. Remote-SSH into the VM and open the `frappe-dev` folder.
2. Run **Dev Containers: Attach to Running Container...** and pick `frappe`.
3. First attach only: run **Dev Containers: Open Container Configuration
   File** and copy in the `extensions`/`settings` from
   `.devcontainer/devcontainer.json`. VS Code remembers this per container
   name from then on — it's a one-time step, not per-session.

`.devcontainer/devcontainer.json` intentionally does **not** define
`dockerComposeFile`/`service`/`postCreateCommand` — those are only used by
VS Code's "Reopen in Container" flow, which this project doesn't use. Only
properties that "Attach to Running Container" actually honors are kept
(`remoteUser`, `workspaceFolder`, `customizations.vscode`).

### VS Code Server pre-seeding

Attaching normally makes VS Code stream the ~200MB VS Code Server build
through `docker exec`'s stdin, which has been observed to hang indefinitely
partway through on some Docker Engine versions (the attach window just spins
forever, with no error). `install.sh`/`startup.sh` avoid this automatically
by pre-seeding the correct build straight into the container beforehand,
via `bootstrap/setup-vscode.sh`:

- Detects the exact build your local VS Code client needs from what it's
  already installed on the VM host (`~/.vscode-server/`, created the moment
  you first Remote-SSH into the VM — no extra step required), or from a
  partial folder left behind by a previous hung attach.
- If you've genuinely never connected to this VM with VS Code before, it
  falls back to asking which platform you develop from once and guessing
  the matching latest-stable build — clearly logged as an unconfirmed
  guess, and automatically replaced with the real one on a later run once
  an actual connection is detected.
- Safe to re-run by hand any time: `./bootstrap/setup-vscode.sh`.
- The seeded build is cached in the `vscode-server` volume so it survives
  container recreation, not just restarts.

### Reaching the site from a browser

Add this to the hosts file of whichever machine you're browsing *from*:

    <your-server-ip>   tcf.local

Then visit `http://tcf.local:8000`. MariaDB is exposed on <your-server-ip>:3306`
for tools like DBeaver.

## Day-to-day scripts

- **`./startup.sh`** — bring containers back up after a manual stop or a
  reboot. Checks the Docker daemon is running (offers to start it if not),
  skips work if everything's already up, and if `frappe-bench` looks
  incomplete (e.g. after a `--volumes`/`--all` shutdown) offers to re-run
  provisioning.
- **`./shutdown.sh [tier]`** — stop containers safely at the end of a
  session, with optional deeper cleanup tiers. Run `./shutdown.sh --help`
  for the full list. Each tier includes everything from the ones above it:
  - *(none)* — stop and remove containers only. Safe default.
  - `--clean` — + prune dangling images/build cache. Non-destructive.
  - `--volumes` — + delete the `mariadb-data`/`seaweedfs-data` volumes
    (wipes the dev database and uploaded/CAD files). Also clears the
    `vscode-server` cache volume, which is harmless — it's just re-seeded
    automatically next time `startup.sh`/`install.sh` runs. Requires typed
    confirmation.
  - `--images` — + remove every image used by this project (re-pulled on
    next start).
  - `--all` — complete fresh state: containers, volumes, images, and the
    local `frappe-bench/` folder. After this, `./install.sh` behaves like a
    first-ever run.

## Apps

App code is NOT stored in this repo. `TCF_APPS` in `.env` controls which of
`tcf_hr`, `tcf_erp`, `tcf_plm`, `tcf_qms`, `tcf_web` get cloned and installed
on bootstrap.