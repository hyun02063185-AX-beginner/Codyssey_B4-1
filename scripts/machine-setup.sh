#!/bin/bash
# machine-setup.sh - runs INSIDE the Ubuntu Machine as root. Normally started by
# scripts/bootstrap-orbstack.sh (Mac side), which streams the needed repo files and passes --src.
#
#   machine-setup.sh check    --src DIR   read-only: compare the machine with the desired B4-1 state
#   machine-setup.sh apply    --src DIR   apply every step idempotently (stops at the first failing step)
#   machine-setup.sh snapshot             print a normalized state description (for diffing machines)
#
# Steps (in order): preflight packages ssh ufw accounts dirs envfile monitor logfile logrotate cron verify agent
# Each step has a check function (desired state reached?) and an apply function. 'apply' runs apply only
# when the check reports a difference, then re-checks. Existing data (logs, crontab entries of other
# jobs, files in managed directories) is never deleted or truncated.
#
# Not handled on purpose: SSH private keys / API keys / passwords (never generated or stored),
# sudo rights for agent-* accounts (never granted), the provided Agent (not available -> PENDING).
set -u
export LC_ALL=C PATH=/usr/sbin:/usr/bin:/sbin:/bin DEBIAN_FRONTEND=noninteractive

MODE="${1:-}"; [ $# -gt 0 ] && shift
SRC=""
while [ $# -gt 0 ]; do
  case "$1" in --src) SRC="${2:-}"; shift 2;; *) echo "unknown argument: $1" >&2; exit 2;; esac
done
[ "$(id -u)" -eq 0 ] || { echo "must run as root (inside the Machine)" >&2; exit 2; }

# ---- desired state (approved lab design; not verified against the official mission text) ----
SSH_PORT=20022; AGENT_PORT=15034
AGENT_HOME=/opt/agent-app; LOG_DIR=/var/log/agent-app; LOG_FILE=$LOG_DIR/monitor.log
ENV_FILE=/etc/default/agent-app; MONITOR=$AGENT_HOME/bin/monitor.sh
SSH_FRAGMENT=/etc/ssh/sshd_config.d/10-b4-mission.conf
LOGROTATE_CONF=/etc/logrotate.d/agent-app
PACKAGES="openssh-server ufw acl cron logrotate iproute2 procps"
USERS="agent-admin agent-dev agent-test"
GROUPS_="agent-common agent-core"
# group -> members (exact set)
MEMBERS_common="agent-admin agent-dev"
MEMBERS_core="agent-admin"
STEPS="preflight packages ssh ufw accounts dirs envfile monitor logfile logrotate cron verify agent"

REASONS=(); NOTES=()
reason() { REASONS+=("$*"); }
note()   { NOTES+=("$*"); }
sorted() { tr ' ' '\n' | sed '/^$/d' | sort | tr '\n' ' ' | sed 's/ $//'; }
file_eq() { [ -f "$1" ] && [ -f "$2" ] && cmp -s "$1" "$2"; }
stat_is() { [ "$(stat -c '%U:%G %a' "$1" 2>/dev/null)" = "$2" ]; }   # "owner:group mode"
need_src() { [ -n "$SRC" ] && [ -d "$SRC" ] || { echo "--src DIR required" >&2; exit 2; }; }
acl_has() { # path pattern...
  local p="$1"; shift; local out; out=$(getfacl -p "$p" 2>/dev/null) || { reason "cannot read ACL of $p"; return; }
  local pat; for pat in "$@"; do printf '%s\n' "$out" | grep -qxE "$pat" || reason "$p: ACL entry missing: ${pat//\\/}"; done; }

# ============================================================== preflight
check_preflight() {
  . /etc/os-release 2>/dev/null
  [ "${ID:-}" = ubuntu ] && [ "${VERSION_ID:-}" = 24.04 ] || reason "OS is '${PRETTY_NAME:-unknown}', expected Ubuntu 24.04"
  [ -d /run/systemd/system ] || reason "systemd is not PID 1"
  note "arch=$(uname -m) os=${PRETTY_NAME:-?}"
  if [ "$MODE" != snapshot ]; then
    need_src; local f
    for f in bin/monitor.sh config/sshd-b4-mission.conf config/etc-default-agent-app.example config/etc-logrotate.d-agent-app scripts/monitor-cron.sh; do
      [ -f "$SRC/$f" ] || reason "repo file missing in --src: $f"; done
  fi
}
apply_preflight() { return 1; }   # cannot be fixed automatically

# ============================================================== packages
check_packages() {
  local p missing=""
  for p in $PACKAGES; do dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q "install ok installed" || missing="$missing $p"; done
  [ -z "$missing" ] || reason "packages missing:$missing"
}
apply_packages() {
  local p missing=""
  for p in $PACKAGES; do dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q "install ok installed" || missing="$missing $p"; done
  apt-get update -q >/dev/null || return 1
  # shellcheck disable=SC2086
  apt-get install -y -q $missing >/dev/null || return 1
}

# ============================================================== ssh
SSH_CHANGED=0
check_ssh() {
  need_src
  if [ -f "$SSH_FRAGMENT" ]; then file_eq "$SSH_FRAGMENT" "$SRC/config/sshd-b4-mission.conf" || reason "$SSH_FRAGMENT differs from repo"
    stat_is "$SSH_FRAGMENT" "root:root 644" || reason "$SSH_FRAGMENT owner/mode != root:root 644"
  else reason "$SSH_FRAGMENT missing"; fi
  if command -v sshd >/dev/null 2>&1; then
    local eff; eff=$(sshd -T 2>&1) || { reason "sshd -T failed: $(echo "$eff" | head -1)"; eff=""; }
    if [ -n "$eff" ]; then
      [ "$(echo "$eff" | awk '$1=="port"{print $2}' | sort -u | tr '\n' ' ' | sed 's/ $//')" = "$SSH_PORT" ] || reason "effective sshd port(s) != $SSH_PORT"
      [ "$(echo "$eff" | awk '$1=="permitrootlogin"{print $2}')" = no ] || reason "effective PermitRootLogin != no"
    fi
  else reason "sshd not installed"; fi
  systemctl is-active --quiet ssh.service || reason "ssh.service not active"
  systemctl is-enabled --quiet ssh.service 2>/dev/null || reason "ssh.service not enabled"
  if systemctl is-active --quiet ssh.socket 2>/dev/null; then reason "ssh.socket is active (would listen on 22)"; fi
  systemctl is-enabled --quiet ssh.socket 2>/dev/null && reason "ssh.socket is enabled"
  ss -H -ltn 2>/dev/null | awk '{print $4}' | grep -qE ":$SSH_PORT\$" || reason "nothing LISTENs on tcp/$SSH_PORT"
  ss -H -ltn 2>/dev/null | awk '{print $4}' | grep -qE ':22$' && reason "something LISTENs on tcp/22"
  note "OrbStack management SSH (orb -m / ssh <machine>@orb) is separate from this sshd and is not touched"
}
apply_ssh() {
  need_src
  install -d -m 0755 /run/sshd || return 1
  local bak=""
  if [ -f "$SSH_FRAGMENT" ]; then bak=$(mktemp); cp -p "$SSH_FRAGMENT" "$bak"; fi
  install -o root -g root -m 0644 "$SRC/config/sshd-b4-mission.conf" "$SSH_FRAGMENT" || return 1
  if ! sshd -t 2>/tmp/b4-sshd-t.err; then
    echo "      sshd -t failed: $(head -2 /tmp/b4-sshd-t.err | tr '\n' ' ')" >&2
    if [ -n "$bak" ]; then install -o root -g root -m 0644 "$bak" "$SSH_FRAGMENT"; else rm -f "$SSH_FRAGMENT"; fi
    rm -f "$bak" /tmp/b4-sshd-t.err; return 1     # existing sshd keeps running with its old config
  fi
  rm -f "$bak" /tmp/b4-sshd-t.err
  systemctl disable --now ssh.socket >/dev/null 2>&1 || true
  systemctl enable ssh.service >/dev/null 2>&1 || return 1
  systemctl restart ssh.service || return 1
  sleep 1
}

# ============================================================== ufw
check_ufw() {
  command -v ufw >/dev/null 2>&1 || { reason "ufw not installed"; return; }
  local st; st=$(ufw status verbose 2>&1)
  echo "$st" | grep -q '^Status: active' || reason "ufw is not active"
  echo "$st" | grep -q '^Default: deny (incoming), allow (outgoing)' || reason "ufw default policy != deny(incoming)/allow(outgoing)"
  local ports; ports=$(ufw status 2>/dev/null | sed -n 's/^\([0-9][0-9]*\/[a-z]*\).*ALLOW.*/\1/p' | sort -u | tr '\n' ' ' | sed 's/ $//')
  [ "$ports" = "$AGENT_PORT/tcp $SSH_PORT/tcp" ] || reason "allowed ports = [$ports], expected [$AGENT_PORT/tcp $SSH_PORT/tcp] (extra rules are reported, never deleted)"
  [ "$(ufw status 2>/dev/null | grep -c '(v6).*ALLOW')" -ge 2 ] || reason "IPv6 allow rules missing"
  systemctl is-enabled --quiet ufw.service 2>/dev/null || reason "ufw.service not enabled (rules would not return after restart)"
}
apply_ufw() {
  ufw default deny incoming >/dev/null || return 1
  ufw default allow outgoing >/dev/null || return 1
  ufw allow "$SSH_PORT/tcp" comment SSH >/dev/null || return 1      # SSH rule FIRST, before enabling
  ufw allow "$AGENT_PORT/tcp" comment Agent >/dev/null || return 1
  ufw show added 2>/dev/null | grep -q "allow $SSH_PORT/tcp" || { echo "      SSH rule not present; refusing to enable ufw" >&2; return 1; }
  systemctl enable ufw.service >/dev/null 2>&1 || true
  ufw --force enable >/dev/null || return 1
}

# ============================================================== accounts
members_of() { getent group "$1" | cut -d: -f4 | tr ',' ' ' | sorted; }
check_accounts() {
  local g u
  for g in $GROUPS_; do getent group "$g" >/dev/null || reason "group $g missing"; done
  for u in $USERS; do
    if getent passwd "$u" >/dev/null; then
      [ "$(getent passwd "$u" | cut -d: -f6,7)" = "/home/$u:/bin/bash" ] || reason "$u home/shell != /home/$u:/bin/bash"
      [ -d "/home/$u" ] || reason "/home/$u missing"
      id -nG "$u" | tr ' ' '\n' | grep -qxE 'sudo|adm|root' && reason "$u is in a privileged group (sudo/adm/root)"
      sudo -l -U "$u" 2>/dev/null | grep -q 'is not allowed to run sudo' || reason "$u may have sudo rights"
      [ "$(passwd -S "$u" 2>/dev/null | awk '{print $2}')" = L ] || note "$u password is not locked (left as is: apply locks it only when creating the user)"
    else reason "user $u missing"; fi
  done
  getent group agent-common >/dev/null && [ "$(members_of agent-common)" = "$(echo $MEMBERS_common | sorted)" ] || reason "agent-common members = [$(members_of agent-common 2>/dev/null)], expected [$MEMBERS_common]"
  getent group agent-core >/dev/null && [ "$(members_of agent-core)" = "$(echo $MEMBERS_core | sorted)" ] || reason "agent-core members = [$(members_of agent-core 2>/dev/null)], expected [$MEMBERS_core]"
}
apply_accounts() {
  local g u
  for g in $GROUPS_; do getent group "$g" >/dev/null || groupadd "$g" || return 1; done          # groups first (GID 1000, 1001 on a fresh machine)
  for u in $USERS; do
    if ! getent passwd "$u" >/dev/null; then
      useradd -m -s /bin/bash -c "B4-1 mission account" "$u" || return 1
      passwd -l "$u" >/dev/null || return 1                                                      # locked password; no key/password is created
    fi
  done
  usermod -aG agent-common,agent-core agent-admin || return 1       # -a: only adds, other memberships are preserved
  usermod -aG agent-common agent-dev || return 1
  # extra members cannot be fixed safely/automatically
  [ "$(members_of agent-common)" = "$(echo $MEMBERS_common | sorted)" ] && [ "$(members_of agent-core)" = "$(echo $MEMBERS_core | sorted)" ] || { echo "      unexpected extra group members; remove manually (gpasswd -d USER GROUP)" >&2; return 1; }
}

# ============================================================== dirs
check_dirs() {
  stat_is "$AGENT_HOME" "root:root 755" || reason "$AGENT_HOME != root:root 755 ($(stat -c '%U:%G %a' "$AGENT_HOME" 2>/dev/null))"
  stat_is "$AGENT_HOME/upload_files" "agent-admin:agent-common 2770" || reason "upload_files != agent-admin:agent-common 2770 ($(stat -c '%U:%G %a' "$AGENT_HOME/upload_files" 2>/dev/null))"
  stat_is "$AGENT_HOME/api_keys" "root:agent-core 2770" || reason "api_keys != root:agent-core 2770 ($(stat -c '%U:%G %a' "$AGENT_HOME/api_keys" 2>/dev/null))"
  stat_is "$LOG_DIR" "root:agent-core 2770" || reason "$LOG_DIR != root:agent-core 2770 ($(stat -c '%U:%G %a' "$LOG_DIR" 2>/dev/null))"
  command -v getfacl >/dev/null 2>&1 || { reason "getfacl missing"; return; }
  acl_has "$AGENT_HOME/upload_files" 'group:agent-common:rwx' 'mask::rwx' 'other::---' 'default:group:agent-common:rwx' 'default:mask::rwx' 'default:other::---'
  acl_has "$AGENT_HOME/api_keys" 'group:agent-core:rwx' 'mask::rwx' 'other::---' 'default:group:agent-core:rwx' 'default:mask::rwx' 'default:other::---'
  acl_has "$LOG_DIR" 'group:agent-core:rwx' 'mask::rwx' 'other::---' 'default:group:agent-core:rwx' 'default:mask::rwx' 'default:other::---'
}
apply_dirs() {
  install -d -o root -g root -m 0755 "$AGENT_HOME" || return 1
  install -d -o agent-admin -g agent-common -m 2770 "$AGENT_HOME/upload_files" || return 1
  install -d -o root -g agent-core -m 2770 "$AGENT_HOME/api_keys" || return 1
  install -d -o root -g agent-core -m 2770 "$LOG_DIR" || return 1
  setfacl -m  g:agent-common:rwx,m::rwx,o::--- "$AGENT_HOME/upload_files" && setfacl -dm g:agent-common:rwx,m::rwx,o::--- "$AGENT_HOME/upload_files" || return 1
  local d; for d in "$AGENT_HOME/api_keys" "$LOG_DIR"; do
    setfacl -m  g:agent-core:rwx,m::rwx,o::--- "$d" && setfacl -dm g:agent-core:rwx,m::rwx,o::--- "$d" || return 1; done
}

# ============================================================== envfile
env_val() { sed -n "s/^$1=//p" "$ENV_FILE" | tail -1; }
check_envfile() {
  need_src
  if [ ! -f "$ENV_FILE" ]; then reason "$ENV_FILE missing"; return; fi
  stat_is "$ENV_FILE" "root:root 644" || reason "$ENV_FILE != root:root 644"
  local k exp
  for k in AGENT_HOME AGENT_PORT AGENT_UPLOAD_DIR AGENT_LOG_DIR; do
    exp=$(sed -n "s/^$k=//p" "$SRC/config/etc-default-agent-app.example" | tail -1)
    [ "$(env_val $k)" = "$exp" ] || reason "$ENV_FILE: $k='$(env_val $k)' expected '$exp'"
  done
  grep -q '^AGENT_KEY_PATH=' "$ENV_FILE" || reason "$ENV_FILE: AGENT_KEY_PATH not defined"
  [ -z "$(env_val AGENT_KEY_PATH)" ] && note "AGENT_KEY_PATH is empty (PENDING: needs the provided Agent)"
  grep -v '^[[:space:]]*#' "$ENV_FILE" | grep -qiE '(secret|password|token|BEGIN .*PRIVATE)' && reason "$ENV_FILE contains secret-looking values"
}
apply_envfile() {
  need_src
  if [ -e "$ENV_FILE" ]; then
    echo "      $ENV_FILE exists with different content; NOT overwritten (merge by hand, example: config/etc-default-agent-app.example)" >&2
    return 1
  fi
  install -o root -g root -m 0644 "$SRC/config/etc-default-agent-app.example" "$ENV_FILE"
}

# ============================================================== monitor
check_monitor() {
  need_src
  stat_is "$AGENT_HOME/bin" "root:root 755" || reason "$AGENT_HOME/bin != root:root 755"
  [ -f "$MONITOR" ] || { reason "$MONITOR missing"; return; }
  stat_is "$MONITOR" "root:agent-admin 750" || reason "$MONITOR != root:agent-admin 750 ($(stat -c '%U:%G %a' "$MONITOR"))"
  file_eq "$MONITOR" "$SRC/bin/monitor.sh" || reason "$MONITOR differs from repo bin/monitor.sh"
  bash -n "$MONITOR" 2>/dev/null || reason "$MONITOR has a syntax error"
}
apply_monitor() {
  need_src
  bash -n "$SRC/bin/monitor.sh" || return 1
  install -d -o root -g root -m 0755 "$AGENT_HOME/bin" || return 1
  install -o root -g agent-admin -m 0750 "$SRC/bin/monitor.sh" "$MONITOR"
}

# ============================================================== logfile (never truncates)
check_logfile() {
  if [ -L "$LOG_FILE" ]; then reason "$LOG_FILE is a symlink"; return; fi
  [ -f "$LOG_FILE" ] || { reason "$LOG_FILE missing"; return; }
  stat_is "$LOG_FILE" "agent-admin:agent-core 660" || reason "$LOG_FILE != agent-admin:agent-core 660 ($(stat -c '%U:%G %a' "$LOG_FILE"))"
  note "monitor.log: $(wc -l < "$LOG_FILE") lines, $(stat -c %s "$LOG_FILE") bytes (content is never modified by this script)"
}
apply_logfile() {
  [ -L "$LOG_FILE" ] && return 1
  if [ ! -e "$LOG_FILE" ]; then install -o agent-admin -g agent-core -m 0660 /dev/null "$LOG_FILE" || return 1
  else chown agent-admin:agent-core "$LOG_FILE" && chmod 0660 "$LOG_FILE"; fi       # owner/mode only, content untouched
}

# ============================================================== logrotate
check_logrotate() {
  need_src
  [ -f "$LOGROTATE_CONF" ] || { reason "$LOGROTATE_CONF missing"; return; }
  file_eq "$LOGROTATE_CONF" "$SRC/config/etc-logrotate.d-agent-app" || reason "$LOGROTATE_CONF differs from repo"
  stat_is "$LOGROTATE_CONF" "root:root 644" || reason "$LOGROTATE_CONF != root:root 644"
  command -v logrotate >/dev/null 2>&1 || { reason "logrotate missing"; return; }
  logrotate -d "$LOGROTATE_CONF" 2>&1 | grep -qi 'error' && reason "logrotate -d reports an error for $LOGROTATE_CONF"
  systemctl is-active --quiet logrotate.timer 2>/dev/null || reason "logrotate.timer not active (size is only checked when logrotate runs)"
  note "logrotate size check runs via logrotate.timer (daily); the log can exceed 10 MiB between checks"
}
apply_logrotate() {
  need_src
  install -o root -g root -m 0644 "$SRC/config/etc-logrotate.d-agent-app" "$LOGROTATE_CONF" || return 1
  systemctl enable --now logrotate.timer >/dev/null 2>&1 || true
}

# ============================================================== cron
check_cron() {
  need_src
  systemctl is-active --quiet cron.service || reason "cron.service not active"
  systemctl is-enabled --quiet cron.service 2>/dev/null || reason "cron.service not enabled"
  getent passwd agent-admin >/dev/null || { reason "agent-admin missing"; return; }
  local st; st=$(MONITOR_CRON_USER=agent-admin bash "$SRC/scripts/monitor-cron.sh" status 2>&1)
  echo "$st" | grep -q '^state=ACTIVE' || reason "agent-admin crontab job is not ACTIVE ($(echo "$st" | grep '^state='))"
  echo "$st" | grep -q 'managed_blocks=1' || reason "managed cron blocks != 1"
  echo "$st" | grep -qF '* * * * * MONITOR_TRIGGER=cron /opt/agent-app/bin/monitor.sh >/dev/null 2>&1' || reason "cron job line differs"
  [ "$(crontab -u root -l 2>/dev/null | grep -c monitor.sh)" = 0 ] || reason "root crontab contains monitor.sh (must be agent-admin's)"
}
apply_cron() {
  need_src
  systemctl enable --now cron.service >/dev/null 2>&1 || return 1
  MONITOR_CRON_USER=agent-admin bash "$SRC/scripts/monitor-cron.sh" install >/dev/null
}

# ============================================================== verify (runs monitor.sh against a TEMP log)
check_verify() {
  [ -x "$MONITOR" ] || { reason "$MONITOR not executable"; return; }
  local t; t=$(mktemp -d /tmp/b4-verify.XXXXXX); chmod 777 "$t"
  runuser -u agent-admin -- env -i PATH=/usr/bin:/bin MONITOR_TRIGGER=bootstrap MONITOR_LOG_FILE="$t/m.log" "$MONITOR" >"$t/out" 2>&1; local rc=$?
  local sum; sum=$(grep 'SUMMARY' "$t/out" | sed 's/^[0-9-]* [0-9:]* //')
  case $rc in
    0) note "monitor.sh exit=0 (HEALTHY)";;
    1) note "monitor.sh exit=1 = expected failure detection while the provided Agent is absent: $sum";;
    *) reason "monitor.sh exit=$rc (monitoring/config error): $sum";;
  esac
  [ "$(wc -l < "$t/m.log" 2>/dev/null)" = "$(wc -l < "$t/out")" ] || reason "temp log lines != terminal lines"
  grep -q 'groups=.*agent-core' "$t/out" || reason "monitor.sh process lacks agent-core group"
  rm -rf --one-file-system -- "$t"
}
apply_verify() { return 1; }

# ============================================================== agent (PENDING)
check_agent() {
  note "PENDING: provided Agent original is not available; not installed, not faked"
  note "PENDING: AGENT_PROCESS_PATTERN is $( [ -n "$(env_val AGENT_PROCESS_PATTERN 2>/dev/null)" ] && echo set || echo 'unset (monitor.sh reports PENDING PROCESS, exit 1)')"
  note "PENDING: AGENT_KEY_PATH, listening 0.0.0.0:$AGENT_PORT, Boot Sequence"
}
apply_agent() { return 0; }

# ============================================================== snapshot (normalized, no timestamps)
snapshot() {
  echo "## os"; . /etc/os-release; echo "$PRETTY_NAME"; uname -m
  echo "## packages"; for p in $PACKAGES; do echo "$p $(dpkg-query -W -f='${Version}' $p 2>/dev/null)"; done
  echo "## accounts"; for u in $USERS; do echo "$(id $u 2>&1)"; getent passwd $u | cut -d: -f1,3,4,6,7; echo "pw=$(passwd -S $u 2>/dev/null | awk '{print $2}') sudo=$(sudo -l -U $u 2>/dev/null | tail -1)"; done
  getent group agent-common agent-core
  echo "## dirs"; for d in $AGENT_HOME $AGENT_HOME/upload_files $AGENT_HOME/api_keys $AGENT_HOME/bin $LOG_DIR; do stat -c '%A %a %U:%G %n' $d 2>&1; getfacl -p $d 2>/dev/null | grep -vE '^#|^$'; done
  echo "## files"; stat -c '%A %a %U:%G %n' $ENV_FILE $MONITOR $LOG_FILE $LOGROTATE_CONF $SSH_FRAGMENT 2>&1
  sha256sum $ENV_FILE $MONITOR $LOGROTATE_CONF $SSH_FRAGMENT 2>&1
  echo "## sshd"; sshd -T 2>&1 | grep -E '^(port|permitrootlogin|passwordauthentication|pubkeyauthentication) '; systemctl is-active ssh.service; systemctl is-enabled ssh.service; echo "socket: $(systemctl is-enabled ssh.socket 2>&1) $(systemctl is-active ssh.socket 2>&1)"
  ss -H -ltn | awk '{print $4}' | sort
  echo "## ufw"; ufw status verbose | grep -vE '^$'; systemctl is-enabled ufw.service
  echo "## cron"; systemctl is-active cron.service; systemctl is-enabled cron.service; crontab -u agent-admin -l 2>&1; for u in root agent-dev agent-test; do echo "crontab $u: $(crontab -u $u -l 2>&1 | head -1)"; done
  echo "## logrotate"; systemctl is-active logrotate.timer; systemctl is-enabled logrotate.timer
}

# ============================================================== runner
c_ok=0; c_chg=0; c_diff=0; c_fail=0
show() { # tag step msg
  printf '[%-4s] %-9s %s\n' "$1" "$2" "$3"; }
run_check_only() {
  local s
  for s in $STEPS; do
    REASONS=(); NOTES=(); "check_$s"; local n=${#REASONS[@]}
    if [ "$s" = agent ]; then show PEND "$s" "${NOTES[0]}"; local i; for ((i=1;i<${#NOTES[@]};i++)); do show PEND "$s" "${NOTES[$i]}"; done; continue; fi
    if [ "$n" -eq 0 ]; then show OK "$s" "desired state reached"; c_ok=$((c_ok+1)); else
      show DIFF "$s" "${REASONS[0]}"; local i; for ((i=1;i<n;i++)); do show "" "" "  - ${REASONS[$i]}"; done; c_diff=$((c_diff+1)); fi
    local nt; for nt in "${NOTES[@]}"; do show note "$s" "$nt"; done
  done
  echo "== check: ok=$c_ok diff=$c_diff (agent: PENDING)"
  [ "$c_diff" -eq 0 ]
}
run_apply() {
  local s
  for s in $STEPS; do
    REASONS=(); NOTES=(); "check_$s"; local n=${#REASONS[@]}
    if [ "$s" = agent ]; then show PEND "$s" "${NOTES[0]}"; local i; for ((i=1;i<${#NOTES[@]};i++)); do show PEND "$s" "${NOTES[$i]}"; done; continue; fi
    if [ "$n" -eq 0 ]; then show OK "$s" "already satisfied (no change)"; c_ok=$((c_ok+1))
      local nt; for nt in "${NOTES[@]}"; do show note "$s" "$nt"; done; continue; fi
    show CHG "$s" "${REASONS[0]}"; local i; for ((i=1;i<n;i++)); do show "" "" "  - ${REASONS[$i]}"; done
    if ! "apply_$s"; then show FAIL "$s" "apply failed - stopping; later steps were NOT run"; c_fail=$((c_fail+1)); break; fi
    REASONS=(); NOTES=(); "check_$s"
    if [ ${#REASONS[@]} -ne 0 ]; then show FAIL "$s" "still differs after apply: ${REASONS[0]} - stopping"; c_fail=$((c_fail+1)); break; fi
    show OK "$s" "applied and verified"; c_chg=$((c_chg+1))
    local nt; for nt in "${NOTES[@]}"; do show note "$s" "$nt"; done
  done
  echo "== apply: unchanged=$c_ok changed=$c_chg failed=$c_fail (agent: PENDING)"
  [ "$c_fail" -eq 0 ]
}

case "$MODE" in
  check)    run_check_only;;
  apply)    run_apply;;
  snapshot) snapshot;;
  *) echo "usage: $0 check|apply --src DIR | snapshot" >&2; exit 2;;
esac
