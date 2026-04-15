"""
BEO Preflight Proxy — BLU-10
OpenAI-compatible proxy on :4001 — runs preflight, rewrites model, forwards to LiteLLM.
"""
import os, json, re, logging, urllib.request, time
import httpx
from fastapi import FastAPI, Request, Response
from fastapi.responses import StreamingResponse
import asyncio

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("beo.proxy")

LITELLM_URL  = os.environ.get("LITELLM_URL", "http://litellm:4000")
LITELLM_KEY  = os.environ.get("LITELLM_MASTER_KEY", "")
TLD_CACHE    = os.environ.get("TLD_CACHE_PATH", "/root/.openclaw/tlds.txt")
TLD_REFRESH  = int(os.environ.get("TLD_REFRESH_DAYS", 30))
NANO_MODEL   = "tier-nano-router"

from preflight import preflight, detect_language, TIER_ALIASES

app = FastAPI(title="BEO Preflight Proxy")

# ── TLD loader ────────────────────────────────────────────────────────────────
def load_tlds() -> set[str]:
    needs = (
        not os.path.exists(TLD_CACHE)
        or time.time() - os.path.getmtime(TLD_CACHE) > TLD_REFRESH * 86400
    )
    if needs:
        try:
            with urllib.request.urlopen(
                "https://data.iana.org/TLD/tlds-alpha-by-domain.txt", timeout=5
            ) as r:
                raw = r.read().decode("utf-8")
            os.makedirs(os.path.dirname(TLD_CACHE), exist_ok=True)
            with open(TLD_CACHE, "w") as f:
                f.write(raw)
            logger.info("[BEO] TLD cache refreshed")
        except Exception as e:
            logger.warning(f"[BEO] TLD fetch failed: {e}")
    if not os.path.exists(TLD_CACHE):
        return {"com", "org", "net", "de", "it", "fr", "es", "uk", "jp", "br", "ru"}
    with open(TLD_CACHE) as f:
        return {l.strip().lower() for l in f if l.strip() and not l.startswith("#")}

_TLDS = load_tlds()

_URL_ROUGH = re.compile(
    r'(?:https?://[^\s]+)'
    r'|(?:www\.[a-zA-Z0-9\-]+\.[a-zA-Z]{2,}[^\s]*)'
    r'|(?:[a-zA-Z0-9][a-zA-Z0-9\-]*(?:\.[a-zA-Z]{2,})+(?:/[^\s]*)?)',
    re.IGNORECASE
)

def extract_urls(text: str) -> list[str]:
    candidates = _URL_ROUGH.findall(text)
    validated = []
    for c in candidates:
        domain = re.sub(r'^https?://', '', c).split('/')[0]
        tld = domain.rsplit('.', 1)[-1].lower()
        if tld in _TLDS:
            validated.append(c)
    return validated


# ── Nano classifier ───────────────────────────────────────────────────────────
async def nano_classify(text: str, client: httpx.AsyncClient) -> tuple[int, bool]:
     
    payload = {
        "model": NANO_MODEL,
        "max_tokens": 32,
        "temperature": 0.1,
        "messages": [
            {
                "role": "system",
                "content": (
                    "Classify the user query. Reply with ONLY this JSON — no explanation:\n"
                    '{"tier":1} if the query is about logic, code, writing, math, or creative tasks.\n'
                    '{"tier":2} if the query needs current data: prices, weather, scores, news, live status.'
                )
            },
            {"role": "user", "content": text[:500]}
        ]
    }
    try:
        r = await client.post(
            f"{LITELLM_URL}/v1/chat/completions",
            json=payload,
            headers={"Authorization": f"Bearer {LITELLM_KEY}"},
            timeout=8.0
        )
        logger.debug(f"[nano] raw response: {r.text[:200]}")
        resp_json = r.json()
        content = (resp_json.get("choices", [{}])[0]
                   .get("message", {})
                   .get("content") or "")

        content = content.strip()
        if not content:
            logger.warning("[nano] empty content — falling back to tier 1")
            return 1, False
        tier = json.loads(content).get("tier", 1)        
        tier = tier if tier in (1, 2) else 1
        logger.info(f"[nano] → tier {tier}")
        return tier, (tier == 2)
    except Exception as e:
        logger.warning(f"[nano] classifier failed ({e}) — falling back to tier 1")
        return 1, False


# ── Main proxy handler ────────────────────────────────────────────────────────
@app.api_route("/{path:path}", methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"])
async def proxy(request: Request, path: str):
    body_bytes = await request.body()

    # Only intercept chat/completions POST — pass everything else through
    if request.method == "POST" and "chat/completions" in path:
        try:
            body = json.loads(body_bytes)
        except Exception:
            body = {}

        # Extract text from last user message
        messages  = body.get("messages", [])
        user_msgs = [m for m in messages if m.get("role") == "user"]
        text      = user_msgs[-1].get("content", "") if user_msgs else ""
        if isinstance(text, list):   # multimodal content blocks
            text = " ".join(p.get("text", "") for p in text if isinstance(p, dict))

        urls  = extract_urls(text)
        files = len([m for m in messages if isinstance(m.get("content"), list)
                     and any(p.get("type") in ("image_url", "file") for p in m["content"])])

        async with httpx.AsyncClient() as client:
            tier, no_store = preflight(text, attachments=files, urls=urls)

            if tier is None:
                tier, no_store = await nano_classify(text, client)

            model = TIER_ALIASES.get(tier, "tier-1-brain")
            logger.info(f"[preflight] tier={tier} model={model} no_store={no_store} "
                        f"chars={len(text)} urls={len(urls)} files={files}")

            body["model"] = model
            if no_store:
                body.setdefault("cache", {})
                body["cache"]["no-cache"] = True
                body["cache"]["no-store"] = True

            body_bytes = json.dumps(body).encode()

        # Forward to LiteLLM
        headers = dict(request.headers)
        headers["content-length"] = str(len(body_bytes))

    async with httpx.AsyncClient() as client:
        fwd_headers = {
            k: v for k, v in request.headers.items()
            if k.lower() not in ("host", "content-length")
        }
        if LITELLM_KEY:
            fwd_headers["authorization"] = f"Bearer {LITELLM_KEY}"

        stream = request.method == "POST" and body.get("stream", False) \
            if request.method == "POST" and "chat/completions" in path else False

        r = await client.request(
            method=request.method,
            url=f"{LITELLM_URL}/{path}",
            headers=fwd_headers,
            content=body_bytes,
            params=request.query_params,
            timeout=300.0
        )

        return Response(
            content=r.content,
            status_code=r.status_code,
            headers=dict(r.headers),
            media_type=r.headers.get("content-type")
        )


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=4001, log_level="info")
