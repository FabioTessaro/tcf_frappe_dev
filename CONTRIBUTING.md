# Contributing

Thanks for your interest in this repository. It holds the **development
environment** of the platform (the scripts that prepare a host, configure and
start the containers and provision a Frappe bench) and the
[Platform Architecture Guide](architecture/README.md). It has a single
maintainer, so please keep changes focused and expect some delay in replies.

By taking part you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Where things belong

| You want to… | Go to |
|---|---|
| report a security problem | **not an issue**: follow [SECURITY.md](SECURITY.md) |
| report a bug in a script, template or container setup | an issue here (*Bug report*) |
| propose a new option, component or script | an issue here (*Feature request*) |
| change or question a rule of the architecture guide | an issue here (*Architecture guide change*) |
| change the `platform` repository or a custom app | that repository, not this one (`platform/` and `frappe-bench/apps/*` are separate git repositories) |
| report a problem in Frappe, ERPNext or another upstream app | the upstream project |

For anything bigger than a small fix, open an issue first so we can agree on
the approach before you write the code.

## Getting set up

Follow the [Quick start](README.md#quick-start) to get a working
environment, then install the git hooks:

```bash
just setup   # git hooks and their environments (not ./setup.sh)
```

Don't use a bare `pre-commit install`: the host and the container share
`.git`, and the portable hooks of `bootstrap/lib/githooks.sh` are what make
commits work on both sides (see [Git hooks](README.md#git-hooks)).

## Making a change

1. Fork the repository and create a branch from `main`.
2. Make the change. Keep to one topic per pull request.
3. Run the checks: `just ci` (every git-hook check on every file, plus a secret
   scan of the history). Fix what they report; don't disable a check to get it
   to pass.
4. Commit with a [Conventional Commits](https://www.conventionalcommits.org/)
   message (`feat: …`, `fix: …`, `docs: …`, `refactor: …`, `chore: …`); the
   `commit-msg` hook checks it.
5. Open a pull request and fill in the template.

### Scripts and templates

- Every script must stay **re-runnable**: it checks the current state and only
  does what is missing. Test a change both on a fresh run and on a re-run over
  an existing environment.
- Keep the shared terminal UI (`bootstrap/lib/ui.sh`) and logging
  (`bootstrap/lib/log.sh`): menus, spinners, ✔ / ▲ / ✖ messages, and secrets
  masked in logs.
- New options need a `--help` entry and a line in the [README](README.md).
- Generated files come from `bootstrap/templates/`; change the template, not
  the generated file. Changes under `bootstrap/templates/platform/` only reach
  `platform` repositories scaffolded afterwards.
- Never commit `.env`, `logs/`, `.state/` or anything holding real secrets or
  personal data. Logs mask known secrets, but check them before pasting them
  anywhere.

### Architecture guide

The guide is the authoritative source of truth for every app built on this
environment, so changes to it follow its own
[governance rules](architecture/00-foundations/02-governance.md):

- A change that adds, removes or changes a rule bumps the guide version
  (major / minor / patch, `FND-GOV-002`) and adds a line to the changelog at
  the bottom of the governance chapter (`FND-GOV-003`).
- A proposal is written as an ADR in [`docs/adr/`](docs/adr/README.md) and
  applied to the guide in the same change (`FND-GOV-010`). Use the
  [ADR template](architecture/90-appendices/adr-template.md) and add the ADR
  to the index.
- A MUST rule cannot be waived by an ADR; change the rule instead
  (`FND-GOV-005`).
- `just check-guide` checks that rule IDs are unique and defined and that the
  links are valid.

### Decisions about this repository

Decisions about the development environment itself (tools, hosting, how the
scripts behave) are recorded as ADRs in [`docs/adr/`](docs/adr/README.md),
numbered in order and never renumbered.

## Licence

This repository is licensed under the [GNU GPL v3](LICENSE). By submitting a
contribution you agree that it is licensed under the same terms.
