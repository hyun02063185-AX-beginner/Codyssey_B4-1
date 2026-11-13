#!/bin/bash
# monitor-cron.sh - manage the agent-admin crontab entry that runs monitor.sh every minute.
# Run inside the Ubuntu Machine as root:   sudo scripts/monitor-cron.sh install|pause|resume|remove|status
#
# - Uses agent-admin's own crontab (not root's). Other entries in that crontab are preserved.
# - Only the block between the BEGIN/END markers is managed; re-running 'install' replaces that block
#   (never duplicates it).
# - The job redirects stdout/stderr to /dev/null: monitor.sh writes its own monitor.log, so cron has
#   nothing to mail. MONITOR_TRIGGER=cron makes cron runs identifiable in the log (trigger=cron).
# - No login-shell environment is used; monitor.sh loads /etc/default/agent-app itself.
set -u
CRON_USER="${MONITOR_CRON_USER:-agent-admin}"
JOB='* * * * * MONITOR_TRIGGER=cron /opt/agent-app/bin/monitor.sh >/dev/null 2>&1'
BEGIN='# BEGIN B4-1 monitor (managed by scripts/monitor-cron.sh; do not edit inside)'
END='# END B4-1 monitor'

[ "$(id -u)" -eq 0 ] || { echo "run as root (sudo)" >&2; exit 2; }
id "$CRON_USER" >/dev/null 2>&1 || { echo "user not found: $CRON_USER" >&2; exit 2; }

current() { crontab -u "$CRON_USER" -l 2>/dev/null || true; }
strip()   { awk -v b="$BEGIN" -v e="$END" '$0==b{skip=1} !skip{print} $0==e{skip=0}'; }
apply() { # state: active|paused|none
  local tmp; tmp=$(mktemp); current | strip > "$tmp"
  # drop trailing blank lines so repeated installs do not grow the file
  sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$tmp"
  case "$1" in
    active) { echo "$BEGIN"; echo "$JOB"; echo "$END"; } >> "$tmp";;
    paused) { echo "$BEGIN"; echo "#PAUSED# $JOB"; echo "$END"; } >> "$tmp";;
    none)   :;;
  esac
  if [ ! -s "$tmp" ]; then crontab -u "$CRON_USER" -r 2>/dev/null || true
  else crontab -u "$CRON_USER" "$tmp" || { rm -f "$tmp"; echo "crontab install failed" >&2; exit 1; }; fi
  rm -f "$tmp"
}
status() {
  local n; n=$(current | grep -c "^$BEGIN\$")
  echo "user=$CRON_USER managed_blocks=$n"
  current | awk -v b="$BEGIN" -v e="$END" '$0==b{p=1} p{print "  " $0} $0==e{p=0}'
  if current | grep -qxF "$JOB"; then echo "state=ACTIVE"
  elif current | grep -qxF "#PAUSED# $JOB"; then echo "state=PAUSED"
  else echo "state=NOT_INSTALLED"; fi
}
case "${1:-status}" in
  install|resume) apply active; status;;
  pause)          apply paused; status;;
  remove)         apply none;   status;;
  status)         status;;
  *) echo "usage: $0 install|pause|resume|remove|status" >&2; exit 2;;
esac
