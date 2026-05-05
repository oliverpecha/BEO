"""
BEO Preflight Proxy — BLU-10
OpenAI-compatible proxy on :4001 — runs preflight, rewrites model, handles caching & metrics.
"""
import os, json, re, logging, urllib.request, time, copy
import httpx
from datetime import datetime
from fastapi import FastAPI, Request, Response
from fastapi.responses import StreamingResponse

from preflight import preflight, TIER_ALIASES
from metrics import write_merged_payload, append_to_csv, update_monthly_stats_md, metrics_router

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("beo.proxy")

LITELLM_URL  = os.environ.get("LITELLM_URL", "http://litellm:4000")
LITELLM_KEY  = os.environ.get("LITELLM_MASTER_KEY", "")
TLD_CACHE    = os.environ.get("TLD_CACHE_PATH", "/root/.openclaw/tlds.txt")
TLD_REFRESH  = int(os.environ.get("TLD_REFRESH_DAYS", 30))
NANO_MODEL   = "tier-nano"

app = FastAPI(title="BEO Preflight Proxy")
app.include_router(metrics_router)

def load_tlds() -> set[str]:
    needs = not os.path.exists(TLD_CACHE) or time.time() - os.path.getmtime(TLD_CACHE) > TLD_REFRESH * 86400
    if needs:
        try:
            with urllib.request.urlopen("https://data.iana.org/TLD/tlds-alpha-by-domain.txt", timeout=5) as r:
                os.makedirs(os.path.dirname(TLD_CACHE), exist_ok=True)
                with open(TLD_CACHE, "w") as f: f.write(r.read().decode("utf-8"))
        except Exception: pass
    if not os.path.exists(TLD_CACHE): return {"com", "org", "net", "de", "it", "fr", "es", "uk", "jp", "br", "ru"}
    with open(TLD_CACHE) as f: return {l.strip().lower() for l in f if l.strip() and not l.startswith("#")}

_TLDS = load_tlds()
_URL_ROUGH = re.compile(r'(?:https?://[^\s]+)|(?:www\.[a-zA-Z0-9\-]+\.[a-zA-Z]{2,}[^\s]*)|(?:[a-zA-Z0-9][a-zA-Z0-9\-]*(?:\.[a-zA-Z]{2,})+(?:/[^\s]*)?)', re.IGNORECASE)

def extract_urls(text: str) -> list[str]:
    return [c for c in _URL_ROUGH.findall(text) if re.sub(r'^https?://', '', c).split('/')[0].rsplit('.', 1)[-1].lower() in _TLDS]

async def nano_classify(text: str, client: httpx.AsyncClient) -> tuple[int, bool]:
    payload = {"model": NANO_MODEL, "max_tokens": 32, "temperature": 0.1, "messages": [
        {"role": "system", "content": 'Classify query. ONLY JSON: {"tier":1} for logic/code/creative. {"tier":2} for live/current data.'},
        {"role": "user", "content": text[:500]}
    ]}
    try:
        r = await client.post(f"{LITELLM_URL}/v1/chat/completions", json=payload, headers={"Authorization": f"Bearer {LITELLM_KEY}"}, timeout=8.0)
        tier = json.loads((r.json().get("choices", [{}])[0].get("message", {}).get("content") or "").strip()).get("tier", 1)
        return tier if tier in (1, 2) else 1, (tier == 2)
    except Exception: return 1, False

def optimize_payload_for_caching(body: dict) -> None:
    messages = body.get("messages", [])
    if messages and messages[0].get("role") == "system":
        sys_text = messages[0].get("content", "")
        boundary = "<!-- OPENCLAW_CACHE_BOUNDARY -->"
        if boundary in sys_text:
            static_part, dynamic_part = sys_text.split(boundary, 1)
            messages[0]["content"] = static_part.strip()
            if "Conversation info (untrusted metadata):" in dynamic_part:
                dynamic_part = dynamic_part.split("Conversation info (untrusted metadata):")[0]
            user_msgs = [m for m in messages if m.get("role") == "user"]
            if user_msgs:
                target_msg = user_msgs[-1]
                orig_content = target_msg.get("content", "")
                injection = f"[Dynamic Runtime Context]\n{dynamic_part.strip()}\n\n"
                if isinstance(orig_content, str): target_msg["content"] = injection + orig_content
                elif isinstance(orig_content, list): target_msg["content"].insert(0, {"type": "text", "text": injection})

@app.api_route("/{path:path}", methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"])
async def proxy(request: Request, path: str):
    body_bytes = await request.body()
    is_chat = request.method == "POST" and "chat/completions" in path
    
    if is_chat:
        try: body = json.loads(body_bytes)
        except Exception: body = {}

        stream = body.get("stream", False)
        if stream: body["stream_options"] = {"include_usage": True}

        now = datetime.now()
        dump_dir = f"/root/.openclaw/payloads/{now.strftime('%Y/%m/%d')}"
        time_str = now.strftime("%Y_%m_%d_@%H_%M_%S_UTC")
        os.makedirs(dump_dir, exist_ok=True)

        raw_body = copy.deepcopy(body)

        messages = body.get("messages", [])
        user_msgs = [m for m in messages if m.get("role") == "user"]
        text = user_msgs[-1].get("content", "") if user_msgs else ""
        if isinstance(text, list): text = " ".join(p.get("text", "") for p in text if isinstance(p, dict))

        urls = extract_urls(text)
        files = len([m for m in messages if isinstance(m.get("content"), list) and any(p.get("type") in ("image_url", "file") for p in m["content"])])

        async with httpx.AsyncClient() as client:
            tier, no_store = preflight(text, attachments=files, urls=urls)
            if tier is None: tier, no_store = await nano_classify(text, client)

            model = TIER_ALIASES.get(tier, "tier-1-brain")
            body["model"] = model
            if no_store:
                body.setdefault("cache", {})
                body["cache"]["no-cache"] = body["cache"]["no-store"] = True

            is_optimized = False
            if os.environ.get("BEO_OPTIMIZE_PAYLOAD", "false").lower() == "true": 
                optimize_payload_for_caching(body)
                is_optimized = True
                
            opt_body = copy.deepcopy(body)
            body_bytes = json.dumps(body).encode()

    async with httpx.AsyncClient() as client:
        fwd_headers = {k: v for k, v in request.headers.items() if k.lower() not in ("host", "content-length")}
        if LITELLM_KEY: fwd_headers["authorization"] = f"Bearer {LITELLM_KEY}"

        start_time = time.time()
        r = await client.request(method=request.method, url=f"{LITELLM_URL}/{path}", headers=fwd_headers, content=body_bytes, params=request.query_params, timeout=300.0)
        latency = time.time() - start_time

        if is_chat:
            inbound_text = r.content.decode('utf-8', errors='replace')
            
            usage_data = {}
            req_id = ""
            real_model = ""
            output_text = ""
            tools_used_list = []
            
            if stream:
                for line in inbound_text.splitlines():
                    if line.startswith('data: ') and line != 'data: [DONE]':
                        try:
                            chunk = json.loads(line[6:])
                            if 'id' in chunk and not req_id: req_id = chunk['id']
                            if 'model' in chunk and not real_model: real_model = chunk['model']
                            if 'usage' in chunk: usage_data = chunk['usage']
                            
                            delta = chunk.get('choices', [{}])[0].get('delta', {})
                            if 'content' in delta and delta['content']:
                                output_text += delta['content']
                            if 'tool_calls' in delta:
                                for tc in delta['tool_calls']:
                                    fname = tc.get('function', {}).get('name')
                                    if fname and fname not in tools_used_list: tools_used_list.append(fname)
                        except: pass
            else:
                try: 
                    resp_json = json.loads(inbound_text)
                    req_id = resp_json.get('id', '')
                    real_model = resp_json.get('model', '')
                    usage_data = resp_json.get('usage', {})
                    output_text = resp_json.get('choices', [{}])[0].get('message', {}).get('content', '')
                    
                    tcs = resp_json.get('choices', [{}])[0].get('message', {}).get('tool_calls', [])
                    for tc in tcs:
                        fname = tc.get('function', {}).get('name')
                        if fname and fname not in tools_used_list: tools_used_list.append(fname)
                except: pass
                
            if not req_id: req_id = time_str
            if not real_model: real_model = "Unknown"
            tools_used_str = ", ".join(tools_used_list) if tools_used_list else ""
            skills_used_str = "" # Can be populated if skills are passed in headers/system prompt

            if os.environ.get("BEO_LOG_PAYLOAD", "false").lower() == "true": 
                write_merged_payload(dump_dir, time_str, req_id, raw_body, opt_body, inbound_text, model, real_model, latency, usage_data, text, output_text, tools_used_str, skills_used_str, is_optimized)
            
            append_to_csv(time_str, req_id, model, real_model, latency, usage_data, text, output_text, tools_used_str, skills_used_str)
            update_monthly_stats_md()

        if is_chat and stream:
            return StreamingResponse(content=iter([r.content]), status_code=r.status_code, media_type='text/event-stream', headers={k: v for k, v in r.headers.items() if k.lower() not in ('content-length', 'transfer-encoding')})

        return Response(content=r.content, status_code=r.status_code, headers={k: v for k, v in r.headers.items() if k.lower() != 'content-length'}, media_type=r.headers.get('content-type'))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=4001, log_level="info")
