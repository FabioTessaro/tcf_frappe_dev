# 701 · Management-system model

## Purpose

Most mandatory norms are ISO management-system standards sharing the **Harmonized Structure**
(clauses 4–10): ISO 9001 (base of EN 9100), ISO 14001, ISO 45001, ISO 50001, ISO 27001 (extended by
ISO 27701). Their common requirements are implemented **once** as shared primitives and reused.

## Shared primitives

| HS clause | Primitive | Reused by |
|---|---|---|
| 4 Context, interested parties | Context and interested-party registers (linked to Party) | All |
| 5 Leadership | Policies, roles and responsibilities as controlled documents | All |
| 6 Risks, opportunities, objectives | Risk register, objectives with KPIs and plans | All (ISO 27005-style risk when added) |
| 7.2 Competence | Competence and qualification records (exposed via `competence_registry`) | QMS, EN 4179, Nadcap, ISO 45001 |
| 7.5 Documented information | Document control (versions, review, approval, distribution) on the records service | All; ISO 15489/16175 |
| 9.1 Monitoring and measurement | KPIs, measurements | All |
| 9.2 Internal audit | Audit programmes, audits, findings, evidence | All; EN 9101 |
| 9.3 Management review | Reviews with inputs and outputs | All |
| 10.2 Nonconformity and corrective action | NCR / CAPA with root cause analysis | QMS (EN 9136), 14001, 45001, 27001 incidents |

## Where the primitives live — PENDING

Recommended: a **foundation app** `<ims-app>` (integrated management system) that norm-specific apps
depend on (tier 2). Core stays free of business data ([DOM-CORE-001](../02-domain-foundations/20-core-primitives.md)).
Until the decision is closed, no shared-primitive doctypes may be created in core or in any feature
app.

## Rules (binding regardless of where the primitives live)

- `CMP-MS-001` Each primitive MUST exist once on the platform; norm apps MUST NOT create their own
  audit, NCR/CAPA, document-control, risk or competence doctypes.
- `CMP-MS-002` Each record of a shared primitive MUST carry the management system(s) it belongs to
  (e.g. `QMS`, `EMS`, `OHS`, `EnMS`, `ISMS`, `PIMS`) so it can be filtered per standard or viewed
  as an integrated system. Management systems are data.
- `CMP-MS-003` Norm apps add only norm-specific doctypes (e.g. FAI reports for EN 9102, APQP
  elements for EN 9145, environmental aspects for ISO 14001, hazards for ISO 45001, significant
  energy uses for ISO 50001).
