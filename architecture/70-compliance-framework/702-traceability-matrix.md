# 702 · Traceability matrix

## Purpose

Maps each norm requirement to the guide rules that support it, the app/feature implementing it and
the evidence an auditor can inspect. It is filled progressively: platform-level rows first, app
rows as apps are built.

## Rules

- `CMP-TRC-001` Each row MUST reference at least one rule ID or app feature, and one evidence item
  (report, record type, test, procedure).
- `CMP-TRC-002` Status values: `planned` → `implemented` (code merged) → `verified` (evidence
  reviewed, e.g. by internal audit).
- `CMP-TRC-003` Apps add their rows in the same pull request that implements the feature.
- `CMP-TRC-004` Clause references are summaries for navigation; the normative text is the norm itself.

## Platform-level rows (initial)

| Norm · clause | Requirement (summary) | Guide rules | App / feature | Evidence | Status |
|---|---|---|---|---|---|
| ISO 27001 A.5.12–A.5.13 | Classification and labelling | DOM-CLS-001…006 | core | Classification Level records; contract test | planned |
| ISO 27001 A.5.15–A.5.18, A.8.2–A.8.5 · NIS2 21(2)(i)(j) | Access control, authentication, MFA | SEC-MOD-001…021, SEC-BASE-001…003, SYS-ACC-001…006 | core | Permission tests; access review report | planned |
| ISO 27001 A.5.19–A.5.22 · NIS2 21(2)(d) | Supplier relationships, supply-chain security | DOM-PTY-001…010, SEC-VULN-001…005, DEL-REL-004…005 | core (Party), platform | Party screening status; SBOMs | planned |
| ISO 27001 A.5.24–A.5.28 · NIS2 Art. 23 · CRA Art. 14 | Incident management and reporting | SEC-INC-001…004 | core | Security Incident records | planned |
| ISO 27001 A.5.29–A.5.30, A.8.13 · NIS2 21(2)(c) | Continuity, backups | OPS-BAK-001…006, DEL-CD-003/004 | platform | Restore test records | planned |
| ISO 27001 A.5.33 · ISO 15489 · ISO 16175 · EN 9100 7.5.3 | Protection and management of records | SEC-REC-001…007, SEC-AUD-001…011 | core | Retention classes, disposition records, audit exports | planned |
| ISO 27001 A.5.34 · ISO 27701 · GDPR Art. 30 | Privacy and PII | SEC-PRIV-001…007, BE-DATA-006 | core | Record of processing (generated); DSAR log | planned |
| ISO 27001 A.8.7 | Protection against malware | BE-FILE-007/008, DOM-CAP (virus_scanner) | core | Scan status on files; detections | planned |
| ISO 27001 A.8.8 · CRA Annex I Part II | Technical vulnerabilities, vulnerability handling | SEC-VULN-001…009 | platform | Trivy reports, SBOMs, `SECURITY.md` | planned |
| ISO 27001 A.8.15–A.8.17 | Logging, monitoring, clock sync | SEC-OBS-001…008, SEC-AUD-003…006, SEC-BASE-009 | core, platform | Audit chain verification records | planned |
| ISO 27001 A.8.24 · NIS2 21(2)(h) | Cryptography | SEC-BASE-004/005, SEC-AUD-004/005, SEC-VULN-004 | platform | TLS config, encryption at rest, signatures | planned |
| ISO 27001 A.8.25–A.8.29 · CRA Annex I Part I | Secure development, testing | FND-CONF-001…006, DEL-CI-001…007, TST-STR-001…005 | all repos | CI results per release | planned |
| ISO 27001 A.8.32 | Change management | FND-GOV-*, DEL-REPO-005, DEL-CD-001…007 | all repos | PR history, deploy audit events | planned |
| ISO 27001 A.8.33 | Test information | BE-DATA-005/006, TST-DATA-003 | all apps | Seeds (synthetic) | planned |
| eIDAS · EN 9100 8.6 | Electronic signatures on release/approval | SEC-SIG-001…007 | core | Signature records | planned |
| EN 9100 8.5.2 | Identification and traceability | SEC-AUD-*, BE-FILE-009, SEC-SIG-003 | core | Audit trail, file hashes | planned |

## App-level rows

Added by each app (EN 9100 clauses 7.2, 8.1.2, 8.4, 8.7, 10.2; EN 9101, 9102, 9110, 9136, 9145;
EN 4179; ISO 14001, 45001, 50001 specifics).
