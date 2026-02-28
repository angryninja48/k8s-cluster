# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-01)

**Core value:** OpenCode sessions and GitHub Copilot auth survive indefinitely and are accessible from any device via browser — no laptop dependency.
**Current focus:** Phase 1 — Foundation

## Current Position

Phase: 1 of 4 (Foundation)
Plan: 0 of 3 in current phase
Status: Ready to plan
Last activity: 2026-03-01 — Roadmap created (4 phases, 30 v1 requirements mapped)

Progress: [░░░░░░░░░░] 0%

## Performance Metrics

**Velocity:**
- Total plans completed: 0
- Average duration: -
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

**Recent Trend:**
- Last 5 plans: n/a
- Trend: n/a

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Pre-planning]: Doppler is the ONLY secrets provider — no SOPS for app secrets; all 6 vars must exist in Doppler before any ExternalSecret reconciles
- [Pre-planning]: `*.angryninja.cloud` wildcard does NOT cover `*.opencode.angryninja.cloud` — dedicated Certificate resource required
- [Pre-planning]: BackendTrafficPolicy for WebSocket must be co-deployed with HelmRelease in Phase 2 (not deferred to Phase 4)
- [Pre-planning]: One workspace validated before copying pattern to second (Phase 2 before Phase 3)

### Pending Todos

None yet.

### Blockers/Concerns

- **Phase 1**: Certificate Gateway integration — confirm whether `*.opencode.angryninja.cloud` cert is referenced at Gateway listener level or HTTPRoute TLS block (check if any existing app creates its own cert)
- **Phase 1**: Copilot `auth.json` Doppler encoding — confirm raw JSON vs. base64 works in ExternalSecret template before declaring Phase 1 complete

## Session Continuity

Last session: 2026-03-01
Stopped at: Roadmap created; no phases planned yet
Resume file: None
