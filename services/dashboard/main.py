import os, csv, glob, calendar
from datetime import datetime, timedelta
from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse, FileResponse
from fastapi.templating import Jinja2Templates

app = FastAPI(title="BEO Dashboard")
templates = Jinja2Templates(directory="templates")

METRICS_KEY = os.environ.get("BEO_DASHBOARD_TOKEN", "mochi")
OPT_ENABLED = os.environ.get("BEO_OPTIMIZE_PAYLOAD", "false").strip(' "\'').lower() == "true"

def get_file_path(time_val: str):
    parts = time_val.split("_")
    if len(parts) >= 6:
        year, month, day = parts[0], parts[1], parts[2]
        file_path = f"/root/.openclaw/payloads/{year}/{month}/{day}/beo_{time_val}_merged.md"
        if os.path.exists(file_path): return file_path
        txt_path = file_path.replace(".md", ".txt")
        if os.path.exists(txt_path): return txt_path
    return None

def fmt_date(d: datetime):
    return d.strftime('%b %d').replace(' 0', ' ')

def parse_csv_row(row):
    """Dynamically parses historical CSV rows regardless of column shifts."""
    d = {"time_val": row[0] if len(row)>0 else "", "req_id": "", "tier": "", "r_model": "", "lat": "0", "p_tk": "0", "c_tk": "0", "o_tk": "0", "in_text": "", "out_text": "", "tools": "", "skills": "", "cost": "0.0"}
    
    if len(row) == 6:
        d["time_val"], d["tier"], d["lat"], d["p_tk"], d["c_tk"], d["o_tk"] = row
    elif len(row) == 9: # Heals the corrupted 9-column rows
        d["time_val"], d["req_id"], d["tier"], d["r_model"], d["lat"], d["p_tk"], d["c_tk"], d["o_tk"], d["cost"] = row
        d["in_text"] = "[Unlogged Input]"
        d["out_text"] = "[Unlogged Output]"
    elif len(row) == 10:
        d["time_val"], d["tier"], d["r_model"], d["lat"], d["p_tk"], d["c_tk"], d["o_tk"], d["in_text"], d["out_text"], d["tools"] = row
    elif len(row) >= 12:
        d["time_val"], d["req_id"], d["tier"], d["r_model"], d["lat"], d["p_tk"], d["c_tk"], d["o_tk"], d["in_text"], d["out_text"], d["tools"], d["skills"] = row[:12]
        if len(row) >= 13: d["cost"] = row[12]
    
    try:
        p_int, c_int = int(d["p_tk"]), int(d["c_tk"])
        d["cache_pct"] = f"{(c_int / p_int * 100):.1f}%" if p_int > 0 else "0.0%"
    except: d["cache_pct"] = "0.0%"
    return d

@app.get("/", response_class=HTMLResponse)
async def dashboard_home(request: Request, token: str = None, time_range: str = "24h", start: str = None, end: str = None, tz_offset: int = 0):
    if token != METRICS_KEY: return HTMLResponse("<h1>Unauthorized.</h1>", status_code=401)
    
    now_utc = datetime.utcnow()
    now_local = now_utc - timedelta(minutes=tz_offset)
    
    this_week_start = now_local - timedelta(days=now_local.weekday())
    this_week_start = this_week_start.replace(hour=0, minute=0, second=0, microsecond=0)
    this_month_start = now_local.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    _, last_day = calendar.monthrange(now_local.year, now_local.month)
    
    q_month = (now_local.month - 1) // 3 * 3 + 1
    this_q_start = now_local.replace(month=q_month, day=1, hour=0, minute=0, second=0, microsecond=0)
    _, q_last_day = calendar.monthrange(now_local.year, q_month + 2)
    
    labels = {
        "1h": f"Past hour ({fmt_date(now_local)})",
        "24h": f"Past 24 hours ({fmt_date(now_local - timedelta(days=1))} – {fmt_date(now_local)})",
        "7d": f"Last 7 days ({fmt_date(now_local - timedelta(days=7))} – {fmt_date(now_local)})",
        "30d": f"Last 30 days ({fmt_date(now_local - timedelta(days=30))} – {fmt_date(now_local)})",
        "90d": f"Last 90 days ({fmt_date(now_local - timedelta(days=90))} – {fmt_date(now_local)})",
        "this_week": f"This week ({fmt_date(this_week_start)} – {fmt_date(this_week_start + timedelta(days=6))})",
        "this_month": f"This month ({fmt_date(this_month_start)} – {fmt_date(now_local.replace(day=last_day))})",
        "this_quarter": f"This quarter ({fmt_date(this_q_start)} – {fmt_date(now_local.replace(month=q_month+2, day=q_last_day))})"
    }

    if start and end and time_range == "custom":
        start_local = datetime.strptime(start, '%Y-%m-%d')
        end_local = datetime.strptime(end, '%Y-%m-%d').replace(hour=23, minute=59, second=59)
    else:
        end_local = now_local
        if time_range == "1h": start_local = now_local - timedelta(hours=1)
        elif time_range == "7d": start_local = now_local - timedelta(days=7)
        elif time_range == "this_week": start_local = this_week_start
        elif time_range == "this_month": start_local = this_month_start
        elif time_range == "this_quarter": start_local = this_q_start
        elif time_range == "30d": start_local = now_local - timedelta(days=30)
        elif time_range == "90d": start_local = now_local - timedelta(days=90)
        else: 
            time_range = "24h"
            start_local = now_local - timedelta(days=1)
            
    start_utc = start_local + timedelta(minutes=tz_offset)
    end_utc = end_local + timedelta(minutes=tz_offset)
    
    all_rows = []
    days_to_fetch = max(1, (end_utc.date() - start_utc.date()).days + 2)
    for i in range(days_to_fetch):
        day = start_utc + timedelta(days=i)
        csv_path = f"/root/.openclaw/payloads/{day.strftime('%Y_%m_%d')}_ledger.csv"
        if os.path.exists(csv_path):
            with open(csv_path, "r", encoding="utf-8") as f:
                data = list(csv.reader(f))
                if len(data) > 1: all_rows.extend(data[1:])
                
    all_rows.reverse()
    
    processed_rows = []
    for row in all_rows:
        if len(row) > 0:
            try:
                # Try the new microsecond format first
                try:
                    row_time = datetime.strptime(row[0], "%Y_%m_%d_@%H_%M_%S_%f_UTC")
                # Fallback to the old format for historical logs
                except ValueError:
                    row_time = datetime.strptime(row[0], "%Y_%m_%d_@%H_%M_%S_UTC")
                
                if start_utc <= row_time <= end_utc:
                    processed_rows.append(parse_csv_row(row))
            except: pass

    return templates.TemplateResponse(request=request, name="payloads.html", context={
        "request": request, "token": token, "time_range": time_range, "start_date": start, "end_date": end, "rows": processed_rows, "labels": labels
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
                    row_data = parse_csv_row(row)
                    break

    with open(file_path, "r", encoding="utf-8") as f: content = f.read()
    return templates.TemplateResponse(request=request, name="payload_viewer.html", context={
        "request": request, "time_val": time_val, "content": content, "row_data": row_data, "token": token, "opt_enabled": OPT_ENABLED
    })

@app.get("/download/{time_val}")
async def download_payload(time_val: str, token: str = None):
    if token != METRICS_KEY: return HTMLResponse("<h1>Unauthorized.</h1>", status_code=401)
    file_path = get_file_path(time_val)
    if not file_path: return HTMLResponse("<h1>Payload not found.</h1>")
    return FileResponse(file_path, media_type='text/markdown', filename=f"beo_{time_val}_merged.md")
