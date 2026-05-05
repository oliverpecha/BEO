"""
BEO Logger Engine (Preflight)
Handles writing merged Markdown dumps and CSV ledger rows.
UI rendering has been decoupled to the standalone Dashboard service.
"""
import os, csv, json
from datetime import datetime, timedelta
from fastapi import APIRouter

metrics_router = APIRouter()

def write_merged_payload(dump_dir: str, time_str: str, req_id: str, raw_body: dict, opt_body: dict, inbound_text: str, model: str, real_model: str, latency: float, usage: dict, in_text: str, out_text: str, tools_used: str, skills_used: str, is_optimized: bool) -> None:
    """Writes a Markdown formatted merged payload file."""
    merged_path = f"{dump_dir}/beo_{time_str}_merged.md"
    
    prompt_tk = usage.get("prompt_tokens", 0)
    cached_tk = usage.get("prompt_tokens_details", {}).get("cached_tokens", 0)
    out_tk = usage.get("completion_tokens", 0)
    hit_rate = (cached_tk/prompt_tk*100) if prompt_tk else 0
    total_tk = prompt_tk + out_tk
    opt_status = "✨ Optimized" if is_optimized else "⚠️ Not Optimized"

    # Parse date and time cleanly
    parts = time_str.split("_")
    v_date = f"{parts[0]}-{parts[1]}-{parts[2]}" if len(parts) >= 3 else "--"
    v_time = f"{parts[3].replace('@','')}:{parts[4]}:{parts[5]} UTC" if len(parts) >= 6 else "--:--:--"

    with open(merged_path, "w", encoding="utf-8") as f:
        # SUMMARY BLOCK
        f.write("████████████████████████████████████████████████████████████████████████████████\n")
        f.write("███ 📊 PAYLOAD SUMMARY █████████████████████████████████████████████████████████\n")
        f.write("████████████████████████████████████████████████████████████████████████████████\n\n")
        
        f.write(f"**📅 Date:** `{v_date}` | **🕒 Time:** `{v_time}` | **🆔 ID:** `{req_id}`\n\n")
        f.write(f"**🤖 Tier:** `{model}` | **🧠 Model:** `{real_model}` | **⚡ Latency:** `{latency:.2f}s`\n\n")
        
        f.write("**🧮 Tokens:**\n")
        f.write(f"📈 **{total_tk:,}** Total | 📡 **{prompt_tk:,}** Input | **{opt_status}** | 🏁 **{out_tk:,}** Output | 🎯 **{cached_tk:,}** Cached ({hit_rate:.1f}%)\n\n")
        
        f.write(f"**🛫 Input:**\n{in_text.strip()}\n\n")
        f.write(f"**🛬 Output:**\n{out_text.strip()}\n\n")
        
        f.write(f"**🛠️ Tools Used:** `{tools_used if tools_used else 'None'}` | **⚙️ Skills Used:** `{skills_used if skills_used else 'None'}`\n\n\n")
        
        ticks = "`" * 3
        
        # OUTBOUND RAW BLOCK
        f.write("████████████████████████████████████████████████████████████████████████████████\n")
        f.write("███ 📦 1. OUTBOUND RAW (Pre-Optimization) ██████████████████████████████████████\n")
        f.write("████████████████████████████████████████████████████████████████████████████████\n")
        f.write(f"\n{ticks}json\n{json.dumps(raw_body, indent=2)}\n{ticks}\n\n\n")
        
        # OUTBOUND OPTIMIZED BLOCK
        f.write("████████████████████████████████████████████████████████████████████████████████\n")
        f.write("███ ✨ 2. OUTBOUND OPTIMIZED ████████████████████████████████████████████████████\n")
        f.write("████████████████████████████████████████████████████████████████████████████████\n")
        f.write(f"\n{ticks}json\n{json.dumps(opt_body, indent=2)}\n{ticks}\n\n\n")
        
        # INBOUND RESPONSE BLOCK
        f.write("████████████████████████████████████████████████████████████████████████████████\n")
        f.write("███ 🏁 3. INBOUND RESPONSE █████████████████████████████████████████████████████\n")
        f.write("████████████████████████████████████████████████████████████████████████████████\n\n")
        try:
            inbound_json = json.loads(inbound_text)
            f.write(f"{ticks}json\n{json.dumps(inbound_json, indent=2)}\n{ticks}\n")
        except:
            f.write(f"{ticks}text\n{inbound_text}\n{ticks}\n")

def append_to_csv(time_str: str, req_id: str, model: str, real_model: str, latency: float, usage: dict, in_text: str, out_text: str, tools_used: str, skills_used: str) -> None:
    now = datetime.now()
    year, month, day = now.strftime("%Y"), now.strftime("%m"), now.strftime("%d")
    csv_path = f"/root/.openclaw/payloads/{year}_{month}_{day}_ledger.csv"
    
    file_exists = os.path.isfile(csv_path)
    prompt_tk = usage.get("prompt_tokens", 0)
    cached_tk = usage.get("prompt_tokens_details", {}).get("cached_tokens", 0)
    out_tk = usage.get("completion_tokens", 0)
    
    in_prev = in_text.replace('\n', ' ').replace('\r', '')[:75] + ("..." if len(in_text) > 75 else "")
    out_prev = out_text.replace('\n', ' ').replace('\r', '')[:75] + ("..." if len(out_text) > 75 else "")
    
    with open(csv_path, "a", newline="", encoding="utf-8") as csvfile:
        writer = csv.writer(csvfile)
        if not file_exists:
            writer.writerow(["Timestamp", "ID", "Tier", "Real_Model", "Lat(s)", "Prompt_Tk", "Cached_Tk", "Output_Tk", "Input", "Output", "Tools", "Skills"])
        writer.writerow([time_str, req_id, model, real_model, f"{latency:.2f}", prompt_tk, cached_tk, out_tk, in_prev, out_prev, tools_used, skills_used])

def update_monthly_stats_md() -> None:
    now = datetime.now()
    month_str = now.strftime("%Y_%m")
    md_path = f"/root/.openclaw/payloads/{month_str}_stats.md"
    md_content = f"# 📊 BEO Token Stats: {now.strftime('%B %Y')}\n\n| Date | Reqs | Avg Latency | Prompt Tk | Cached Tk | Hit % |\n|---|---|---|---|---|---|\n"
    totals = {"reqs": 0, "lat": 0, "p": 0, "c": 0}
    for i in range(31, -1, -1):
        d = now - timedelta(days=i)
        if d.strftime("%Y_%m") != month_str: continue 
        date_str = d.strftime('%Y_%m_%d')
        csv_path = f"/root/.openclaw/payloads/{date_str}_ledger.csv"
        if not os.path.exists(csv_path): continue
        reqs = 0; lat = 0.0; p = 0; c = 0
        with open(csv_path, 'r', encoding="utf-8") as f:
            reader = csv.reader(f)
            data = list(reader)[1:]
            for row in data:
                try:
                    if len(row) == 6: reqs += 1; lat += float(row[2]); p += int(row[3]); c += int(row[4])
                    elif len(row) == 10: reqs += 1; lat += float(row[3]); p += int(row[4]); c += int(row[5])
                    else: reqs += 1; lat += float(row[4]); p += int(row[5]); c += int(row[6])
                except: pass
        if reqs > 0:
            hit_rate = (c / p * 100) if p > 0 else 0
            md_content += f"| {date_str} | {reqs} | {lat/reqs:.2f}s | {p:,} | {c:,} | {hit_rate:.1f}% |\n"
            for k, v in [("reqs", reqs), ("lat", lat), ("p", p), ("c", c)]: totals[k] += v
    if totals["reqs"] > 0:
        tot_hit = (totals["c"] / totals["p"] * 100) if totals["p"] > 0 else 0
        md_content += f"| **TOTAL** | **{totals['reqs']}** | **{totals['lat']/totals['reqs']:.2f}s** | **{totals['p']:,}** | **{totals['c']:,}** | **{tot_hit:.1f}%** |\n"
    with open(md_path, "w", encoding="utf-8") as f: f.write(md_content)
