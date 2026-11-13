#!/bin/bash
# bootstrap-orbstack.sh - rebuild / check the B4-1 practice environment from this repository.
# Runs on the Mac (no sudo needed on the Mac). All privileged work happens INSIDE the Ubuntu Machine
# through `orb -m <machine> sudo ...`.
#
#   scripts/bootstrap-orbstack.sh [--machine NAME] <command> [options]
#
#   create      create the OrbStack Machine (ubuntu:noble) if it does not exist (never deletes anything)
#   check       compare the Machine with the desired state; changes no persistent system state.
#               By default it also runs monitor.sh once against a TEMP log (temp dir in /tmp, removed afterwards).
#               --no-run skips that run. (A transient copy of the repo files is always streamed to /tmp and removed.)
#   apply       apply all steps idempotently; stops at the first failing step
#               (refuses to touch a Machine that already holds B4-1 data unless --allow-existing)
#   snapshot    print a normalized state description (diff two Machines with it)
#   verify      check + Mac-side network checks (SSH banner on the Machine IP, UFW allow/drop behaviour)
#               [--wait-cron SECONDS]  wait for scheduled monitor.sh runs (trigger=cron) in monitor.log
#               [--ssh-pubkey FILE]    install this PUBLIC key for the Machine's default user and test a real
#                                      login on tcp/20022 + root rejection (the private key never leaves the Mac)
#   all         create + apply + verify
#
# Default machine: b4-lab. Use --machine b4-recovery-test for rebuild tests; the real b4-lab is never
# deleted or reset by this script.
# Not handled: SSH keys / passwords / API keys (never generated or stored) and the provided Agent (PENDING).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO="$(cd "$HERE/.." && pwd)"
MACHINE=b4-lab; ALLOW_EXISTING=0; WAIT_CRON=0; PUBKEY=""; NO_RUN=0
CMD=""
while [ $# -gt 0 ]; do
  case "$1" in
    --machine) MACHINE="${2:-}"; shift 2;;
    --allow-existing) ALLOW_EXISTING=1; shift;;
    --no-run) NO_RUN=1; shift;;
    --wait-cron) WAIT_CRON="${2:-0}"; shift 2;;
    --ssh-pubkey) PUBKEY="${2:-}"; shift 2;;
    -h|--help) sed -n '2,/^set -u/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0;;
    create|check|apply|snapshot|verify|all) CMD="$1"; shift;;
    *) echo "unknown argument: $1 (try --help)" >&2; exit 2;;
  esac
done
[ -n "$CMD" ] || { echo "usage: $0 [--machine NAME] create|check|apply|snapshot|verify|all (see --help)" >&2; exit 2; }
[[ "$MACHINE" =~ ^[a-z0-9][a-z0-9-]*$ ]] || { echo "invalid machine name: $MACHINE" >&2; exit 2; }
command -v orb >/dev/null || { echo "orb (OrbStack CLI) not found" >&2; exit 2; }

say() { printf '%s\n' "$*"; }
T() { local n=$1; shift; perl -e 'alarm shift; exec @ARGV' "$n" "$@"; }   # macOS has no timeout(1)
exists() { orb list 2>/dev/null | awk '{print $1}' | grep -qx "$MACHINE"; }

do_create() {
  if exists; then say "[ OK ] create    Machine '$MACHINE' already exists (not touched)"; return 0; fi
  say "[CHG ] create    orb create ubuntu:noble $MACHINE"
  orb create ubuntu:noble "$MACHINE" || { say "[FAIL] create    orb create failed"; return 1; }
  local i; for i in $(seq 1 30); do orb -m "$MACHINE" true 2>/dev/null && break; sleep 2; done
  orb -m "$MACHINE" true 2>/dev/null || { say "[FAIL] create    Machine did not become reachable"; return 1; }
  say "[ OK ] create    Machine '$MACHINE' ready"
}

# stream the files the Machine-side script needs (no dependency on OrbStack's Mac-home mount)
remote() { # mode [extra args]
  local mode="$1"; shift
  ( cd "$REPO" && COPYFILE_DISABLE=1 tar -cf - bin/monitor.sh config/sshd-b4-mission.conf config/etc-default-agent-app.example \
      config/etc-logrotate.d-agent-app scripts/monitor-cron.sh scripts/machine-setup.sh ) |
  orb -m "$MACHINE" sudo bash -c 'D=$(mktemp -d /tmp/b4-src.XXXXXX); tar -xf - -C "$D" && bash "$D/scripts/machine-setup.sh" "$@" --src "$D"; rc=$?; rm -rf --one-file-system -- "$D"; exit $rc' _ "$mode" "$@"
}

need_machine() { exists || { say "[FAIL] Machine '$MACHINE' does not exist (run: $0 --machine $MACHINE create)"; return 1; }; }

do_check()    { need_machine || return 1; say "== check: $MACHINE (no persistent changes$( [ "$NO_RUN" -eq 1 ] && echo ", monitor.sh not run"))"; if [ "$NO_RUN" -eq 1 ]; then remote check --no-run; else remote check; fi; }
do_snapshot() { need_machine || return 1; orb -m "$MACHINE" sudo bash -s -- snapshot < "$REPO/scripts/machine-setup.sh"; }
do_apply() {
  need_machine || return 1
  if orb -m "$MACHINE" bash -c 'test -e /opt/agent-app -o -e /var/log/agent-app/monitor.log -o -e /etc/default/agent-app' 2>/dev/null && [ "$ALLOW_EXISTING" -ne 1 ]; then
    say "[STOP] '$MACHINE' already holds B4-1 data (/opt/agent-app, monitor.log or /etc/default/agent-app)."
    say "       Run '$0 --machine $MACHINE check' first to see the differences; re-run apply with --allow-existing"
    say "       to repair them (existing logs / other crontab entries / files are preserved, nothing is deleted)."
    return 1
  fi
  say "== apply: $MACHINE"; remote apply
}

net_checks() {
  local ip; ip=$(orb -m "$MACHINE" bash -c "ip -4 -o addr show scope global | awk '{print \$4}' | cut -d/ -f1 | head -1" 2>/dev/null)
  [ -n "$ip" ] || { say "[FAIL] net        cannot determine Machine IP"; return 1; }
  say "== Mac-side network checks against $MACHINE ($ip)"; local rc=0
  orb -m "$MACHINE" echo ORB_MGMT_OK >/dev/null 2>&1 && say "[ OK ] orb-mgmt  orb -m $MACHINE works" || { say "[FAIL] orb-mgmt  orb -m failed"; rc=1; }
  local ban; ban=$(T 8 perl -MIO::Socket::INET -e '$s=IO::Socket::INET->new(PeerAddr=>"'"$ip"':20022",Timeout=>5) or exit 1; $l=<$s>; print $l' 2>/dev/null | head -1 | tr -d '\r')
  case "$ban" in SSH-2.0-OpenSSH*) say "[ OK ] ssh-20022 $ip:20022 answers with '$ban' (Ubuntu sshd, not OrbStack's SSH)";; *) say "[FAIL] ssh-20022 no OpenSSH banner on $ip:20022 (got '$ban')"; rc=1;; esac
  local r
  r=$(T 8 perl -MIO::Socket::INET -e '$s=IO::Socket::INET->new(PeerAddr=>"'"$ip"':22",Timeout=>4); print $s?"open":"closed"' 2>/dev/null); [ "${r:-timeout}" != open ] && say "[ OK ] ssh-22    $ip:22 not reachable (${r:-timeout})" || { say "[FAIL] ssh-22    $ip:22 is reachable"; rc=1; }
  # no test server needed: 'refused' = packet passed the firewall (nothing listens), 'timeout' = dropped by UFW
  local p res
  for p in 15034 15035; do
    res=$(T 10 perl -MIO::Socket::INET -e '$s=IO::Socket::INET->new(PeerAddr=>"'"$ip"':'$p'",Timeout=>4); if($s){print "open"} elsif($!{ECONNREFUSED}){print "refused"} else {print "timeout"}' 2>/dev/null); res=${res:-timeout}
    if [ $p = 15034 ]; then [ "$res" = refused ] || [ "$res" = open ] && say "[ OK ] ufw-$p   passes the firewall ($res; nothing listens yet = refused, Agent absent)" || { say "[FAIL] ufw-$p   $res (expected refused/open)"; rc=1; }
    else [ "$res" = timeout ] && say "[ OK ] ufw-$p   dropped by UFW (timeout)" || { say "[FAIL] ufw-$p   $res (expected timeout)"; rc=1; }; fi
  done
  if [ -n "$PUBKEY" ]; then
    local pub="$PUBKEY" priv="${PUBKEY%.pub}" user
    if ! grep -qE '^(ssh-|ecdsa-)' "$pub" 2>/dev/null || grep -q PRIVATE "$pub"; then say "[FAIL] ssh-login  $pub is not a public key"; return 1; fi
    [ -f "$priv" ] || { say "[FAIL] ssh-login  matching private key $priv not found on this Mac"; return 1; }
    user=$(orb -m "$MACHINE" whoami)
    cat "$pub" | orb -m "$MACHINE" bash -c 'mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && k=$(cat) && (grep -qxF "$k" ~/.ssh/authorized_keys || echo "$k" >> ~/.ssh/authorized_keys)'
    local kh; kh=$(mktemp); local out
    out=$(T 15 ssh -i "$priv" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=6 -o UserKnownHostsFile="$kh" -o StrictHostKeyChecking=accept-new -p 20022 "$user@$ip" 'echo LOGIN_OK $(hostname) $SSH_CONNECTION' 2>&1 | tail -1)
    case "$out" in LOGIN_OK*) say "[ OK ] ssh-login  real login as $user on tcp/20022: $out";; *) say "[FAIL] ssh-login  $out"; rc=1;; esac
    T 15 ssh -i "$priv" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=6 -o UserKnownHostsFile="$kh" -o StrictHostKeyChecking=accept-new -p 20022 "root@$ip" true >/dev/null 2>&1; local rr=$?
    [ "$rr" -ne 0 ] && say "[ OK ] ssh-root   root login attempt rejected (ssh exit=$rr). NOTE: this key is not authorized for root, so the attempt alone cannot tell PermitRootLogin from a plain auth failure; the effective 'permitrootlogin no' is verified by the ssh step (sshd -T)" || { say "[FAIL] ssh-root   root login unexpectedly succeeded"; rc=1; }
    rm -f "$kh"
  fi
  return $rc
}
cron_wait() {
  [ "$WAIT_CRON" -gt 0 ] || return 0
  say "== waiting up to ${WAIT_CRON}s for scheduled runs (trigger=cron) in monitor.log"
  local end=$((SECONDS+WAIT_CRON)) n=0 base
  cnt() { orb -m "$MACHINE" sudo bash -c "grep -c 'trigger=cron' /var/log/agent-app/monitor.log || true" 2>/dev/null | tail -1; }
  base=$(cnt); base=${base:-0}
  while [ $SECONDS -lt $end ]; do
    n=$(cnt); n=${n:-0}
    [ $((n-base)) -ge 3 ] && break; sleep 10; done
  if [ $((n-base)) -ge 3 ]; then say "[ OK ] cron      $((n-base)) new scheduled runs (trigger=cron) appended during the wait"
    orb -m "$MACHINE" sudo bash -c "grep -E 'trigger=cron|SUMMARY' /var/log/agent-app/monitor.log | tail -n 6 | cut -c1-175"
  else say "[FAIL] cron      only $((n-base)) scheduled runs seen"; return 1; fi
}
do_verify() { do_check; local a=$?; net_checks; local b=$?; cron_wait; local c=$?; [ $a -eq 0 ] && [ $b -eq 0 ] && [ $c -eq 0 ]; }

case "$CMD" in
  create)   do_create;;
  check)    do_check;;
  apply)    do_apply;;
  snapshot) do_snapshot;;
  verify)   do_verify;;
  all)      do_create && do_apply && do_verify;;
esac
