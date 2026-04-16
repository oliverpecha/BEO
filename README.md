<div align="center">

# BEO — Bureau of External Operations

**A self-hosted, multi-tier Telegram AI assistant.**  
Routes every query through the cheapest viable model tier — semantic cache, live web lookups, headless scraping, and deep synthesis — all on a single 4 GB VPS.

[![License: MIT](https://img.shields.io/badge/License-MIT-teal.svg)](LICENSE)
[![Docker](https://img.shields.io/badge/Docker-Compose-blue?logo=docker)](docker-compose.yml)

</div>

---

## What is BEO?

📟 BEO (Bureau of Ethereal Operations) is a self-hosted multi-model routing layer built for OpenClaw. Instead of sending every query to one model through a provider with an incentive to maximize your spend, BEO routes each query to the cheapest model that can handle it.

## The Official Bureau Cast List

BEO operates via a distinct roster of specialized agents:

* 🎬 **The Director (OpenClaw):** The primary orchestration daemon that sits on the local node and autonomously determines operational Tiers.
* 🔑 **The Gatekeeper (LiteLLM):** The API proxy that enforces rate limits, failover logic, and manages promotional keys.
* 📚 **The Librarian (Redis):** The keeper of the semantic cache that serves identical previous queries instantly.
* 💼 **The Broker (Brave Search API):** A programmatic search index that trades real-time web snippets for fractions of a cent.
* 🏃 **The Minions (Gemini 3.1 Flash-Lite):** High-concurrency grunts that execute local parallel scraping and strip CSS/JS.
* 🔮 **The Oracle (Gemini 1.5 Pro):** A cloud-based model with a 2M-token vision used for deep synthesis of massive payloads.
* 🎙  **The MC (Gemini 3 Flash Preview):** The sassy front-end voice that processes logic and formats the final broadcast.
* 🏛️  **The Board (Claude 3 Opus):** The ultimate authority summoned exclusively via strict keyword rituals for existential overrides.

---

## The Ethereal Triage Protocol

Every inbound message passes through a pre-flight pipeline that enforces a strict escalation ladder:

| Tier | Name | Action | Target Cost |
|------|------|--------|-------------|
| 0 | 🧠 **The Brain** | Pure Logic: Handled by The MC directly from internal neural weights. | ~$0.00007 |
| 1 | 🗄️  **The Cabinet** | Redis Cache: Instant bypass of LLM generation for identical semantic queries. | $0.00 |
| 2 | 🗂️  **The Desk** | Quick Facts: Bypasses scraping, pays The Broker directly for a JSON snippet. | ~$0.0005 |
| 3 | 🗺️  **The Field** | General Browsing: Deploys Minions to locally scrape and strip HTML from specific URLs. | ~$0.01 |
| 4 | 🌀 **The Extraction** | Deep Research: Massive data payloads hoisted to The Oracle for deep synthesis. | ~$0.10 |
| 5 | 👑 **The VIP** | The Board: Bypasses The Director entirely via the `/opus` trigger. | $0.50+ |

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

# 2. Bootstrap — creates required host dirs and copies .env.example
./setup.sh

# 3. Fill in your keys
nano .env

# 4. Copy and adjust OpenClaw config
cp openclaw.json.example openclaw.json

# 5. Launch
docker compose up -d

# 6. Check logs
docker compose logs -f
```

> **Why `setup.sh`?** Git cannot track empty directories. `data/redis/` must exist on the host before Docker mounts it — otherwise Docker creates it as root and Redis fails to write. `setup.sh` creates it with correct ownership. Run it once after every fresh clone.

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
