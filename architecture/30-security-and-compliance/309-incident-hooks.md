# 309 · Security incident support

## Purpose

What the platform provides so the organisation can meet NIS2 and CRA reporting obligations. The
incident-management *process* is organisational; this chapter defines the technical support.

## Rules

- `SEC-INC-001` Core MUST provide a **Security Incident** record (doctype) with: detection time,
  classification of severity, affected systems and data, whether personal data is involved, and
  the reporting milestones: early warning (≤ 24 h), notification (≤ 72 h), final report (≤ 1 month)
  for NIS2, and the CRA reporting milestones for actively exploited vulnerabilities in products
  with digital elements.
- `SEC-INC-002` Automated detectors (audit chain mismatch, anomaly alerts, antivirus detections,
  repeated authentication failures) MUST create incident candidates for triage.
- `SEC-INC-003` Incident records, their timeline and evidence are records with retention class
  `security_incident` and are audit-protected.
- `SEC-INC-004` A personal-data breach flag MUST trigger the GDPR 72-hour notification workflow
  task for the privacy officer.

## Compliance links

NIS2 Art. 23; CRA Art. 14; GDPR Art. 33–34; ISO 27001 A.5.24–A.5.28.
