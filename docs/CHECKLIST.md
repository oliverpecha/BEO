# BEO Deployment Checklist

## Phase 0 — Bare-bones Brain over Telegram
- [x] BLU-01 — Single node Docker Compose topology
- [x] BLU-02 — Fix `api_base` to `http://litellm:4000/v1`
- [x] BLU-07 — Create `.env` from `.env.example`
- [x] BLU-08 — Keys via `env_file:` only, never volume-mounted

## Phase 1 — Persistence, volumes, and safety baseline
- [x] BLU-03 — Persistent volume mounts for all stateful services
- [x] BLU-04 — Redis AOF persistence (`--appendonly yes --appendfsync everysec`)
- [x] BLU-05 — Agent cold-start policy confirmed (no background agents)
- [x] BLU-25 — Constrained execution environment locked in `openclaw.json`

## Phase 2 — Pre-flight router and the Cabinet
- [ ] BLU-09 — Multilingual pre-flight (lingua + keywords.json)
- [ ] BLU-10 — Unified pre-flight pipeline (`preflight()` + `dispatch()`)
- [ ] BLU-16 — `tier-nano-router` alias in `litellm_config.yaml`
- [ ] BLU-17 — Semantic cache with `text-embedding-004`
- [ ] BLU-18 — Similarity threshold set to `0.92`
- [ ] BLU-19 — Cabinet `no_store` semantics per tier

## Phase 3 — Web tiers: Desk, Field, and Extraction
- [ ] BLU-11 — Tier 3 Field: `fetch_url()`, Minion spawning, token overflow check
- [ ] BLU-20 — Per-tier timeouts in LiteLLM config
- [ ] BLU-21 — Inter-agent payload passing (no temp files, no Redis intermediate)
- [ ] BLU-22 — Minion concurrency cap (`max_parallel_requests: 5`)

## Phase 4 — VIP Tier, MC charter, and MEMORY.md
- [ ] BLU-24 — Context window sync at startup
- [ ] BLU-23 — Compaction + memory flush block in `openclaw.json`
- [ ] BLU-29 — Multi-group session isolation verified
- [ ] BLU-30 — MC operational charter + railblock system prompt

## Phase 5 — Operations, alerts, and scaling thresholds
- [ ] BLU-12 — LiteLLM budget DB (`database_url` in config)
- [ ] BLU-13 — Gemini key rotation mechanics confirmed
- [ ] BLU-14 — Router strategy set (`simple-shuffle` → `least-busy`)
- [ ] BLU-15 — Per-key budget model configured
- [ ] BLU-31 — Self-alerting for budget overruns and OOM events
- [ ] BLU-32 — Nightly agent profile backup cron
- [ ] BLU-33 — Load scaling pressure points documented

## Phase 6 — Post-MVP niceties
- [ ] BLU-06 — Reverse proxy (Caddy/Nginx) if webhooks adopted
- [ ] BLU-26 — Voice pipeline (STT/TTS wrapper, API-based)
- [ ] BLU-27 — Multi-user design review
- [ ] BLU-28 — /opus user-ID allowlist
