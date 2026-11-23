# 209 · Workflows — PENDING

## Status

**PENDING.** The design is not decided. The constraints below are agreed and binding. Do not build
a workflow engine, workflow designer or approval framework beyond these constraints until the
decision is closed in [90-appendices/open-decisions](../90-appendices/open-decisions.md).

## Agreed constraints

- `BE-WF-001` Workflows MUST build on and extend Frappe's built-in Workflow engine
  (Workflow, Workflow State, Workflow Transition, Workflow Action).
- `BE-WF-002` The system MUST be usable for any doctype of any app; it MUST NOT be specific to one
  feature app.
- `BE-WF-003` Non-developers (e.g. process engineers) MUST be able to create and edit workflows
  without a release.
- `BE-WF-004` Workflow definitions are **controlled configuration**: every change MUST be audited
  ([SEC-AUD-001](../30-security-and-compliance/302-audit.md)); approval of workflow changes is to
  be decided.
- `BE-WF-005` Transitions MAY require an electronic signature with a declared meaning
  ([30-security-and-compliance/303-electronic-signatures](../30-security-and-compliance/303-electronic-signatures.md)).
- `BE-WF-006` Desk and the portal MUST apply transitions through one shared code path; the portal
  calls a feature API that delegates to that path.

## Interim rule

Until the design is closed, features needing state transitions SHOULD implement them in
`service.py` through `frappe.model.workflow.apply_workflow` when a Workflow exists for the doctype,
and keep the transition list minimal.
