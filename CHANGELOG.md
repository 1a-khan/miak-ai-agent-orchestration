## [Unreleased] — 2026-05-01

### Added
- `docker-compose.yml` — defines `postgres` (postgres:16-alpine with healthcheck + named volume) and `app` services so the full stack can be started with a single command locally or via Coolify Docker Compose deploy; `DB_HOST` is pre-wired to the postgres service name so no manual config is needed
