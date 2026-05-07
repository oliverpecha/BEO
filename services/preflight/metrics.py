import os, csv, json
from datetime import datetime
from fastapi import APIRouter

metrics_router = APIRouter()

def write_merged_payload(dump_dir, time_str, req_id, raw_body, opt_body, inbound, tier, model, lat, usage, in_txt, out_txt, tools, meta, is_opt):
    merged_path = f"{dump_dir}/beo_{time_str}_merged.md"
    p_tk = usage.get("prompt_tokens", 0)
    c_tk = usage.get("prompt_tokens_details", {}).get("cached_tokens", 0)
    o_tk = usage.get("completion_tokens", 0)
    hit_rate = (c_tk/p_tk*100) if p_tk > 0 else 0
    
    mods = []
    ptd = usage.get("prompt_tokens_details", {})
    if isinstance(ptd, dict):
        for k, v in ptd.items():
            if v > 0: mods.append(f"{k.replace('_tokens', '').upper()}: {v}")
    modality_str = ", ".join(mods) if mods else "TEXT Only"

    parts = time_str.split("_")
    v_date = f"{parts[0]}-{parts[1]}-{parts[2]}" if len(parts) >= 3 else "--"
    v_time = f"{parts[3].replace('@','')}:{parts[4]}:{parts[5]} UTC" if len(parts) >= 6 else "--:--:--"

    with open(merged_path, "w", encoding="utf-8") as f:
        f.write("█"*80 + "\n███ 📊 PAYLOAD SUMMARY\n" + "█"*80 + "\n\n")
        f.write(f"**📅 Date:** `{v_date}` | **🕒 Time:** `{v_time}` | **🆔 ID:** `{req_id}`\n\n")
        f.write(f"**🤖 Tier:** `{tier}` | **🧠 Model:** `{model}` | **⚡ Latency:** `{lat:.2f}s`\n\n")
        
        f.write("**🧮 Tokens:**\n\n| 📈 Total | 📡 Input | ✨ Optimization | 🏁 Output | 🗄️ Cache | 🕸️ Cached |\n|---|---|---|---|---|---|\n")
        f.write(f"| **{p_tk+o_tk:,}** | **{p_tk:,}** | {'💎 Optimized' if is_opt else '⚠️ Not Optimized'} | **{o_tk:,}** | {'🎯 Hit' if c_tk>0 else '🔔 Missed'} | **{c_tk:,} ({hit_rate:.1f}%)** |\n\n")
        
        f.write(f"**🛫 Input:**\n{in_txt}\n\n**🛬 Output:**\n{out_txt}\n\n")
        f.write(f"**🛠️ Tools Used:** `{tools}` | **⚙️ Skills Used:** `None`\n\n")
        f.write(f"**📁 File:** `{merged_path}`\n\n")
        
        f.write(f"**🔍 Deep Metadata:**\n")
        f.write(f"*   **💰 Response Cost:** `${meta.get('cost', '0.0')}`\n")
        f.write(f"*   **⚡ Latency Details:** `{meta.get('model_lat', '0')}ms` (Model) vs `{lat:.2f}s` (Proxy Round-trip)\n")
        f.write(f"*   **🛠️ System Info:** LiteLLM `v{meta.get('version', '?')}` | Call ID: `{meta.get('call_id', '?')}`\n")
        f.write(f"*   **🆔 Turn Token:** `{meta.get('turn_token', 'N/A')}`\n")
        f.write(f"*   **🕸️ Cache Modality:** `{modality_str}`\n\n\n")

        ticks = "```"
        f.write("█"*80 + "\n███ 📦 1. OUTBOUND RAW (Pre-Optimization)\n" + "█"*80 + f"\n\n{ticks}json\n{json.dumps(raw_body, indent=2)}\n{ticks}\n\n\n")
        f.write("█"*80 + "\n███ ✨ 2. OUTBOUND OPTIMIZED\n" + "█"*80 + f"\n\n{ticks}json\n{json.dumps(opt_body, indent=2)}\n{ticks}\n\n\n")
        f.write("█"*80 + "\n███ 🏁 3. INBOUND RESPONSE\n" + "█"*80 + "\n\n")
        try:
            f.write(f"{ticks}json\n{json.dumps(json.loads(inbound), indent=2)}\n{ticks}\n")
        except: 
            f.write(f"{ticks}text\n{inbound}\n{ticks}\n")

def append_to_csv(time_str, req_id, tier, model, lat, usage, in_txt, out_txt, tools, skills, cost):
    now = datetime.now()
    csv_path = f"/root/.openclaw/payloads/{now.strftime('%Y_%m_%d')}_ledger.csv"
    exists = os.path.isfile(csv_path)
    
    p_tk = usage.get("prompt_tokens", 0)
    c_tk = usage.get("prompt_tokens_details", {}).get("cached_tokens", 0)
    o_tk = usage.get("completion_tokens", 0)
    
    in_prev = str(in_txt).replace('\n', ' ').replace('\r', '')[:75]
    out_prev = str(out_txt).replace('\n', ' ').replace('\r', '')[:75]
    
    with open(csv_path, "a", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        if not exists: 
            writer.writerow(["Timestamp","ID","Tier","Model","Lat","Prompt_Tk","Cached_Tk","Output_Tk","Input","Output","Tools","Skills","Cost"])
        writer.writerow([time_str, req_id, tier, model, f"{lat:.2f}", p_tk, c_tk, o_tk, in_prev, out_prev, tools, skills, cost])

def update_monthly_stats_md():
    pass
