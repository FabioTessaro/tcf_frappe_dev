<!-- markdownlint-disable-file MD041 -->
<!-- Pull-request template of the development-environment repository.
     Title: a Conventional Commit (`feat: …`, `fix: …`, `docs: …`).
     Changes to the platform repository or a custom app belong in those
     repositories, which have their own template. -->

## What and why

<!-- One or two sentences. Link the issue it closes (`Closes #123`) and cite
     guide rule IDs or ADRs when relevant. -->

## Kind of change

- [ ] Scripts or `bootstrap/` libraries
- [ ] Templates (`bootstrap/templates/`)
- [ ] Architecture guide (`architecture/`)
- [ ] ADR (`docs/adr/`)
- [ ] Other documentation or repository configuration

## How it was tested

<!-- Which scripts you ran, with which options, on which host OS, and whether
     you tried both a fresh run and a re-run. Write "docs only" if nothing
     needed running. -->

## Checklist

Tick what applies; explain any unticked item.

- [ ] `just ci` passes; no check was skipped or disabled
- [ ] Scripts stay re-runnable: tested on a fresh run and on a re-run
- [ ] New or changed options are in `--help` and the README
- [ ] Generated files were changed through their template in `bootstrap/templates/`
- [ ] No secrets, personal data or real records in code, templates, logs or screenshots
- [ ] Guide changed? Version bumped and changelog line added (FND-GOV-002, FND-GOV-003); `just check-guide` passes
- [ ] Decision made or SHOULD rule deviated from? ADR added and listed in `docs/adr/README.md` (FND-GOV-004)
- [ ] Breaking change (existing `.env`, environments or scaffolded repositories need manual steps)? Marked `!` in the title, with the steps described above
