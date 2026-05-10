#!/usr/bin/env python3
"""
BEO Unified CLI
Usage: 
  python3 beo_cli.py stats
  python3 beo_cli.py cat <timestamp_id>
"""
import sys, os, csv, glob, datetime

def show_stats():
    print(f"\n{'Date':<12} | {'Reqs':<5} | {'Avg Latency':<12} | {'Prompt Tk':<12} | {'Cached Tk':<12} | {'Hit %':<6}")
    print("-" * 75)
    totals = {"reqs": 0, "lat": 0, "p": 0, "c": 0}

    for i in range(6, -1, -1):
        d = datetime.datetime.now() - datetime.timedelta(days=i)
        date_str = d.strftime('%Y_%m_%d')
        path = f"/root/.openclaw/payloads/{date_str}_ledger.csv"
        
        if not os.path.exists(path):
            print(f"{date_str:<12} | No data")
            continue
            
        reqs = 0; lat = 0.0; p = 0; c = 0
        with open(path, 'r', encoding="utf-8") as f:
            reader = csv.DictReader(f)
            for row in reader:
                try:
                    reqs += 1; lat += float(row['Latency(s)'])
                    p += int(row['Prompt_Tokens']); c += int(row['Cached_Tokens'])
                except: pass
                
        if reqs == 0:
            print(f"{date_str:<12} | No data")
            continue
            
        hit_rate = (c / p * 100) if p > 0 else 0
        print(f"{date_str:<12} | {reqs:<5} | {lat/reqs:<10.2f} s | {p:<12} | {c:<12} | {hit_rate:<6.1f}")
        for k, v in [("reqs", reqs), ("lat", lat), ("p", p), ("c", c)]: totals[k] += v

    print("-" * 75)
    if totals["reqs"] > 0:
        tot_hit = (totals["c"] / totals["p"] * 100) if totals["p"] > 0 else 0
        print(f"{'7-DAY TOTAL':<12} | {totals['reqs']:<5} | {totals['lat']/totals['reqs']:<10.2f} s | {totals['p']:<12} | {totals['c']:<12} | {tot_hit:<6.1f}\n")

def cat_payload(payload_id):
    # Extracts base safely whether you pass "2026_05_04_@16_59_29" or "beo_..._merged.txt"
    base = os.path.basename(payload_id).replace("beo_", "").replace("_merged.txt", "")
    parts = base.split("_")
    
    # We still need the first 3 elements (Year, Month, Day) to find the folder path
    if len(parts) >= 3:
        year, month, day = parts[0], parts[1], parts[2]
        fpath = f"/root/.openclaw/payloads/{year}/{month}/{day}/beo_{base}_merged.txt"
        
        if os.path.exists(fpath):
            with open(fpath, 'r', encoding="utf-8") as f:
                print(f.read().strip())
        else:
            print(f"❌ Could not find merged file at: {fpath}")
    else:
        print("❌ Invalid ID format. Use YYYY_MM_DD_@HH_MM_SS")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 beo_cli.py [stats | cat <YYYY_MM_DD_@HH_MM_SS>]")
        sys.exit(1)
        
    if sys.argv[1] == "stats":
        show_stats()
    elif sys.argv[1] == "cat" and len(sys.argv) > 2:
        cat_payload(sys.argv[2])
    else:
        print("❌ Invalid command.")
