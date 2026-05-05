import os, csv, glob
from datetime import datetime, timedelta
from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse, FileResponse
from fastapi.templating import Jinja2Templates

app = FastAPI(title="BEO Dashboard")
templates = Jinja2Templates(directory="templates")

METRICS_KEY = os.environ.get("BEO_DASHBOARD_TOKEN", "mochi")

def get_file_path(time_val: str):
    parts = time_val.split("_")
    if len(parts) >= 6:
        year, month, day = parts[0], parts[1], parts[2]
        # Look for the .md file primarily
        file_path = f"/root/.openclaw/payloads/{year}/{month}/{day}/beo_{time_val}_merged.md"
        if os.path.exists(file_path): return file_path
        
        # Fallback for the few .txt files created today
        txt_path = file_path.replace(".md", ".txt")
        if os.path.exists(txt_path): return txt_path
    return None

@app.get("/", response_class=HTMLResponse)
async def dashboard_home(request: Request, token: str = None, start: str = None, end: str = None):
    if token != METRICS_KEY: return HTMLResponse("<h1>Unauthorized.</h1>", status_code=401)
    
    start_date = start or datetime.now().strftime('%Y-%m-%d')
    end_date = end or datetime.now().strftime('%Y-%m-%d')
    start_dt = datetime.strptime(start_date, '%Y-%m-%d')
    end_dt = datetime.strptime(end_date, '%Y-%m-%d')
    
    all_rows = []
    for i in range((end_dt - start_dt).days + 1):
        day = start_dt + timedelta(days=i)
        csv_path = f"/root/.openclaw/payloads/{day.strftime('%Y_%m_%d')}_ledger.csv"
        if os.path.exists(csv_path):
            with open(csv_path, "r", encoding="utf-8") as f:
                data = list(csv.reader(f))
                if len(data) > 1: all_rows.extend(data[1:])
                
    all_rows.reverse()
    
    processed_rows = []
    for row in all_rows:
        req_id, skills = "", ""
        if len(row) == 6:
            time_val, tier, lat, p_tk, c_tk, o_tk = row
            r_model, in_text, out_text, tools = "", "", "", ""
        elif len(row) == 10:
            time_val, tier, r_model, lat, p_tk, c_tk, o_tk, in_text, out_text, tools = row
        else:
            time_val, req_id, tier, r_model, lat, p_tk, c_tk, o_tk, in_text, out_text, tools, skills = (row + [""] * 12)[:12]
        
        try:
            p_int, c_int = int(p_tk), int(c_tk)
            cache_pct = f"{(c_int / p_int * 100):.1f}%" if p_int > 0 else "0.0%"
        except: cache_pct = "0.0%"

        if "_@" in time_val:
            parts = time_val.split("_")
            disp_time = f"{parts[0]}-{parts[1]}-{parts[2]}<br>{parts[3].replace('@','')}:{parts[4]}:{parts[5]}"
        else:
            disp_time = time_val
            
        processed_rows.append({
            "time_val": time_val, "disp_time": disp_time, "tier": tier, "r_model": r_model, 
            "lat": lat, "p_tk": p_tk, "c_tk": c_tk, "cache_pct": cache_pct, "o_tk": o_tk, 
            "in_text": in_text, "out_text": out_text
        })

    return templates.TemplateResponse(request=request, name="payloads.html", context={
        "request": request, "token": token, "start_date": start_date, "end_date": end_date, "rows": processed_rows
    })

@app.get("/payload/{time_val}", response_class=HTMLResponse)
async def view_payload(request: Request, time_val: str, token: str = None):
    if token != METRICS_KEY: return HTMLResponse("<h1>Unauthorized.</h1>", status_code=401)
    file_path = get_file_path(time_val)
    if not file_path: return HTMLResponse("<h1>Payload not found.</h1>")
    
    parts = time_val.split("_")
    csv_path = f"/root/.openclaw/payloads/{parts[0]}_{parts[1]}_{parts[2]}_ledger.csv"
    row_data = {}
    if os.path.exists(csv_path):
        with open(csv_path, "r", encoding="utf-8") as f:
            for row in csv.reader(f):
                if len(row) > 0 and row[0] == time_val:
                    if len(row) >= 12:
                        row_data = {"req_id": row[1], "tier": row[2], "r_model": row[3], "lat": row[4], "p_tk": row[5], "c_tk": row[6], "o_tk": row[7], "in_text": row[8], "out_text": row[9], "tools": row[10], "skills": row[11]}
                    elif len(row) == 10:
                        row_data = {"tier": row[1], "r_model": row[2], "lat": row[3], "p_tk": row[4], "c_tk": row[5], "o_tk": row[6], "in_text": row[7], "out_text": row[8], "tools": row[9]}
                    elif len(row) == 6:
                        row_data = {"tier": row[1], "lat": row[2], "p_tk": row[3], "c_tk": row[4], "o_tk": row[5]}
                    break

    with open(file_path, "r", encoding="utf-8") as f: content = f.read()
    return templates.TemplateResponse(request=request, name="payload_viewer.html", context={
        "request": request, "time_val": time_val, "content": content, "row_data": row_data, "token": token
    })

@app.get("/download/{time_val}")
async def download_payload(time_val: str, token: str = None):
    if token != METRICS_KEY: return HTMLResponse("<h1>Unauthorized.</h1>", status_code=401)
    file_path = get_file_path(time_val)
    if not file_path: return HTMLResponse("<h1>Payload not found.</h1>")
    # Output as markdown
    return FileResponse(file_path, media_type='text/markdown', filename=f"beo_{time_val}_merged.md")
