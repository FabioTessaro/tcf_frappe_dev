# 700 · Norms register

## Purpose

The norms and laws the platform targets. **Mandatory** norms MUST be supported (by the platform or
by apps, see the level column); **optional** norms are supported progressively as apps are added.

The platform is a **blank canvas**: core and the delivery pipeline satisfy the platform-level
norms from the first production release; apps add coverage of the others over time.

## Register

| Norm | Scope | Status | Level |
|---|---|---|---|
| EN 9100:2018 | Aerospace quality management system | **Mandatory** | Shared MS primitives + QMS apps |
| EN 9110 | QMS for aviation maintenance organisations | **Mandatory** | MRO / maintenance app |
| EN 9101 | Audit requirements for 9100-series certification | **Mandatory** | Shared MS primitives (internal audits) + evidence exports |
| EN 9102 | First Article Inspection | **Mandatory** | QMS app (with PLM, MES) |
| EN 9145 | APQP / PPAP for aerospace | **Mandatory** | QMS app (with PLM, suppliers via Party) |
| EN 9136 | Root cause analysis and problem solving | **Mandatory** | Shared MS primitives (nonconformity/CAPA) + QMS |
| EN 4179 | Qualification and approval of NDT personnel | **Mandatory** | Competence primitives + training/qualification app |
| NIS2 (Dir. (EU) 2022/2555 and national transposition) | Cybersecurity risk management and incident reporting | **Mandatory** | Platform |
| Cyber Resilience Act (Reg. (EU) 2024/2847) | Security of products with digital elements, vulnerability handling, SBOM | **Mandatory** | Platform (delivery pipeline, vulnerability handling) |
| ISO/IEC 27001:2022 + 27002:2022 | Information security management system and controls | **Mandatory** | Platform + shared MS primitives (ISMS) |
| ISO/IEC 27701 | Privacy information management | **Mandatory** | Platform (privacy service) |
| ISO 14001 | Environmental management system | **Mandatory** | Shared MS primitives + EMS app |
| ISO 45001 | Occupational health and safety management system | **Mandatory** | Shared MS primitives + OHS app |
| ISO 50001 | Energy management system | **Mandatory** | Shared MS primitives + EnMS app |
| ISO 15489-1 | Records management principles | **Mandatory** | Platform (records service) |
| ISO 16175 | Requirements for records in software | **Mandatory** | Platform (records service) |
| EN 9103 | Variation management of key characteristics | Optional | MES / QMS (SPC) |
| EN 9146 | Foreign object damage prevention | Optional | MES / QMS |
| Nadcap (PRI, AC7xxx + SAE AMS) | Special-process accreditation | Optional | MES / QMS / calibration |
| ISO 10007 | Configuration management | Optional | PLM |
| ISO 10012 | Measurement management systems | Optional | Calibration app |
| ISO/IEC 17025 | Testing and calibration laboratories | Optional | Calibration / lab app |
| ISO/IEC 27005 | Information security risk management | Optional | ISMS (risk register) |
| ISO 22301 | Business continuity | Optional | Operations (backup/restore already aligned) |

Laws that apply regardless of the target list and are already reflected in rules: GDPR (privacy),
eIDAS (signatures), labour law on employee monitoring (audit), EU dual-use and sanctions regulations
(classification, party screening) where applicable.

## Rules

- `CMP-REG-001` Changes to this register (adding a norm, changing status) are guide changes (minor
  version).
- `CMP-REG-002` Platform-level mandatory norms MUST be fully mapped in the traceability matrix and
  implemented before the first production release.
- `CMP-REG-003` A feature app claiming to cover a norm MUST add its rows to the traceability matrix
  and update the coverage roadmap.
