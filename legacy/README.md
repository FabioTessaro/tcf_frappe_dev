# Legacy scripts (not working)

The previous generation of the lifecycle scripts, kept only as a reference for
the features that still have to be ported (`new-app.sh`, `check-env.sh`,
`setup-env.sh` and the frontend-pipeline helpers in `bootstrap/`).

**Do not run anything in this folder.** The scripts expect the old layout
(`.devcontainer/docker-compose.yml`, `bootstrap/*.sh`, old `.env` keys such
as `TCF_SITE_NAME` / `TCF_APPS`) and no longer work with the new structure
described in the main [README](../README.md).
