# Security policy

This repository holds the **development environment** of the platform: scripts
that prepare a host, configure and start Docker containers, and provision a
Frappe bench. It contains no application code and produces no release
artifacts (see the [architecture guide](architecture/README.md), rule
`SEC-VULN-010`).

## Supported versions

Only the latest commit on `main` is supported. Fixes are not backported.

## Reporting a vulnerability

Please **do not open a public issue** for security problems.

Report them privately through GitHub's private vulnerability reporting:
[Report a vulnerability](https://github.com/FabioTessaro/tcf_frappe_dev/security/advisories/new).

Include, where possible:

- what is affected (script, template, container, configuration key);
- how to reproduce it, and its impact;
- whether it is already public.

You will get an acknowledgement within 5 working days. Confirmed issues are
fixed on `main`, and the advisory is published once a fix is available.

## In scope

- secrets leaking from `.env`, logs, generated files or containers;
- services exposed or reachable without authentication beyond what the
  [README](README.md) documents;
- unsafe handling of downloaded tools, images or scripts;
- command injection through configuration values.

## Out of scope

- Vulnerabilities in Frappe, ERPNext or other upstream apps: report them to
  their projects.
- Vulnerabilities in the custom apps: report them to their own repositories
  (each one has its own `SECURITY.md`).
- Development conveniences documented in the README, such as MariaDB published
  on the host or the SeaweedFS filer UI, which are intentional for a
  development environment that must never hold real data.
