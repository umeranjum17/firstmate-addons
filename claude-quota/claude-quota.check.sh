#!/usr/bin/env bash
# Wake Main when the Claude window burns ahead of time (captain 16 Oct ~02:50Z: "use opus 5.5 for now we have lot of
# limits"). Main, the 10 leads and many workers share one Max account, so an empty 5 h window stops Main and every lead
# until it resets. Fires when the 5 h window is under 35% with more than 60 min to its reset, or the week is under 40%;
# repeats only when that picture changes. At most one read per 10 min. Usage: $0 [quota-json-file] (file = test input).
# 16 Oct: also fires when the week's burn rate over the last 1-5 h would empty it more than 12 h before its reset
# (02:57-07:05Z went 98% -> 87% left = empty ~17 Oct while the week resets 22 Oct; the < 40% line fires far too late).
# ponytail: fixed thresholds; tune here if the number of Opus lanes changes.
set -u
MARK=/home/umer/firstmate/state/.claude-quota.last
now=$(date +%s)
if [ $# -eq 0 ]; then
  [ -f "$MARK" ] && [ $((now - $(stat -c %Y "$MARK"))) -lt 600 ] && exit 0
  j=$(timeout 60 quota-axi --json 2>/dev/null) || exit 0
else
  j=$(cat "$1"); MARK=$(mktemp)
fi
HIST=/home/umer/firstmate/state/.claude-quota.hist; [ $# -eq 0 ] || HIST=${CQ_HIST:-$(mktemp)}
out=$(printf '%s' "$j" | HIST=$HIST python3 -I -c '
import json,sys,datetime as D
try:
    x=[p for p in json.load(sys.stdin)["providers"] if p.get("provider")=="claude"][0]
    W={w["id"]:w for w in x["windows"]}; f,w=W["five_hour"],W["seven_day"]
except Exception: sys.exit()
P=lambda s: D.datetime.fromisoformat(s.replace("Z","+00:00"))
left=int((P(f["resetsAt"])-D.datetime.now(D.timezone.utc)).total_seconds()//60)
fp,wp,wr=f["percentRemaining"],w["percentRemaining"],w["resetsAt"]
import os,time
now=time.time(); hp=os.environ["HIST"]
try: h=[tuple(map(float,l.split())) for l in open(hp) if l.strip()]
except Exception: h=[]
h=[x for x in h if now-x[0]<5*3600]+[(now,wp)]
open(hp,"w").write("".join(f"{int(a)} {int(b)}\n" for a,b in h[-40:]))
old=[x for x in h if now-x[0]>=3600]
rate=(old[0][1]-wp)/((now-old[0][0])/3600) if old else 0
reset_h=(P(wr)-D.datetime.now(D.timezone.utc)).total_seconds()/3600
fast=rate>0 and wp/rate < reset_h-12
if not ((fp<35 and left>60) or wp<40 or fast): sys.exit()
print(f"{fp//10}|{wp//10}|{int(fast)}")
if fast: print(f"claude-quota: Claude week {wp}% left, burning {rate:.1f}%/h over the last {(now-old[0][0])/3600:.1f} h = empty in {wp/rate:.0f} h, but it resets in {reset_h:.0f} h ({wr}). Cut Claude use now: stop worker fan-out (Workflow/Agent), no new Opus workers, move the newest Opus workers to GLM 5.3 Flash (pi zai/glm-5.3-flash, captain 08:05Z) or Go Muse / DeepSeek within the Go pace (never Main or the leads; never Step 5)"); sys.exit()
print(f"claude-quota: Claude 5 h window {fp}% left with {left} min to its reset; week {wp}% left (resets {wr}). Opus burns ahead of the window: move the newest Opus workers (never Main or the leads) to GLM 5.3 Flash (pi zai/glm-5.3-flash) or Go Muse / DeepSeek (never Step 5, captain 03:13Z) until the 5 h window resets; at week < 40% also drop Opus from the ordinary dispatch rules")
')
[ -n "$out" ] || { : > "$MARK"; exit 0; }
sig=${out%%$'\n'*}
[ "$sig" = "$(cat "$MARK" 2>/dev/null)" ] && { touch "$MARK"; exit 0; }
printf '%s' "$sig" > "$MARK"
printf '%s\n' "${out#*$'\n'}"
