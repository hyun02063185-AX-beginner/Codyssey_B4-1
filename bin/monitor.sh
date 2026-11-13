#!/bin/bash
# monitor.sh - B4-1 health check (Bash only).
# Deploy path: $AGENT_HOME/bin/monitor.sh   (/opt/agent-app/bin/monitor.sh)
#
# Checks: Agent process, TCP LISTEN, UFW state, CPU/MEM/DISK.
# Output: stdout AND appended to $AGENT_LOG_DIR/monitor.log (written by this script itself;
#         override path: MONITOR_LOG_FILE). Log format is a temporary design format
#         [official format unconfirmed]. cron registration / log rotation are separate tasks.
#         No secret values are ever printed or logged (only fixed fields, never AGENT_KEY_PATH's value).
#
# Exit codes:
#   0  healthy: Agent process confirmed AND 0.0.0.0:PORT LISTEN AND the listener PID is
#      confirmed to be the Agent process (warnings/unknown allowed)
#   1  health check failed or cannot be confirmed (process missing, process identification
#      not configured [PENDING], port not LISTEN / wrong bind / PID mismatch / owner or
#      IPv4 reachability unconfirmed [PENDING])
#   2  monitoring/config error (bad config, missing tool, collection failure, log write failure)
#      -- only when no confirmed failure (exit 1 takes precedence)
#
# Config is loaded explicitly from /etc/default/agent-app (override: MONITOR_ENV_FILE).
# It never relies on login-shell files. Thresholds are [design defaults], not official values.

set -u
export LC_ALL=C PATH=/usr/sbin:/usr/bin:/sbin:/bin

ENV_FILE="${MONITOR_ENV_FILE:-/etc/default/agent-app}"

FAILS=0; WARNS=0; UNKNOWNS=0; PENDINGS=0; ERRORS=0

ts()  { date '+%Y-%m-%d %H:%M:%S'; }

# ---- logging -------------------------------------------------------------
# Every line printed to stdout is also appended to monitor.log by this script itself
# (no reliance on cron redirection). Lines produced before the log path is known are
# buffered and flushed once the log is opened. The log is opened in append mode only
# (never truncated). Log problems are reported as ERROR (exit 2 unless a real failure
# already makes the exit code 1) - they never silently pass.
# LOG_STATE: pending (path not known yet) | ok | failed | disabled
LOG_STATE=pending; LOG_FILE=""; LOG_BUF=()
umask 007   # new log file: 0660 (when the directory has no default ACL)

log_write() { # line  (state ok: append via fd 9; pending: buffer)
  case "$LOG_STATE" in
    pending) LOG_BUF+=("$1");;
    ok) if ! printf '%s\n' "$1" >&9 2>/dev/null; then
          LOG_STATE=failed; say ERROR LOG "write to $LOG_FILE failed; log is incomplete from this line on"
        fi;;
  esac
}
bump() {
  case "$1" in
    FAIL) FAILS=$((FAILS+1));; WARNING) WARNS=$((WARNS+1));;
    UNKNOWN) UNKNOWNS=$((UNKNOWNS+1));; PENDING) PENDINGS=$((PENDINGS+1));;
    ERROR) ERRORS=$((ERRORS+1));;
  esac
}
say() { # level category message  -> stdout + log (identical text)
  local msg="${3//$'\n'/ }" line
  line="$(ts) [$1] $2 $msg"
  printf '%s\n' "$line"
  bump "$1"
  log_write "$line"
}
init_log() {
  local dir="${AGENT_LOG_DIR:-}" err
  LOG_FILE="${MONITOR_LOG_FILE:-}"
  [ -z "$LOG_FILE" ] && [ -n "$dir" ] && LOG_FILE="$dir/monitor.log"
  if [ -z "$LOG_FILE" ]; then LOG_STATE=disabled; return; fi
  if [ -L "$LOG_FILE" ]; then
    LOG_STATE=failed; say ERROR LOG "refusing symlink log path: $LOG_FILE"; return
  fi
  if [ -e "$LOG_FILE" ] && [ ! -f "$LOG_FILE" ] && [ "${MONITOR_LOG_ALLOW_SPECIAL:-0}" != 1 ]; then
    LOG_STATE=failed; say ERROR LOG "log path exists but is not a regular file: $LOG_FILE"; return
  fi
  # open for append (creates the file if missing; never truncates)
  err=$( { : >>"$LOG_FILE"; } 2>&1 ) || {
    LOG_STATE=failed; say ERROR LOG "cannot open log for append: ${err##*: }"; return; }
  { exec 9>>"$LOG_FILE"; } 2>/dev/null || { LOG_STATE=failed; say ERROR LOG "cannot open log fd: $LOG_FILE"; return; }
  LOG_STATE=ok
  local l
  for l in "${LOG_BUF[@]}"; do
    [ "$LOG_STATE" = ok ] && log_write "$l"
  done
  LOG_BUF=()
}
summary_line() {
  local lg
  case "$LOG_STATE" in ok) lg="$LOG_FILE";; failed) lg="FAILED";; *) lg="disabled";; esac
  printf '%s [INFO] SUMMARY result=%s exit=%s fail=%s pending=%s warning=%s unknown=%s error=%s log=%s' \
    "$(ts)" "$1" "$2" "$FAILS" "$PENDINGS" "$WARNS" "$UNKNOWNS" "$ERRORS" "$lg"
}
verdict() {
  if [ $((FAILS+PENDINGS)) -gt 0 ]; then V_CODE=1; V_RESULT=UNHEALTHY
  elif [ "$ERRORS" -gt 0 ]; then V_CODE=2; V_RESULT=MONITOR_ERROR
  else V_CODE=0; V_RESULT=HEALTHY; fi
}
finish() {
  local line
  verdict; line=$(summary_line "$V_RESULT" "$V_CODE")
  if [ "$LOG_STATE" = ok ]; then
    # the summary must reach the log too; if that write fails the verdict is recomputed
    if ! printf '%s\n' "$line" >&9 2>/dev/null; then
      LOG_STATE=failed
      local el; el="$(ts) [ERROR] LOG write to $LOG_FILE failed while writing SUMMARY"
      printf '%s\n' "$el"; ERRORS=$((ERRORS+1))
      verdict; line=$(summary_line "$V_RESULT" "$V_CODE")
    fi
  fi
  printf '%s\n' "$line"
  exit "$V_CODE"
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
# trigger: who started this run (crontab sets MONITOR_TRIGGER=cron); anything else is logged as given
# (sanitized, max 16 chars), default "manual". groups: effective supplementary groups of this process.
TRIG="${MONITOR_TRIGGER:-manual}"; TRIG="${TRIG//[^A-Za-z0-9_-]/_}"; TRIG="${TRIG:0:16}"
say INFO START "user=$(id -un) uid=$EUID groups=$(id -Gn | tr ' ' ,) trigger=$TRIG host=$(hostname) env_file=$ENV_FILE"
if [ ! -r "$ENV_FILE" ]; then
  LOG_STATE=disabled; say ERROR CONFIG "env file not readable: $ENV_FILE (log disabled: AGENT_LOG_DIR unknown)"; finish
fi
# shellcheck disable=SC1090
set -a; . "$ENV_FILE"; set +a
init_log

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
else
  say INFO CONFIG "AGENT_KEY_PATH is set (value intentionally not printed or logged)"
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
# Real LISTEN sockets only (ss). Firewall allow rules (UFW 15034) are NOT considered, and an
# open port alone does not prove it is the Agent. Requirements for a healthy port check:
#   1. bind: a 0.0.0.0:PORT (IPv4 all-interfaces) listener exists.
#        - 127.x / [::1]            -> loopback only      : FAIL (not reachable from other hosts)
#        - specific non-wildcard IP -> not all-interfaces : FAIL
#        - [::] or '*' only         -> IPv4 reachability is NOT confirmed (depends on the
#          socket's IPV6_V6ONLY setting, which ss does not show); not treated as equal to
#          0.0.0.0 -> PENDING
#   2. owner (only when the Agent process was confirmed): the PID(s) holding the socket must
#      match the matched Agent PID(s).
#        - visible PID not in the Agent PIDs     -> FAIL (port held by someone else)
#        - PID not visible to this uid (ss -p shows only own / root-visible sockets)
#                                                -> PENDING (unconfirmed, never "OK")
SS_FILE="${MONITOR_SS_FILE:-}"   # test hook: file with 'ss -H -ltnp' formatted lines
if [ -n "$SS_FILE" ]; then ssout=$(cat "$SS_FILE" 2>&1); src=$?; else ssout=$(ss -H -ltnp 2>&1); src=$?; fi
if [ "$src" -ne 0 ]; then
  say ERROR PORT "ss failed (rc=$src): $ssout"
else
  lst=$(printf '%s\n' "$ssout" | awk -v p="$AGENT_PORT" '$4 ~ (":" p "$") {print}')
  if [ -z "$lst" ]; then
    say FAIL PORT "tcp/$AGENT_PORT not LISTEN"
  else
    # classify bind addresses (strip :PORT and %iface scope)
    v4all=0; v6any=0; loop=0; spec=0; addrs=""
    while IFS= read -r line; do
      la=$(printf '%s' "$line" | awk '{print $4}'); addrs="$addrs $la"
      h=${la%:*}; h=${h%%%*}
      case "$h" in
        0.0.0.0)          v4all=1;;
        "[::]"|"*")       v6any=1;;
        127.*|"[::1]")    loop=1;;
        *)                spec=1;;
      esac
    done <<EOF_LST
$lst
EOF_LST
    addrs=${addrs# }
    # owner PIDs
    vis_pids=""; invisible=0
    while IFS= read -r line; do
      lp=$(printf '%s' "$line" | grep -o 'pid=[0-9]*' | cut -d= -f2)
      if [ -z "$lp" ]; then invisible=1; else vis_pids="$vis_pids $lp"; fi
    done <<EOF_LST
$lst
EOF_LST
    vis_pids=$(printf '%s\n' $vis_pids | sort -un | paste -sd' ' -)

    bind_state=ok
    if [ "$v4all" -eq 1 ]; then bind_state=ok
    elif [ "$v6any" -eq 1 ]; then bind_state=v6only
    else bind_state=bad; fi

    if [ "$bind_state" = bad ]; then
      what="loopback only"; [ "$loop" -eq 0 ] && what="specific address only"
      say FAIL PORT "tcp/$AGENT_PORT LISTEN on [$addrs] but required 0.0.0.0:$AGENT_PORT binding is missing ($what)"
    elif [ "$bind_state" = v6only ]; then
      say PENDING PORT "tcp/$AGENT_PORT LISTEN on [$addrs] has no 0.0.0.0 binding; IPv6 wildcard alone does not confirm IPv4 reachability"
    else
      # bind OK; now ownership
      if [ "$PROC_OK" -ne 1 ]; then
        say OK PORT "tcp/$AGENT_PORT LISTEN on 0.0.0.0 [$addrs]; owner not evaluated (no confirmed agent process) - LISTEN alone does not prove it is the Agent"
      else
        other=""; for lp in $vis_pids; do hit=0; for ap in $AGENT_PIDS; do [ "$lp" = "$ap" ] && hit=1; done; [ "$hit" -eq 0 ] && other="$other $lp"; done
        other=${other# }
        if [ -n "$other" ]; then
          say FAIL PORT "tcp/$AGENT_PORT LISTEN on [$addrs] held by pid=[$other], not by matched agent pid=[$AGENT_PIDS]"
        elif [ "$invisible" -eq 1 ]; then
          say PENDING PORT "tcp/$AGENT_PORT LISTEN on 0.0.0.0 [$addrs] but owner PID not visible to uid=$EUID; cannot confirm it belongs to agent pid=[$AGENT_PIDS]"
        else
          say OK PORT "tcp/$AGENT_PORT LISTEN on 0.0.0.0 [$addrs], owner pid=[$vis_pids] matches agent pid=[$AGENT_PIDS]"
        fi
      fi
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
