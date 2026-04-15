#!/usr/bin/env bash
# BEO Phase 0 — Test Protocol v6
# Active stack:   ~/openclaw/docker-compose.yml
# Containers:     openclaw-gateway | beo-litellm | beo-redis
# DNS (service):  litellm | redis
# .env:           ~/openclaw/.env
# litellm_config: ~/beo/litellm_config.yaml (generated)
# No DATABASE_URL — stateless LiteLLM
# Run: bash ~/beo/beo_p0_test.sh

set -uo pipefail
PASS=0; FAIL=0; WARN=0

c_green='\033[0;32m'; c_red='\033[0;31m'; c_yellow='\033[1;33m'
c_bold='\033[1m'; c_reset='\033[0m'

pass() { echo -e "  ${c_green}✓${c_reset} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "  ${c_red}✗${c_reset} $1"; FAIL=$((FAIL + 1)); }
warn() { echo -e "  ${c_yellow}⚠${c_reset} $1"; WARN=$((WARN + 1)); }
hdr()  { echo -e "\n${c_bold}── $1 ──${c_reset}"; }

ENV_FILE=~/openclaw/.env
COMPOSE_FILE=~/openclaw/docker-compose.yml
LITELLM_CONFIG=~/beo/litellm_config.yaml
CTR_OPENCLAW=openclaw-gateway
CTR_LITELLM=beo-litellm
CTR_REDIS=beo-redis
SVC_LITELLM=litellm
SVC_REDIS=redis

hdr "L1 · .env sanity (BLU-07 / BLU-08)"
[[ -f "$ENV_FILE" ]] && pass ".env found at $ENV_FILE" || fail ".env missing at $ENV_FILE"
if [[ -f "$ENV_FILE" ]]; then
  for key in TELEGRAM_BOT_TOKEN TELEGRAM_OWNER_CHAT_ID LITELLM_MASTER_KEY; do
    val=$(grep -E "^${key}=" "$ENV_FILE" 2>/dev/null | cut -d= -f2- | xargs)
    [[ -n "$val" ]] && pass "$key is set" || fail "$key is empty or missing"
  done
  has_key=0
  for key in GEMINI_KEY_1 GEMINI_KEY_2 GEMINI_KEY_3 OPENROUTER_API_KEY; do
    val=$(grep -E "^${key}=" "$ENV_FILE" 2>/dev/null | cut -d= -f2- | xargs)
    if [[ -n "$val" ]]; then has_key=1; pass "$key is set (model key present)"; break; fi
  done
  [[ $has_key -eq 0 ]] && fail "No model key found (GEMINI_KEY_* or OPENROUTER_API_KEY)"
fi

hdr "L2 · Docker containers running (BLU-01)"
for ctr in "$CTR_OPENCLAW" "$CTR_LITELLM" "$CTR_REDIS"; do
  status=$(docker inspect --format '{{.State.Status}}' "$ctr" 2>/dev/null || echo "missing")
  health=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}}' "$ctr" 2>/dev/null || echo "n/a")
  if [[ "$status" == "running" ]]; then
    pass "$ctr running (health: $health)"
  elif [[ "$status" == "missing" ]]; then
    fail "$ctr not found — run: docker compose -f $COMPOSE_FILE up -d"
  else
    fail "$ctr state: $status"
  fi
done

hdr "L3 · Inter-container networking (BLU-02)"
nets_oc=$(docker inspect "$CTR_OPENCLAW" --format '{{json .NetworkSettings.Networks}}' 2>/dev/null \
  | python3 -c "import sys,json; print(' '.join(json.load(sys.stdin).keys()))" 2>/dev/null || echo "")
nets_ll=$(docker inspect "$CTR_LITELLM"  --format '{{json .NetworkSettings.Networks}}' 2>/dev/null \
  | python3 -c "import sys,json; print(' '.join(json.load(sys.stdin).keys()))" 2>/dev/null || echo "")
shared=""
for net in $nets_oc; do
  if echo "$nets_ll" | grep -qw "$net"; then shared="$net"; break; fi
done
if [[ -n "$shared" ]]; then
  pass "Shared Docker network: $shared"
else
  fail "No shared network — $CTR_OPENCLAW and $CTR_LITELLM cannot communicate"
  echo "       $CTR_OPENCLAW networks: $nets_oc"
  echo "       $CTR_LITELLM  networks: $nets_ll"
fi

node_test=$(docker exec "$CTR_OPENCLAW" node -e "
const h=require('http');
const r=h.get('http://${SVC_LITELLM}:4000/health/readiness',(res)=>{console.log('OK '+res.statusCode);res.destroy();});
r.on('error',(e)=>console.log('FAIL '+e.message));
r.setTimeout(3000,()=>{r.destroy();console.log('TIMEOUT');});
" 2>/dev/null || echo "EXEC_ERROR")
if echo "$node_test" | grep -q "^OK"; then
  pass "openclaw-gateway → ${SVC_LITELLM}:4000 reachable (HTTP OK)"
elif [[ "$node_test" == "EXEC_ERROR" ]]; then
  warn "Could not exec node in $CTR_OPENCLAW"
else
  fail "openclaw-gateway cannot reach ${SVC_LITELLM}:4000 — $node_test"
  echo "       Verify service name and shared network in ~/openclaw/docker-compose.yml"
fi

hdr "L4 · LiteLLM Gatekeeper health"
health_out=$(docker exec "$CTR_LITELLM" curl -sf http://localhost:4000/health/readiness 2>/dev/null \
  || docker exec "$CTR_LITELLM" python3 -c \
  "import urllib.request; print(urllib.request.urlopen('http://localhost:4000/health/readiness').read().decode())" \
  2>/dev/null || echo "FAIL")
echo "$health_out" | grep -qi "healthy\|status\|ok\|version" \
  && pass "LiteLLM /health/readiness OK" \
  || fail "LiteLLM health failed: $health_out"

hdr "L5 · litellm_config.yaml — tier-1-brain alias"
if [[ -f "$LITELLM_CONFIG" ]]; then
  pass "litellm_config.yaml exists"
  grep -q "tier-1-brain" "$LITELLM_CONFIG" \
    && pass "tier-1-brain alias present" \
    || fail "tier-1-brain missing — run ~/beo/generate_litellm_config.sh"
  grep -q "litellm_params" "$LITELLM_CONFIG" \
    && pass "litellm_params block present" \
    || warn "litellm_params block not found"
else
  fail "$LITELLM_CONFIG not found — run ~/beo/generate_litellm_config.sh"
fi

hdr "L6 · LiteLLM /v1/models — tier-1-brain live"
LKEY=$(grep -E "^LITELLM_MASTER_KEY=" "$ENV_FILE" | cut -d= -f2- | xargs)
models_out=$(docker exec "$CTR_LITELLM" curl -sf -H "Authorization: Bearer ${LKEY}" \
  http://localhost:4000/v1/models 2>/dev/null \
  || docker exec "$CTR_LITELLM" python3 -c \
  "import urllib.request; req=urllib.request.Request('http://localhost:4000/v1/models',headers={'Authorization':'Bearer ${LKEY}'}); print(urllib.request.urlopen(req).read().decode())" \
  2>/dev/null || echo "FAIL")
if echo "$models_out" | grep -q "tier-1-brain"; then
  pass "tier-1-brain live in /v1/models"
elif echo "$models_out" | grep -q '"data"'; then
  fail "LiteLLM responding but tier-1-brain not listed — restart litellm after running generate script"
else
  fail "Cannot reach /v1/models (response: ${models_out:0:80})"
fi

hdr "L7 · OpenClaw LiteLLM endpoint (BLU-02)"
api_base_env=$(docker exec "$CTR_OPENCLAW" sh -c 'echo "$LITELLM_API_BASE"' 2>/dev/null || echo "")
if [[ -n "$api_base_env" ]]; then
  if echo "$api_base_env" | grep -q "localhost"; then
    fail "LITELLM_API_BASE=$api_base_env — uses localhost (BLU-02 violation)"
    echo "       Must be: http://${SVC_LITELLM}:4000/v1"
  else
    pass "LITELLM_API_BASE=$api_base_env"
  fi
else
  warn "LITELLM_API_BASE env var not set in container — checking openclaw.json"
  json_raw=$(docker exec "$CTR_OPENCLAW" cat /home/node/.openclaw/openclaw.json 2>/dev/null || echo "FILE_NOT_FOUND")
  if [[ "$json_raw" == "FILE_NOT_FOUND" ]]; then
    fail "LITELLM_API_BASE not set and openclaw.json not found — endpoint not configured"
  else
    echo "       openclaw.json:"
    echo "$json_raw" | python3 -m json.tool 2>/dev/null | sed "s/^/         /" || echo "$json_raw" | sed "s/^/         /"
    echo "$json_raw" | grep -q "localhost" \
      && fail "openclaw.json endpoint uses localhost (BLU-02)" \
      || pass "openclaw.json exists and no localhost found"
  fi
fi

hdr "L8 · Redis Librarian ping"
redis_ping=$(docker exec "$CTR_REDIS" redis-cli ping 2>/dev/null || echo "FAIL")
[[ "$redis_ping" == "PONG" ]] && pass "Redis PONG" || fail "Redis not responding: $redis_ping"

hdr "L9 · Telegram token format"
if [[ -f "$ENV_FILE" ]]; then
  tok=$(grep -E "^TELEGRAM_BOT_TOKEN=" "$ENV_FILE" | cut -d= -f2- | xargs)
  if [[ "$tok" =~ ^[0-9]+:[A-Za-z0-9_-]{35}$ ]]; then
    pass "TELEGRAM_BOT_TOKEN format valid"
  elif [[ -z "$tok" ]]; then
    fail "TELEGRAM_BOT_TOKEN empty"
  else
    warn "TELEGRAM_BOT_TOKEN format unusual — verify with @userinfobot"
  fi
fi

# ── L10 · openclaw.json model prefix (new critical check) ───────
hdr "L10 · OpenClaw model prefix (must be litellm/, not openai/)"
prefix=$(docker exec openclaw-gateway node -e \
  "const c=require('/home/node/.openclaw/openclaw.json');
   console.log(c.agents.defaults.model.primary)" 2>/dev/null || echo "EXEC_ERROR")
if [[ "$prefix" == litellm/* ]]; then
  pass "model primary = $prefix (correct provider)"
elif [[ "$prefix" == openai/* ]]; then
  fail "model primary = $prefix — openai/ bypasses baseUrl, change to litellm/"
else
  warn "model primary = $prefix — verify provider routing"
fi

# ── L11 · models.providers.litellm.baseUrl present ──────────────
hdr "L11 · Custom litellm provider baseUrl"
baseurl=$(docker exec openclaw-gateway node -e \
  "const c=require('/home/node/.openclaw/openclaw.json');
   console.log(c?.models?.providers?.litellm?.baseUrl||'MISSING')" 2>/dev/null || echo "EXEC_ERROR")
if [[ "$baseurl" == *"litellm:4000"* ]]; then
  pass "models.providers.litellm.baseUrl = $baseurl"
elif [[ "$baseurl" == "MISSING" ]]; then
  fail "models.providers.litellm not defined in openclaw.json"
else
  warn "baseUrl = $baseurl — verify matches LiteLLM service name"
fi

# ── L12 · End-to-end: LiteLLM completes a real request ──────────
hdr "L12 · End-to-end: direct LiteLLM completion (host → litellm)"
LKEY=$(grep -E "^LITELLM_MASTER_KEY=" "$ENV_FILE" | cut -d= -f2- | xargs)
e2e_resp=$(curl -sf -X POST http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer ${LKEY}" \
  -H "Content-Type: application/json" \
  -d '{"model":"tier-1-brain","messages":[{"role":"user","content":"reply with the single word PASS"}],"max_tokens":5}' \
  2>/dev/null || echo "CURL_FAIL")
if echo "$e2e_resp" | grep -qi "PASS\|content\|choices"; then
  pass "LiteLLM completion OK — tier-1-brain responded"
elif [[ "$e2e_resp" == "CURL_FAIL" ]]; then
  fail "Cannot reach LiteLLM on port 4000 from host"
else
  fail "LiteLLM responded but unexpected output: ${e2e_resp:0:120}"
fi

echo ""
echo -e "${c_bold}══ Phase 0 Test Summary ══${c_reset}"
echo -e "  ${c_green}Passed: $PASS${c_reset}  |  ${c_red}Failed: $FAIL${c_reset}  |  ${c_yellow}Warnings: $WARN${c_reset}"
echo ""
if [[ $FAIL -eq 0 ]]; then
  echo -e "  ${c_green}${c_bold}✓ Phase 0 healthy. Run Telegram smoke tests.${c_reset}"
else
  echo -e "  ${c_red}${c_bold}✗ Fix failures before Telegram testing.${c_reset}"
fi


echo ""
echo -e "${c_bold}── Telegram Smoke Tests ──${c_reset}"
echo '  1. "Hello, are you there?"          → any coherent reply'
echo '  2. "What model are you running on?"  → model name from LiteLLM'
echo '  3. "What is 17 x 23?"               → 391'
echo '  4. docker compose -f ~/openclaw/docker-compose.yml restart && sleep 15'
echo '     then "ping" → confirms long-poll reconnects after restart'
echo ""
