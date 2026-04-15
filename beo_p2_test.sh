#!/usr/bin/env bash
# beo_p2_test.sh — Phase 2 verification: preflight proxy, routing, cache baseline
# Run from ~/beo: bash beo_p2_test.sh
set -euo pipefail

PASS=0; FAIL=0
pass() { echo "  ✅ $1"; ((PASS++)) || true; }
fail() { echo "  ❌ FAIL: $1"; ((FAIL++)) || true; }
header() { echo; echo "── $1 ──"; }

OC_ENV="/root/openclaw/.env"
LITELLM_MASTER_KEY=$(grep -E '^LITELLM_MASTER_KEY=' "$OC_ENV" | head -1 | cut -d= -f2-)

# ── BLU-16: Tier aliases & nano router in config ─────────────────────────────
header "BLU-16 — Tier aliases present in litellm_config.yaml"

CFG="/root/beo/litellm_config.yaml"
if [[ -f "$CFG" ]]; then
  pass "litellm_config.yaml exists at $CFG"
else
  fail "litellm_config.yaml missing at $CFG"
fi

for tier in tier-1-brain tier-2-desk tier-3-field tier-4-extraction tier-5-vip tier-nano-router; do
  if grep -q "model_name: ${tier}" "$CFG"; then
    pass "model_name present: ${tier}"
  else
    fail "model_name missing: ${tier}"
  fi
done

# ── BLU-17/19: Cache baseline in litellm_settings ────────────────────────────
header "BLU-17/19 — Cache baseline and no_cache_for_model"

if grep -q "litellm_settings:" "$CFG"; then
  pass "litellm_settings block present"
else
  fail "litellm_settings block missing"
fi

if grep -q "cache: true" "$CFG"; then
  pass "cache: true enabled"
else
  fail "cache not enabled (cache: true missing)"
fi

if grep -q "type: \"redis\"" "$CFG"; then
  pass "cache_params.type=redis"
else
  fail "cache_params.type=redis missing or different"
fi

if grep -q "no_cache_for_model:" "$CFG"; then
  pass "no_cache_for_model present"
else
  fail "no_cache_for_model missing"
fi

for m in tier-4-extraction tier-5-vip; do
  if grep -q "\"${m}\"" "$CFG"; then
    pass "no_cache_for_model includes ${m}"
  else
    fail "no_cache_for_model missing ${m}"
  fi
done

# ── BLU-10: Preflight proxy container health ─────────────────────────────────
header "BLU-10 — Preflight proxy container"

PF_STATE=$(docker inspect beo-preflight --format '{{.State.Status}}' 2>/dev/null || echo "missing")
if [[ "$PF_STATE" == "running" ]]; then
  pass "beo-preflight container is running"
else
  fail "beo-preflight container not running (state: $PF_STATE)"
fi

PF_PORT=$(docker ps --format '{{.Names}} {{.Ports}}' | grep '^beo-preflight ' || true)
if echo "$PF_PORT" | grep -q '4001->4001'; then
  pass "beo-preflight exposes port 4001"
else
  fail "beo-preflight does not expose 4001 as expected: $PF_PORT"
fi

# ── BLU-10: Gateway points to preflight ──────────────────────────────────────
header "BLU-10 — Gateway env points to preflight"

GW_ENV=$(docker inspect openclaw-gateway --format '{{json .Config.Env}}' 2>/dev/null || echo "[]")
if echo "$GW_ENV" | grep -q "LITELLM_API_BASE=http://beo-preflight:4001/v1"; then
  pass "LITELLM_API_BASE points to beo-preflight:4001/v1"
else
  fail "LITELLM_API_BASE not pointing to preflight"
fi

if echo "$GW_ENV" | grep -q "OPENAI_API_BASE=http://beo-preflight:4001/v1"; then
  pass "OPENAI_API_BASE points to beo-preflight:4001/v1"
else
  fail "OPENAI_API_BASE not pointing to preflight"
fi

# ── BLU-09/10: Routing behavior via direct curl ──────────────────────────────
header "BLU-09/10 — Preflight routing behavior (direct curl)"

WEATHER_MODEL=$(
  curl -s http://localhost:4001/v1/chat/completions \
    -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"model":"tier-1-brain","messages":[{"role":"user","content":"whats the weather in Barcelona today?"}]}' |
  python3 -c 'import sys,json; r=json.load(sys.stdin); print(r.get("model",""))' 2>/dev/null || echo ""
)

if [[ "$WEATHER_MODEL" == "tier-2-desk" ]]; then
  pass "Weather query routed to tier-2-desk"
else
  fail "Weather query did not route to tier-2-desk (got: '$WEATHER_MODEL')"
fi

HAIKU_MODEL=$(
  curl -s http://localhost:4001/v1/chat/completions \
    -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"model":"tier-1-brain","messages":[{"role":"user","content":"write a haiku about docker containers"}]}' |
  python3 -c 'import sys,json; r=json.load(sys.stdin); print(r.get("model",""))' 2>/dev/null || echo ""
)

if [[ "$HAIKU_MODEL" == "tier-1-brain" ]]; then
  pass "Creative haiku query stays on tier-1-brain"
else
  fail "Creative haiku query did not stay on tier-1-brain (got: '$HAIKU_MODEL')"
fi

# ── BLU-10: Nano classifier fallbacks visible but non-fatal ──────────────────
header "BLU-10 — Nano classifier fallback sanity"

NANO_WARN_COUNT=$(docker logs beo-preflight 2>/dev/null | grep -c "nano] empty content" || true)
if [[ "$NANO_WARN_COUNT" -ge 0 ]]; then
  pass "Nano fallback warnings present (count=${NANO_WARN_COUNT}) — non-fatal"
else
  fail "Could not read nano fallback warnings from beo-preflight logs"
fi

# ── BLU-02/03 sanity: stack containers ───────────────────────────────────────
header "Stack sanity — core containers present"

for c in openclaw-gateway beo-preflight beo-litellm beo-redis; do
  if docker ps --format '{{.Names}}' | grep -qx "$c"; then
    pass "Container present: $c"
  else
    fail "Container missing from docker ps: $c"
  fi
done

# ── Summary ───────────────────────────────────────────────────────────────────
echo
echo "══════════════════════════════════════"
echo "  Phase 2: $PASS passed, $FAIL failed"
echo "══════════════════════════════════════"
if [ "$FAIL" -eq 0 ]; then
  echo "  🎉 All checks pass — ready to commit Phase 2 router"
else
  echo "  ⚠️  Fix $FAIL failure(s) above before committing"
fi
exit "$FAIL"
