<div align="center">

# BEO — Bureau of External Operations

**A self-hosted, multi-tier Telegram AI assistant.**  
Routes every query through the cheapest viable model tier — semantic cache, live web lookups, headless scraping, and deep synthesis — all on a single 4 GB VPS.

[![License: MIT](https://img.shields.io/badge/License-MIT-teal.svg)](LICENSE)
[![Docker](https://img.shields.io/badge/Docker-Compose-blue?logo=docker)](docker-compose.yml)

</div>

---

## What is BEO?

BEO is a personal AI assistant that lives in your Telegram — single-user, self-hosted, cost-aware.

Every inbound message passes through a pre-flight pipeline that decides the cheapest correct response path:

| Tier | Name | Triggers |
|------|------|----------|
| 0 | **The Cabinet** | Semantic cache hit — no LLM call at all |
| 1 | **The Brain** | Logic, code, writing, explanation |
| 2 | **The Desk** | Live lookups, current events, prices |
| 3 | **The Field** | 1–5 URLs — headless scrape + summarise |
| 4 | **The Oracle** | Deep synthesis across many sources |
| 5 | **The VIP** | `/opus` — highest-capability model |

Built on [OpenClaw](https://github.com/openclaw) + [LiteLLM](https://github.com/BerriAI/litellm) + Redis + Telegram long-polling, running on a single Hetzner VPS.

---

## Architecture

See [`docs/BLUEPRINT.md`](docs/BLUEPRINT.md) for the full engineering spec (BLU-01 → BLU-33).

```
Telegram ──► Pre-flight (lang detect + TLD + nano-classifier)
                    │
              Redis Semantic Cache (Tier 0)
                    │ miss
              LiteLLM (routing, budgets, rate limiting)
                    │
        ┌───────────┼──────────────┬──────────────┐
      Brain        Desk          Field          Oracle
   (Tier 1)     (Tier 2)      (Tier 3)        (Tier 4)
                mcp-search   mcp-firecrawl   multi-source
                                              synthesis
```

---

## Prerequisites

- A VPS with **4 GB RAM minimum** (Hetzner CAX11 or equivalent)
- Docker + Docker Compose installed
- A [Telegram bot token](https://core.telegram.org/bots/tutorial) from @BotFather
- At least one of:
  - [Google AI Studio](https://aistudio.google.com/) API key (free tier works)
  - [OpenRouter](https://openrouter.ai/) API key

---

## Quick Start

```bash
# 1. Clone
git clone https://github.com/YOUR_USERNAME/beo.git && cd beo

# 2. Copy and fill in your keys
cp .env.example .env
nano .env

# 3. Copy and adjust OpenClaw config
cp openclaw.json.example openclaw.json

# 4. Launch
docker compose up -d

# 5. Check logs
docker compose logs -f
```

---

## Configuration

All configuration lives in three files:

| File | Purpose |
|------|---------|
| `.env` | API keys and operational thresholds (never committed) |
| `litellm_config.yaml` | Model aliases, budgets, router strategy, semantic cache |
| `openclaw.json` | Agent definitions, approval policy, compaction settings |

See `.env.example` for all required variables with inline documentation.

---

## Deployment

BEO is designed for a single-node VPS. The deploy workflow is:

```bash
# On your VPS — after git clone and .env setup
docker compose up -d

# To update after a git push
git pull origin main && docker compose up -d --no-build
```

See [`docs/DEPLOY.md`](docs/DEPLOY.md) for the full VPS setup walkthrough.

---

## Roadmap

See [`CHECKLIST.md`](CHECKLIST.md) for the phased deployment roadmap (Phase 0 → Phase 6).

---

## License

MIT — see [LICENSE](LICENSE).
