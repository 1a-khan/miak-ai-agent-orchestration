# Changelog

## [Unreleased] — 2026-05-01

### Fixed

- TelegramPoller no longer crashes the whole app on network errors (DNS blips, timeouts) — errors are now caught, poller backs off 5 seconds and retries silently without crashing the GenServer
- Supervisor `max_restarts` raised from 3 to 20 within a 60s window, giving agents more room to recover from transient failures before the app shuts down

### Added

- `Grafana.push_error/2` — pushes error events to Loki with `type="error"` label; TelegramPoller network errors now appear in Grafana with component and reason fields
- `docker-compose.yml` — defines `postgres` (postgres:16-alpine with healthcheck + named volume) and `app` services so the full stack can be started with a single command locally or via Coolify Docker Compose deploy; `DB_HOST` is pre-wired to the postgres service name so no manual config is needed
