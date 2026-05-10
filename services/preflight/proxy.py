import os, json, logging, time, httpx, asyncio, re
from datetime import datetime
from fastapi import FastAPI, Request, Response
from fastapi.responses import StreamingResponse
from preflight import TIER_ALIASES, preflight
from metrics import write_merged_payload, append_to_csv, update_monthly_stats_md, metrics_router

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("beo.proxy")

app = FastAPI(title="BEO Preflight Proxy")
app.include_router(metrics_router)

LITELLM_URL = os.environ.get("LITELLM_URL", "http://litellm:4000")
LITELLM_KEY = os.environ.get("LITELLM_MASTER_KEY", "")

limits = httpx.Limits(max_keepalive_connections=50, max_connections=100)
http_client = httpx.AsyncClient(timeout=300.0, limits=limits)

async def process_log(content_bytes, dump_dir, time_str, raw_body, meta, is_opt, model, user_prompt):
    try:
        inbound_text = content_bytes.decode('utf-8', errors='replace')
        req_id, output_text, usage, turn_token, tools_used = "", "", {}, "N/A", []
        
        for line in inbound_text.splitlines():
            if line.startswith('data: ') and line != 'data: [DONE]':
                try:
                    j = json.loads(line[6:])
                    if 'id' in j and not req_id: req_id = j['id']
                    if 'usage' in j: usage = j['usage']
                    if 'turnToken' in j: turn_token = j['turnToken']
                    
                    delta = j.get('choices', [{}])[0].get('delta', {})
                    if 'content' in delta and delta['content']: output_text += delta['content']
                    
                    for tc in delta.get('tool_calls', []):
                        fname = tc.get('function', {}).get('name')
                        if fname and fname not in tools_used: tools_used.append(fname)
                except: pass
                
        if not req_id:
            try:
                j = json.loads(inbound_text)
                req_id = j.get('id', '')
                if 'turnToken' in j: turn_token = j['turnToken']
                if 'usage' in j: usage = j['usage']
                output_text = j.get('choices', [{}])[0].get('message', {}).get('content', '')
            except: pass
            
        meta["turn_token"] = turn_token
        tools_str = ", ".join(tools_used) if tools_used else "None"
        
        await asyncio.to_thread(write_merged_payload, dump_dir, time_str, req_id or time_str, raw_body, raw_body, inbound_text, model, meta.get("model", model), float(meta["proxy_lat"]), usage, user_prompt, output_text, tools_str, meta, is_opt)
        await asyncio.to_thread(append_to_csv, time_str, req_id or time_str, model, meta.get("model", model), float(meta["proxy_lat"]), usage, user_prompt, output_text, tools_str, "None", meta.get("cost", "0.0"))
        await asyncio.to_thread(update_monthly_stats_md)
        
    except Exception as e: 
        logger.error(f"Background log failed: {e}")

@app.api_route("/{path:path}", methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"])
async def proxy(request: Request, path: str):
    # --- CHECKPOINT 1: Start ---
    t_0 = time.perf_counter()
    
    body_bytes = await request.body()
    
    # --- CHECKPOINT 2: Body Loaded ---
    t_body = time.perf_counter()
    logger.info(f"[TRACE] Request body read: {(t_body - t_0)*1000:.2f}ms")

    is_chat = request.method == "POST" and "chat/completions" in path
    is_opt = os.environ.get("BEO_OPTIMIZE_PAYLOAD", "false").lower() == "true"
    
    raw_body, stream, model, user_prompt = {}, False, TIER_ALIASES.get(1, "tier-1-brain"), "Unknown Input"
    
    if is_chat:
        try:
            raw_body = json.loads(body_bytes)
            stream = raw_body.get("stream", False)
            if stream: raw_body["stream_options"] = {"include_usage": True}
            
            user_msgs = [m for m in raw_body.get("messages", []) if m.get("role") == "user"]
            user_prompt = user_msgs[-1].get("content", "") if user_msgs else ""
            if isinstance(user_prompt, list): user_prompt = " ".join(p.get("text", "") for p in user_prompt if isinstance(p, dict))
            
            # --- THE RESTORED ROUTING LOGIC ---
            # Extract URLs to feed your field/extraction tier rules
            urls_in_prompt = re.findall(r'(https?://[^\s]+)', user_prompt)
            
            # Run the preflight waterfall
            tier_num, is_desk = preflight(user_prompt, attachments=0, urls=urls_in_prompt)
            
            # Fallback (If preflight returns None, default to Brain)
            if tier_num is None:
                tier_num = 1
                
            model = TIER_ALIASES.get(tier_num, "tier-1-brain")
            raw_body["model"] = model
            # ----------------------------------
            
            body_bytes = json.dumps(raw_body).encode()
        except: pass

    # --- CHECKPOINT 3: Preflight/JSON Logic Done ---
    t_preflight = time.perf_counter()
    logger.info(f"[TRACE] Preflight/JSON overhead: {(t_preflight - t_body)*1000:.2f}ms")

    fwd_headers = {k: v for k, v in request.headers.items() if k.lower() not in ("host", "content-length", "accept-encoding")}
    if LITELLM_KEY: fwd_headers["authorization"] = f"Bearer {LITELLM_KEY}"
    fwd_headers["accept-encoding"] = "identity" 
    
    req = http_client.build_request(method=request.method, url=f"{LITELLM_URL}/{path}", headers=fwd_headers, content=body_bytes)
    
    start_time = time.time()
    r = await http_client.send(req, stream=True)
    latency = time.time() - start_time
    
    # --- CHECKPOINT 4: LiteLLM Response Received ---
    t_litellm = time.perf_counter()
    logger.info(f"[TRACE] LiteLLM Roundtrip: {(t_litellm - t_preflight)*1000:.2f}ms")

    resp_headers = {k: v for k, v in r.headers.items() if k.lower() not in ('content-length', 'transfer-encoding', 'content-encoding')}

    if is_chat:
        # THE FIX: Restored full fallback parsing logic
        real_model = "Unknown"
        for h in ["x-litellm-model-api-name", "x-litellm-model-name", "x-litellm-api-model"]:
            if r.headers.get(h): 
                real_model = r.headers.get(h)
                break
        
        if real_model == "Unknown" and r.headers.get("x-litellm-model-api-base"):
            base_url = r.headers.get("x-litellm-model-api-base", "")
            if "/models/" in base_url:
                real_model = base_url.split("/models/")[-1].split(":")[0].split("/")[0]
            elif "openai" in base_url:
                real_model = "OpenAI Backend"

        meta = {
            "model": real_model, 
            "cost": r.headers.get("x-litellm-response-cost-original", "0.0"), 
            "model_lat": r.headers.get("x-litellm-response-duration-ms", "0"), 
            "version": r.headers.get("x-litellm-version", "Unknown"), 
            "call_id": r.headers.get("x-litellm-call-id", "Unknown"), 
            "proxy_lat": f"{latency:.2f}"
        }
        
        now = datetime.now()
        time_str = now.strftime("%Y_%m_%d_@%H_%M_%S_UTC")
        dump_dir = f"/root/.openclaw/payloads/{now.strftime('%Y/%m/%d')}"
        os.makedirs(dump_dir, exist_ok=True)

        if stream:
            cap = bytearray()
            async def stream_gen():
                try:
                    async for line in r.aiter_lines(): 
                        chunk = (line + "\n").encode("utf-8")
                        cap.extend(chunk)
                        yield chunk
                finally:
                    await r.aclose()
                    # await client.aclose()
                    asyncio.create_task(process_log(bytes(cap), dump_dir, time_str, raw_body, meta, is_opt, model, user_prompt))
            
            # --- CHECKPOINT 5: Final dispatch (Stream) ---
            t_end = time.perf_counter()
            logger.info(f"[TRACE] Total Proxy overhead before stream starts: {(t_end - t_0)*1000:.2f}ms")
            
            return StreamingResponse(stream_gen(), status_code=r.status_code, headers=resp_headers, media_type="text/event-stream")
        else:
            await r.aread()
            content = r.content
            await r.aclose()
            # await client.aclose()
            asyncio.create_task(process_log(content, dump_dir, time_str, raw_body, meta, is_opt, model, user_prompt))
            
            # --- CHECKPOINT 5: Final dispatch (Sync) ---
            t_end = time.perf_counter()
            logger.info(f"[TRACE] Total Proxy overhead before sync return: {(t_end - t_0)*1000:.2f}ms")
            
            return Response(content=content, status_code=r.status_code, headers=resp_headers, media_type=r.headers.get("content-type"))
            
    await r.aread()
    content = r.content
    await r.aclose()
    # await client.aclose()
    
    # --- CHECKPOINT 5: Final dispatch (Fallback) ---
    t_end = time.perf_counter()
    logger.info(f"[TRACE] Total Proxy overhead before fallback return: {(t_end - t_0)*1000:.2f}ms")
    
    return Response(content=content, status_code=r.status_code, headers=resp_headers)
