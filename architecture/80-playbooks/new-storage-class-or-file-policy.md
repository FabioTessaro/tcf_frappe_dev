# Playbook · New storage class or file policy

**New file policy (feature)**

1. Declare it in the slice's `files.py` with every field of the policy table
   ([208-files](../20-backend/208-files.md)) (`BE-FILE-005`).
2. External sources ⇒ `antivirus: required` unless an ADR says otherwise (`BE-FILE-007`).
3. Large files ⇒ `direct_transfer: true` (presigned multipart).
4. Upload through a feature endpoint (`BE-FILE-005`); add `test_files.py`.

**New storage class (deployment)**

1. Add the class and its bucket mapping in configuration (`BE-FILE-020`).
2. Create the bucket (dev: `bootstrap/templates/buckets.list`; production: provisioning).
3. Allow the class in the relevant Classification Levels (`DOM-CLS-005`).
4. Include the bucket in backups (`OPS-BAK-001`).
