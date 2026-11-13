#!/bin/bash
# monitor.sh - B4-1 health check (Bash only).
# Deploy path: $AGENT_HOME/bin/monitor.sh   (/opt/agent-app/bin/monitor.sh)
#
# Checks: Agent process, TCP LISTEN, UFW state, CPU/MEM/DISK.
# Output: stdout only (log file / cron / rotation are separate tasks).
#
# Exit codes:
#   0  healthy: Agent process confirmed AND port LISTEN (warnings/unknown allowed)
#   1  health check failed or cannot be confirmed (process missing, process
#      identification not configured [PENDING], port not LISTEN)
#   2  monitoring/config error (bad config, missing tool, collection failure)
#      -- only when no confirmed failure (exit 1 takes precedence)
#
# Config is loaded explicitly from /etc/default/agent-app (override: MONITOR_ENV_FILE).
# It never relies on login-shell files. Thresholds are [design defaults], not official values.

set -u
export LC_ALL=C PATH=/usr/sbin:/usr/bin:/sbin:/bin

ENV_FILE="${MONITOR_ENV_FILE:-/etc/default/agent-app}"

FAILS=0; WARNS=0; UNKNOWNS=0; PENDINGS=0; ERRORS=0

ts()  { date '+%Y-%m-%d %H:%M:%S'; }
say() { # level category message
  printf '%s [%s] %s %s\n' "$(ts)" "$1" "$2" "$3"
  case "$1" in
    FAIL) FAILS=$((FAILS+1));; WARNING) WARNS=$((WARNS+1));;
    UNKNOWN) UNKNOWNS=$((UNKNOWNS+1));; PENDING) PENDINGS=$((PENDINGS+1));;
    ERROR) ERRORS=$((ERRORS+1));;
  esac
}
finish() {
  local code result
  if [ $((FAILS+PENDINGS)) -gt 0 ]; then code=1; result=UNHEALTHY
  elif [ "$ERRORS" -gt 0 ]; then code=2; result=MONITOR_ERROR
  else code=0; result=HEALTHY; fi
  say INFO SUMMARY "result=$result exit=$code fail=$FAILS pending=$PENDINGS warning=$WARNS unknown=$UNKNOWNS error=$ERRORS"
  exit "$code"
}
is_uint()  { [[ "${1:-}" =~ ^[0-9]+$ ]]; }
is_pct()   { [[ "${1:-}" =~ ^[0-9]+(\.[0-9]+)?$ ]] && awk -v v="$1" 'BEGIN{exit !(v>=0 && v<=100)}'; }
is_pos()   { [[ "${1:-}" =~ ^[0-9]+(\.[0-9]+)?$ ]] && awk -v v="$1" 'BEGIN{exit !(v>0 && v<=10)}'; }
gt()       { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a>b)}'; }

# ---------------------------------------------------------------- tools
for t in ss pgrep df awk date sleep; do
  command -v "$t" >/dev/null 2>&1 || { say ERROR TOOLS "required command not found: $t"; finish; }
done

# ---------------------------------------------------------------- config
say INFO START "user=$(id -un) uid=$EUID host=$(hostname) env_file=$ENV_FILE"
if [ ! -r "$ENV_FILE" ]; then
  say ERROR CONFIG "env file not readable: $ENV_FILE"; finish
fi
# shellcheck disable=SC1090
set -a; . "$ENV_FILE"; set +a

cfg_bad=0
for v in AGENT_HOME AGENT_PORT AGENT_UPLOAD_DIR AGENT_LOG_DIR; do
  if [ -z "${!v:-}" ]; then say ERROR CONFIG "required variable missing or empty: $v"; cfg_bad=1; fi
done
if [ -n "${AGENT_PORT:-}" ]; then
  if ! is_uint "$AGENT_PORT" || [ "$AGENT_PORT" -lt 1 ] || [ "$AGENT_PORT" -gt 65535 ]; then
    say ERROR CONFIG "AGENT_PORT invalid (need integer 1-65535): '$AGENT_PORT'"; cfg_bad=1
  fi
fi
# [design defaults] - not official values; override via environment/env file
CPU_WARN="${MONITOR_CPU_WARN:-80}"; MEM_WARN="${MONITOR_MEM_WARN:-80}"; DISK_WARN="${MONITOR_DISK_WARN:-80}"
DISK_PATH="${MONITOR_DISK_PATH:-/}"; CPU_INTERVAL="${MONITOR_CPU_INTERVAL:-1}"
is_pct "$CPU_WARN"  || { say ERROR CONFIG "MONITOR_CPU_WARN invalid (0-100): '$CPU_WARN'";  cfg_bad=1; }
is_pct "$MEM_WARN"  || { say ERROR CONFIG "MONITOR_MEM_WARN invalid (0-100): '$MEM_WARN'";  cfg_bad=1; }
is_pct "$DISK_WARN" || { say ERROR CONFIG "MONITOR_DISK_WARN invalid (0-100): '$DISK_WARN'"; cfg_bad=1; }
is_pos "$CPU_INTERVAL" || { say ERROR CONFIG "MONITOR_CPU_INTERVAL invalid (0<x<=10 sec): '$CPU_INTERVAL'"; cfg_bad=1; }
[ -n "$DISK_PATH" ] && [ -d "$DISK_PATH" ] || { say ERROR CONFIG "MONITOR_DISK_PATH not a directory: '$DISK_PATH'"; cfg_bad=1; }
[ "$cfg_bad" -eq 0 ] || finish
say INFO CONFIG "AGENT_HOME=$AGENT_HOME AGENT_PORT=$AGENT_PORT AGENT_UPLOAD_DIR=$AGENT_UPLOAD_DIR AGENT_LOG_DIR=$AGENT_LOG_DIR"
if [ -z "${AGENT_KEY_PATH:-}" ]; then
  say INFO CONFIG "AGENT_KEY_PATH is empty (PENDING in setup); not needed for monitoring, continuing"
fi

# ---------------------------------------------------------------- A. Agent process
# Identification is NOT guessed. Set AGENT_PROCESS_PATTERN (extended regex for pgrep -f)
# once the provided Agent's command line is known. Unset => PENDING (counts as not healthy).
PROC_OK=0; AGENT_PIDS=""
if [ -z "${AGENT_PROCESS_PATTERN:-}" ]; then
  say PENDING PROCESS "agent identification criteria not configured (AGENT_PROCESS_PATTERN unset); not assuming any python process is the Agent"
else
  pids=$(pgrep -f -- "$AGENT_PROCESS_PATTERN" 2>/dev/null); prc=$?
  if [ "$prc" -gt 1 ]; then
    say ERROR PROCESS "pgrep failed (rc=$prc) for pattern '$AGENT_PROCESS_PATTERN'"
  else
    for p in $pids; do [ "$p" = "$$" ] || [ "$p" = "$PPID" ] || AGENT_PIDS="$AGENT_PIDS $p"; done
    AGENT_PIDS="${AGENT_PIDS# }"
    if [ -n "$AGENT_PIDS" ]; then
      PROC_OK=1; say OK PROCESS "agent process matched pattern '$AGENT_PROCESS_PATTERN' pid=[$AGENT_PIDS]"
    else
      say FAIL PROCESS "no process matches pattern '$AGENT_PROCESS_PATTERN'"
    fi
  fi
fi

# ---------------------------------------------------------------- B. TCP LISTEN
# Actual LISTEN socket only. Firewall allow rules (UFW 15034) are NOT considered here,
# and an open port alone does not prove it is the Agent.
ssout=$(ss -H -ltnp 2>&1); src=$?
if [ "$src" -ne 0 ]; then
  say ERROR PORT "ss failed (rc=$src): $ssout"
else
  lst=$(printf '%s\n' "$ssout" | awk -v p="$AGENT_PORT" '$4 ~ (":" p "$") {print}')
  if [ -z "$lst" ]; then
    say FAIL PORT "tcp/$AGENT_PORT not LISTEN"
  else
    addrs=$(printf '%s\n' "$lst" | awk '{print $4}' | sort -u | paste -sd, -)
    lpids=$(printf '%s\n' "$lst" | grep -o 'pid=[0-9]*' | cut -d= -f2 | sort -u | paste -sd' ' -)
    if [ "$PROC_OK" -eq 1 ] && [ -n "$lpids" ]; then
      match=0; for lp in $lpids; do for ap in $AGENT_PIDS; do [ "$lp" = "$ap" ] && match=1; done; done
      if [ "$match" -eq 1 ]; then say OK PORT "tcp/$AGENT_PORT LISTEN on $addrs, listener pid=[$lpids] belongs to matched agent process"
      else say OK PORT "tcp/$AGENT_PORT LISTEN on $addrs, listener pid=[$lpids] differs from matched agent pid=[$AGENT_PIDS]"; fi
    elif [ -n "$lpids" ]; then
      say OK PORT "tcp/$AGENT_PORT LISTEN on $addrs, pid=[$lpids] (LISTEN alone does not prove it is the Agent)"
    else
      say OK PORT "tcp/$AGENT_PORT LISTEN on $addrs, owner not visible to uid=$EUID (LISTEN alone does not prove it is the Agent)"
    fi
  fi
fi

# ---------------------------------------------------------------- C. Firewall (UFW)
# 'ufw status' needs root. Without root the real state is UNKNOWN; ufw.service state or
# ufw.conf ENABLED are only hints (they do not prove packets are being filtered).
hint="ufw.conf ENABLED=$(sed -n 's/^ENABLED=//p' /etc/ufw/ufw.conf 2>/dev/null | head -1)"
UFW_CMD="${MONITOR_UFW_CMD:-ufw}"   # test hook: stub command that prints 'ufw status' output
if ! command -v "$UFW_CMD" >/dev/null 2>&1; then
  say WARNING FIREWALL "ufw command not found (no UFW firewall)"
else
  uout=$("$UFW_CMD" status 2>&1); urc=$?
  first=$(printf '%s\n' "$uout" | head -1)
  if [ "$urc" -eq 0 ] && [ "${first#Status: }" = "active" ]; then
    say OK FIREWALL "ufw active"
  elif [ "$urc" -eq 0 ] && [ "${first#Status: }" = "inactive" ]; then
    say WARNING FIREWALL "ufw inactive"
  elif printf '%s' "$uout" | grep -qiE 'need to be root|permission denied|not permitted'; then
    say UNKNOWN FIREWALL "cannot read ufw status as uid=$EUID (needs root; no sudo granted). hint only: $hint"
  else
    say ERROR FIREWALL "ufw status failed (rc=$urc): $first"
  fi
fi

# ---------------------------------------------------------------- D. Resources
# CPU: two samples of the aggregate 'cpu' line in /proc/stat, CPU_INTERVAL seconds apart.
#      busy% = 100 * (dTotal - dIdle) / dTotal, total = user+nice+system+idle+iowait+irq+softirq+steal,
#      idle = idle+iowait.
STAT1="${MONITOR_PROC_STAT:-/proc/stat}"; STAT2="${MONITOR_PROC_STAT_2:-}"   # *_2: test hook
cpu_line() { awk '/^cpu /{t=0; for(i=2;i<=9;i++) t+=$i; print t, $5+$6; exit}' "$1" 2>/dev/null; }
s1=$(cpu_line "$STAT1")
if [ -n "$STAT2" ]; then s2=$(cpu_line "$STAT2"); else sleep "$CPU_INTERVAL"; s2=$(cpu_line "$STAT1"); fi
if [ -z "$s1" ] || [ -z "$s2" ]; then
  say ERROR CPU "cannot read cpu counters from $STAT1"
else
  cpu=$(awk -v a="$s1" -v b="$s2" 'BEGIN{split(a,x," "); split(b,y," "); dt=y[1]-x[1]; di=y[2]-x[2];
        if (dt<=0) {print "ERR"; exit} printf "%.1f", 100*(dt-di)/dt}')
  if [ "$cpu" = "ERR" ]; then say ERROR CPU "no counter progress between samples (total delta <= 0)"
  elif gt "$cpu" "$CPU_WARN"; then say WARNING CPU "usage=${cpu}% > threshold ${CPU_WARN}% [design default]"
  else say OK CPU "usage=${cpu}% (threshold ${CPU_WARN}% [design default])"; fi
fi

# MEM: (MemTotal - MemAvailable) / MemTotal from /proc/meminfo.
MEMINFO="${MONITOR_MEMINFO:-/proc/meminfo}"
mem=$(awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2} END{ if (t>0 && a!="") printf "%.1f %d %d", 100*(t-a)/t, t, a; else print "ERR"}' "$MEMINFO" 2>/dev/null)
if [ -z "$mem" ] || [ "$mem" = "ERR" ]; then
  say ERROR MEM "cannot read MemTotal/MemAvailable from $MEMINFO"
else
  set -- $mem; mpct=$1; mtot=$2; mavail=$3
  if gt "$mpct" "$MEM_WARN"; then say WARNING MEM "usage=${mpct}% (total=${mtot}kB available=${mavail}kB) > threshold ${MEM_WARN}% [design default]"
  else say OK MEM "usage=${mpct}% (total=${mtot}kB available=${mavail}kB) (threshold ${MEM_WARN}% [design default])"; fi
fi

# DISK: used / (used + avail) for DISK_PATH from 'df -Pk' (same basis as df's Use%, unrounded).
dsk=$(df -Pk "$DISK_PATH" 2>/dev/null | awk 'NR==2{u=$3; a=$4; if (u+a>0) printf "%.1f %s", 100*u/(u+a), $6; else print "ERR"}')
if [ -z "$dsk" ] || [ "$dsk" = "ERR" ]; then
  say ERROR DISK "df failed for $DISK_PATH"
else
  set -- $dsk; dpct=$1; dmnt=$2
  if gt "$dpct" "$DISK_WARN"; then say WARNING DISK "usage=${dpct}% path=$DISK_PATH mount=$dmnt > threshold ${DISK_WARN}% [design default]"
  else say OK DISK "usage=${dpct}% path=$DISK_PATH mount=$dmnt (threshold ${DISK_WARN}% [design default])"; fi
fi

finish
