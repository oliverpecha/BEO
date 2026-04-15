#!/usr/bin/env bash
# beo_p1_test.sh — Phase 1 verification: persistence, volumes, cold-start, constraints
# Run from ~/beo: bash beo_p1_test.sh
set -euo pipefail

PASS=0; FAIL=0
pass() { echo "  ✅ $1"; ((PASS++)) || true; }
fail() { echo "  ❌ FAIL: $1"; ((FAIL++)) || true; }
header() { echo; echo "── $1 ──"; }

# ── BLU-03: Persistent volume mounts ─────────────────────────────────────────
header "BLU-03 — Persistent volume mounts"

check_mount() {
  local ctr="$1" pattern="$2"
  if docker inspect "$ctr" 2>/dev/null | python3 -c \
    "import sys,json
mounts = [m['Source'] for c in json.load(sys.stdin) for m in c.get('Mounts',[])]
print('\n'.join(mounts))" | grep -q "$pattern"; then
    pass "$ctr mounts $pattern"
  else
    fail "$ctr missing mount: $pattern"
  fi
}

check_mount "openclaw-gateway" ".openclaw"
check_mount "openclaw-gateway" "workspace"
check_mount "openclaw-gateway" "gog"
check_mount "beo-redis"        "beo/data/redis"
check_mount "beo-litellm"      "litellm_config.yaml"

[ -d /root/beo/data/redis ] \
  && pass "Host dir exists: /root/beo/data/redis" \
  || fail "Missing: /root/beo/data/redis"

# ── BLU-04: Redis AOF ─────────────────────────────────────────────────────────
header "BLU-04 — Redis AOF persistence"

AOF=$(docker exec beo-redis redis-cli CONFIG GET appendonly 2>/dev/null | tail -1)
[ "$AOF" = "yes" ] && pass "appendonly=yes" || fail "appendonly not set (got: '$AOF')"

FSYNC=$(docker exec beo-redis redis-cli CONFIG GET appendfsync 2>/dev/null | tail -1)
[ "$FSYNC" = "everysec" ] && pass "appendfsync=everysec" || fail "appendfsync wrong (got: '$FSYNC')"

AOF_DIR_SIZE=$(docker exec beo-redis sh -c "ls /data/ 2>/dev/null" | wc -l)
[ "$AOF_DIR_SIZE" -gt 0 ] \
  && pass "Redis /data has files (AOF initialised)" \
  || fail "Redis /data is empty — no writes yet"

# ── BLU-05: Cold-start policy ────────────────────────────────────────────────
header "BLU-05 — Agent cold-start policy"

INFRA_PATTERN="^(openclaw-gateway|beo-litellm|beo-redis)$"
EXTRA=$(docker ps --format "{{.Names}}" | grep -vE "$INFRA_PATTERN" || true)
if [ -z "$EXTRA" ]; then
  pass "No rogue agent containers running"
else
  fail "Unexpected containers running: $EXTRA"
fi

CLI_UP=$(docker ps --format "{{.Names}}" | grep -c "openclaw-cli" || true)
[ "$CLI_UP" -eq 0 ] \
  && pass "openclaw-cli is stopped (cold-start confirmed)" \
  || fail "openclaw-cli is persistently running — review restart policy"

ALWAYS=$(grep "restart: always" ~/openclaw/docker-compose.yml 2>/dev/null || true)
[ -z "$ALWAYS" ] \
  && pass "No restart:always found in compose" \
  || fail "restart:always found — check: $ALWAYS"

# ── BLU-25: openclaw.json constraints ────────────────────────────────────────
header "BLU-25 — Constrained execution environment"

OC_JSON="/root/.openclaw/openclaw.json"
[ -f "$OC_JSON" ] && pass "openclaw.json exists" || { fail "openclaw.json not found"; exit 1; }

# File permissions — doctor flagged this
PERMS=$(stat -c "%a" "$OC_JSON")
[ "$PERMS" = "600" ] \
  && pass "openclaw.json chmod 600" \
  || fail "openclaw.json permissions are $PERMS (want 600 — run: chmod 600 $OC_JSON)"

python3 - "$OC_JSON" << 'PYEOF'
import json, sys
c = json.load(open(sys.argv[1]))
results = []

def chk(label, ok): results.append((label, ok))

# sandbox off — real cold-start enforcement
sandbox = c.get("agents",{}).get("defaults",{}).get("sandbox",{}).get("mode","MISSING")
chk("agents.defaults.sandbox.mode=off", sandbox == "off")

# denyCommands — real execution constraint mechanism in this schema version
deny = c.get("gateway",{}).get("nodes",{}).get("denyCommands",[])
chk("gateway.nodes.denyCommands non-empty", len(deny) > 0)
for cmd in ["camera.snap", "screen.record", "sms.send"]:
    chk(f"denyCommands includes {cmd}", cmd in deny)

# litellm tiers declared
model_ids = [m.get("id") for m in
    c.get("models",{}).get("providers",{}).get("litellm",{}).get("models",[])]
for tier in ["tier-1-brain", "tier-2-desk", "tier-nano-router"]:
    chk(f"litellm model declared: {tier}", tier in model_ids)

# primary model routes through litellm (not a direct provider)
primary = c.get("agents",{}).get("defaults",{}).get("model",{}).get("primary","")
chk("primary model routes via litellm/", primary.startswith("litellm/"))

# fallback declared
fallbacks = c.get("agents",{}).get("defaults",{}).get("model",{}).get("fallbacks",[])
chk("at least one fallback model declared", len(fallbacks) > 0)

for label, ok in results:
    print(f"  {'✅' if ok else '❌ FAIL:'} {label}")

sys.exit(sum(1 for _, ok in results if not ok))
PYEOF
PY_FAILS=$?
PY_TOTAL=9
PASS=$((PASS + (PY_TOTAL - PY_FAILS)))
FAIL=$((FAIL + PY_FAILS))

# ── Summary ───────────────────────────────────────────────────────────────────
echo
echo "══════════════════════════════════════"
echo "  Phase 1: $PASS passed, $FAIL failed"
echo "══════════════════════════════════════"
if [ "$FAIL" -eq 0 ]; then
  echo "  🎉 All checks pass — ready to commit Phase 1"
else
  echo "  ⚠️  Fix $FAIL failure(s) above before committing"
fi
exit "$FAIL"
