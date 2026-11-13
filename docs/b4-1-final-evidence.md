# B4-1 요구사항 수행 내역서 (제출용)

- 기준: GitHub `main` (작업 15 시점, 작성 2026-11-13). 저장소: https://github.com/hyun02063185-AX-beginner/Codyssey_B4-1
- 실습 환경: OrbStack Linux Machine `b4-lab` (Ubuntu 24.04.5 LTS, x86_64)
- 요구사항 목록의 출처: Notion B4-1 페이지의 "Mission Core" 13개 항목. 이 목록은 **기존 Codyssey 관리자료의 요약**이며 공식 미션 원문과 직접 대조하지 않았습니다.
- 제출물: ① 이 수행 내역서 ② `monitor.sh` 소스 → [bin/monitor.sh](../bin/monitor.sh)

## 0. 읽는 법 — 판정 표기

| 표기 | 뜻 |
|---|---|
| **PASS** | 이 저장소에 기록된 실측(명령·출력)으로 확인됨 |
| **PASS (설계값)** | 동작은 실측으로 확인했으나, 값(경로·mode·임계값·형식·소속 등)이 **[승인된 실습 설계]** 또는 **[관리자료]** 라서 공식 원문과 대조되지 않음 |
| **PENDING** | 제공 Agent 원본 등 외부 자료가 없어 **검증하지 못함**. 완료로 간주하지 않음 |

> 이 문서에 **[원문 대조 완료]** 인 값은 없습니다. 모든 값은 "관리자료" 또는 "승인된 실습 설계"입니다.

## 1. 한눈에 보기

| # | Mission Core 항목 | 판정 | 상세 |
|---|---|---|---|
| 1 | SSH 포트 20022, Root 원격 로그인 차단 | PASS (설계값) | §2.1 |
| 2 | UFW 활성, TCP 20022/15034만 인바운드 허용 | PASS (설계값) | §2.2 |
| 3 | 계정 3개·그룹 2개 구성 | PASS (설계값: 소속) | §2.3 |
| 4 | upload_files / api_keys / `/var/log/agent-app` 권한·ACL | PASS (설계값: 경로·mode) | §2.3 |
| 5 | 환경변수 5개 | **4개 PASS / `AGENT_KEY_PATH` PENDING** | §2.4 |
| 6 | 제공 앱 실행: Boot Sequence 5단계 `[OK]`, `Agent READY`, `0.0.0.0:15034` LISTEN | **PENDING** (Agent 원본 NOT FOUND) | §2.5 |
| 7 | `$AGENT_HOME/bin/monitor.sh` Bash 구현, 소유자/권한 | PASS (설계값: 소유자·mode) | §2.6 |
| 8 | 프로세스·TCP 15034 Health Check, 실패 시 `exit 1` | 로직 PASS / **Agent 정상 판정 PENDING** | §2.6 |
| 9 | 방화벽 점검, 비활성 시 WARNING만 | 로직 PASS (스텁 검증) / 실제 비활성 상태 미시험 | §2.6 |
| 10 | CPU/MEM/DISK 수집, 임계값 초과 시 WARNING | PASS (임계값 80%는 설계 기본값) | §2.7 |
| 11 | `monitor.log` 지정 포맷 누적 기록 | PASS (포맷은 임시 설계) | §2.8 |
| 12 | 로그 최대 10MB / 10개 | 설정·임시환경 PASS / **실제 타이머 발동 PENDING** | §2.9 |
| 13 | agent-admin crontab 매분 실행, 로그 자동 증가 | PASS | §2.10 |
| + | 환경 복구 자동화 (`bootstrap-orbstack.sh`) | PASS | §2.11 |

보너스(`report.sh`, 7일 압축/30일 삭제)는 **착수하지 않았습니다**.

## 2. 항목별 수행 내역

공통 접두어: 아래 `orb -m b4-lab sudo …`는 Mac 터미널에서 Machine 안의 root 명령을 실행합니다(Mac에는 sudo 불필요).

### 2.1 SSH 포트 20022 · Root 로그인 차단 — PASS (설계값)

| 항목 | 값 |
|---|---|
| 적용값 | `Port 20022`, `PermitRootLogin no` — `/etc/ssh/sshd_config.d/10-b4-mission.conf` ([config/sshd-b4-mission.conf](../config/sshd-b4-mission.conf)) |
| 운영 방식 [설계] | `ssh.socket` 비활성, `ssh.service` 상시 실행 |
| 확인 명령 | `orb -m b4-lab sudo sshd -T \| grep -Ei '^(port\|permitrootlogin) '` → `port 20022` / `permitrootlogin no` |
| | `orb -m b4-lab sudo ss -tlnp \| grep sshd` → `0.0.0.0:20022`, `[::]:20022` (22 없음) |
| | Mac: `ssh -p 20022 <계정>@<Machine IP>` → 배너 `SSH-2.0-OpenSSH_9.6p1 Ubuntu-3ubuntu13.20` |
| 테스트 결과 | Mac→20022 실제 접속 성공 / Mac→22 접속 불가 / root에 유효 키를 임시 등록해도 거부(sshd 로그 `ROOT LOGIN REFUSED`, 임시 키 제거) / `orb restart` 후 유지 |
| 추가 확인 | 2026-11-13 작업 15 시점 재확인: 위 `sshd -T`·`ss` 출력 일치, Mac에서 20022 배너 수신, `ssh.service` active, `ssh.socket` inactive/disabled |
| 증빙 | [orbstack-environment.md §10](orbstack-environment.md) (SSH 20022 구성·검증), [§5 OrbStack 내부 SSH와의 구분](orbstack-environment.md) |
| 주의 | OrbStack 관리 SSH(`orb -m`, `ssh <machine>@orb`)는 Ubuntu sshd와 **별개**이며 Root 차단 대상이 아님. 비밀번호 인증(`PasswordAuthentication`)은 기본값 유지 — 공식 요구 여부 [확인 필요] |

### 2.2 UFW — PASS (설계값)

| 항목 | 값 |
|---|---|
| 적용값 | default deny incoming / allow outgoing, `20022/tcp`·`15034/tcp` 허용(IPv4·IPv6). 순서: 20022 허용 → 15034 허용 → enable (lockout 방지) |
| 확인 명령 | `orb -m b4-lab sudo ufw status verbose` |
| 2026-11-13 재확인 출력 | `Status: active` / `Default: deny (incoming), allow (outgoing), deny (routed)` / `20022/tcp ALLOW IN`, `15034/tcp ALLOW IN` + `(v6)` 동일 |
| 허용·차단 실측 | 15035(미허용): 활성화 전 접속 성공 → 활성화 후 **timeout(차단)**. 15034(허용): 리스너가 없으면 **refused**. 20022: 접속 성공 |
| 작업 15 재확인 | Mac→`:22` timeout(UFW drop), Mac→`:15034` refused(허용되었으나 리스너 없음 = Agent 부재와 일치) |
| 재시작 후 | `orb restart b4-lab` 후 UFW 자동 복원과 허용·차단 재검증 PASS |
| 증빙 | [orbstack-environment.md §11](orbstack-environment.md) (§11.4 결과, §11.7 재시작 후 복원) |
| 한계 | 커널 로그 `UFW BLOCK`은 확인하지 못함(INCONCLUSIVE, 차단 자체는 접속 비교로 확인). Mac 재부팅·OrbStack 앱 재시작 후 복원은 미검증 |

### 2.3 사용자·그룹·ACL — PASS (설계값)

> **사용자별 그룹 소속은 공식 원문이 아니라 사용자가 승인한 실습 설계입니다.**

| 계정 | 보조 그룹 | upload_files | api_keys | /var/log/agent-app |
|---|---|---|---|---|
| `agent-admin` | `agent-common`, `agent-core` | R/W | R/W | R/W |
| `agent-dev` | `agent-common` | R/W | 거부 | 거부 |
| `agent-test` | 없음 | 거부 | 거부 | 거부 |

세 계정 모두 홈 750, 비밀번호 잠김, **sudo 없음**.

| 경로 | 소유자:그룹 | mode | ACL |
|---|---|---|---|
| `/opt/agent-app` | `root:root` | `0755` | — |
| `/opt/agent-app/upload_files` | `agent-admin:agent-common` | `2770` | access+default |
| `/opt/agent-app/api_keys` | `root:agent-core` | `2770` | access+default |
| `/var/log/agent-app` | `root:agent-core` | `2770` | access+default |
| `/opt/agent-app/bin` | `root:root` | `0755` | — |

- 확인 명령: `id agent-admin agent-dev agent-test`, `getent group agent-common agent-core`, `stat -c '%A %U:%G %n' …`, `getfacl <경로>`
- 2026-11-13 재확인: `agent-common:x:1000:agent-admin,agent-dev`, `agent-core:x:1001:agent-admin`, 위 표의 소유자·mode 일치
- 테스트: `sudo -u <계정>`으로 허용/거부 9칸 전부 실측 PASS. 상속(setgid·default ACL), umask 영향, 상위 경로 탐색, ACL mask 시나리오 실측.
- 알려진 한계: 파일 생성 프로그램이 **명시적 mode 0644**를 요청하면 ACL mask가 `r--`가 되어 그룹 쓰기가 막힐 수 있음(실측, `chmod g+w`로 복구). 제공 Agent의 실제 파일 생성 방식은 미확인.
- 증빙: [b4-1-permission-plan.md §11](b4-1-permission-plan.md) (적용·접근 검증·상속·회귀), §10 (ACL 임시 실습)

### 2.4 환경변수 5개 — 4개 PASS (설계값) / 1개 PENDING

파일: `/etc/default/agent-app` (`root:root 0644`, KEY=VALUE, 비밀값 없음) — 원본 [config/etc-default-agent-app.example](../config/etc-default-agent-app.example)

| 변수 | 현재 값 | 판정 | 출처 구분 |
|---|---|---|---|
| `AGENT_HOME` | `/opt/agent-app` | PASS | 승인된 실습 설계 |
| `AGENT_PORT` | `15034` | PASS | 관리자료 |
| `AGENT_UPLOAD_DIR` | `/opt/agent-app/upload_files` | PASS | 승인된 실습 설계 |
| `AGENT_LOG_DIR` | `/var/log/agent-app` | PASS | 관리자료 |
| `AGENT_KEY_PATH` | *(빈 값)* | **PENDING** | 제공 앱이 파일/디렉터리 중 무엇을 요구하는지 알 수 없어 추측하지 않음 |

- 확인 명령: `orb -m b4-lab cat /etc/default/agent-app`
- 실측: `agent-admin`의 `env -i` 새 프로세스에서 `set -a; . /etc/default/agent-app; set +a`로 5개 전달 확인, systemd `EnvironmentFile=` 호환 확인. **로그인 셸·cron 환경에는 자동으로 들어가지 않으므로** `monitor.sh`가 파일을 직접 로드함(cron 환경에 `AGENT_*` 없음을 관찰로 확인).
- **"로드 검증 PASS"는 "Agent가 이 변수를 사용함"의 증명이 아닙니다.** Agent 사용 여부는 PENDING.
- 증빙: [b4-1-agent-runtime.md §2–3](b4-1-agent-runtime.md)

### 2.5 제공 Agent 실행 — **PENDING (미검증)**

| 요구 | 상태 |
|---|---|
| 제공 Python 앱 원본 | **NOT FOUND** — 저장소·Mac·Machine·Notion 어디에서도 발견하지 못함. (B4-2 Notion의 `agent-leak-app` 이름은 파일 존재의 증거가 아님) |
| 일반 계정으로 실행 | 미실행 (실행 계정·명령·Python/아키텍처 요구 미확인) |
| Boot Sequence 5단계 `[OK]` | 미검증 |
| `Agent READY` 출력 | 미검증 |
| `0.0.0.0:15034` LISTEN | **미검증** — 현재 `ss`에 15034 리스너 없음(정상: Agent가 없으므로) |

가짜 Agent·모의 서버를 만들어 이 항목을 통과시키지 않았습니다. 상세: [b4-1-agent-runtime.md §1](b4-1-agent-runtime.md)

### 2.6 `monitor.sh` — 구현 PASS (설계값) / Agent 정상 판정 PENDING

| 항목 | 값 |
|---|---|
| 소스 | [bin/monitor.sh](../bin/monitor.sh) (Bash, `bash -n` PASS) |
| 배포 | `/opt/agent-app/bin/monitor.sh` = `$AGENT_HOME/bin/monitor.sh`, `root:agent-admin 0750` [설계 결정] |
| 일치 확인 | 저장소 `bin/monitor.sh`와 배포본의 sha256 동일: `475cc855…843fd4` (2026-11-13) |
| 점검 | Agent 프로세스 / TCP 15034(주소·소유 PID 포함) / UFW / CPU·MEM·DISK |
| 종료 코드 | `0` 정상(프로세스 OK + `0.0.0.0:15034` LISTEN + 소유 PID 일치) / `1` 프로세스·포트 실패 또는 확인 불가 / `2` 모니터링 자체 오류 |
| 방화벽 | 비활성 → `WARNING` 출력, 종료 코드 영향 없음(exit 0 유지 — "WARNING 시 종료 코드"는 [확인 필요]로 0으로 정함). root가 아니면 `UNKNOWN`(sudo 미부여) |
| 판정 시나리오 | 포트·PID·바인딩 42건 PASS / 0 FAIL (fixture·기존 sshd 이용; 실제 Agent 아님) |

- **현재 `exit 1`은 "제공 Agent 부재"를 올바르게 감지한 결과이며 실패가 아니라 예상된 장애 감지입니다.** 로그 예: `[PENDING] PROCESS agent identification criteria not configured (AGENT_PROCESS_PATTERN unset)`, `[FAIL] PORT tcp/15034 not LISTEN`, `SUMMARY result=UNHEALTHY exit=1`.
- **PENDING:** `AGENT_PROCESS_PATTERN` 미설정(Agent 식별 기준 불명), 정상(exit 0) 출력, 실제 UFW 비활성 상태에서의 WARNING(스텁으로만 검증).
- 증빙: [b4-1-monitor.md §3–5](b4-1-monitor.md) (판정 규칙, 종료 코드, 실측)

### 2.7 CPU / MEM / DISK — PASS (임계값은 설계 기본값)

- 수집: CPU(`/proc/stat` 샘플), MEM(`MemAvailable` 기반), DISK(`/` 사용률). 임계값 **80%는 [설계 기본값]**이며 공식 값이 아님. 초과 시 `WARNING`.
- 2026-11-13 17:53 실제 cron 실행 로그: `CPU usage=0.0%`, `MEM usage=3.7%`, `DISK usage=0.4%` (모두 `[OK]`, `threshold 80% [design default]`).
- 임계값 초과 `WARNING`은 [b4-1-monitor.md §5](b4-1-monitor.md)의 임계값 하향 시험으로 확인.

### 2.8 `monitor.log` 기록 — PASS (포맷은 임시 설계)

- 경로 `/var/log/agent-app/monitor.log`, `agent-admin:agent-core 0660`. 스크립트가 직접 append(cron 리디렉션에 의존하지 않음).
- 형식 `YYYY-MM-DD HH:MM:SS [LEVEL] CATEGORY message` — **공식 "지정 포맷"과 대조하지 못한 임시 설계**.
- 확인 명령: `orb -m b4-lab sudo tail -12 /var/log/agent-app/monitor.log`, `orb -m b4-lab sudo wc -l /var/log/agent-app/monitor.log`
- 현재 상태(2026-11-13 17:53): 570줄, 실행 1회=10줄(`START`·`CONFIG`×2·`PROCESS`·`PORT`·`FIREWALL`·`CPU`·`MEM`·`DISK`·`SUMMARY`).
- 실측: 3회 누적, 터미널 출력과 동일, 동시 실행 6건에서 줄 깨짐 없음, 권한 거부/ENOSPC/심볼릭 링크 오류 경로, 비밀정보 미기록.
- 증빙: [b4-1-monitor.md §2.1, §5.2](b4-1-monitor.md)

### 2.9 로그 순환 10MB / 10개 — 설정·임시환경 PASS / 실제 발동 PENDING

| 항목 | 값 |
|---|---|
| 설정 | `/etc/logrotate.d/agent-app` ([config/etc-logrotate.d-agent-app](../config/etc-logrotate.d-agent-app)): `size 10M`, `rotate 9`(활성 1 + 순환본 9 = 최대 10개), `create 0660 agent-admin agent-core`, `su agent-admin agent-core`, rename+create |
| 의미 | 검사 시점에 **10 MiB(10,485,760 B) 이상**이면 순환. "10개"를 활성 포함으로 해석한 것은 **승인된 실습 설계** |
| 임시환경 시험 | 37건 PASS / 0 FAIL — 경계(미만·동일·초과), 12회 반복 순환, 파일 수, 데이터 보존, 권한 유지, 실행 중 rename |
| 실제 로그 | 강제 순환·삭제하지 않음(현재 570줄, 약 67 KB — 10 MiB에 한참 미달) |
| 확인 명령 | `orb -m b4-lab sudo logrotate -d /etc/logrotate.d/agent-app` (dry-run) |
| 증빙 | [b4-1-log-rotation.md §2–4](b4-1-log-rotation.md) |

**PENDING — 확인된 사실만 정리:**
- `logrotate.timer`는 일 1회(00:00) 동작합니다. 현재 `LastTrigger=2026-11-13 00:00:40`(이전 발동 11-12 00:00:40)이나 **이 설정 파일은 11-13 낮에 설치**되었으므로 그 발동은 이 정책의 증거가 아닙니다. 다음 예정 `2026-11-14 00:00:00 KST` 이후 `journalctl -u logrotate.service`와 `/var/lib/logrotate/status`로 확인해야 하며, **현재는 PENDING**입니다. (`/var/lib/logrotate/status`의 `monitor.log` 항목은 작업 12의 비강제 수동 검사 기록이지 타이머 발동 기록이 아님.)
- 운영 로그가 실제로 10 MiB에 도달해 순환되는 것은 미확인.
- 검사가 일 1회이므로 로그가 검사 사이에 10 MiB를 넘을 수 있습니다 — **엄격한 최대 크기 보장이 아닙니다**.

### 2.10 cron 매분 실행 — PASS

| 항목 | 값 |
|---|---|
| 등록 | `agent-admin` crontab (root 아님): `* * * * * MONITOR_TRIGGER=cron /opt/agent-app/bin/monitor.sh >/dev/null 2>&1` (관리 블록 `# BEGIN/END B4-1 monitor`) |
| 확인 명령 | `orb -m b4-lab sudo crontab -u agent-admin -l` / `systemctl is-active cron` → `active` |
| 실측 | 2026-11-13 17:03–17:08 KST 연속 **6회**(빠진 분 0), 로그 50→120줄, START `trigger=cron` vs `manual` 구분, cron 프로세스의 `groups=agent-admin,agent-common,agent-core` |
| 작업 15 재확인 | 17:53:01 실행이 계속 누적됨(로그 570줄, 마지막 START `trigger=cron`) |
| 관리 | [scripts/monitor-cron.sh](../scripts/monitor-cron.sh) `install\|pause\|resume\|remove\|status` — 재설치 시 중복 방지, 다른 항목 유지 |
| 증빙 | [b4-1-cron.md §1–3](b4-1-cron.md) |

- 매 실행의 `SUMMARY result=UNHEALTHY exit=1`은 Agent 부재의 올바른 기록입니다. 정상 exit 0은 **PENDING**.
- **알려진 공백:** cron이 stdout/stderr를 `/dev/null`로 보내고 cron은 종료 코드를 기록하지 않으므로, 로그 쓰기 실패는 "새 줄이 생기지 않음"으로만 보입니다. 별도 알림 채널은 구현하지 않았습니다.

### 2.11 환경 복구 자동화 — PASS

- Mac의 [scripts/bootstrap-orbstack.sh](../scripts/bootstrap-orbstack.sh)가 저장소 파일을 Machine 안의 [scripts/machine-setup.sh](../scripts/machine-setup.sh)로 전달해 12단계(`preflight packages ssh ufw accounts dirs envfile monitor logfile logrotate cron verify agent`)를 멱등하게 적용·점검합니다.
- 검증(테스트 Machine `b4-recovery-test`): 새 Machine에 GitHub 파일만으로 구성 → `b4-lab`과 정규화 스냅샷 동일, 반복 `apply` 변경 없음, `check` 12/12 OK, Mac 네트워크 검증(20022 배너·22 차단·15034 refused·15035 timeout·실제 로그인·cron 3회).
- SSH 사전검증(작업 14-1): 설정 조각 백업 → `sshd -t` → `sshd -T` 실효 설정(Port 정확히 20022, `PermitRootLogin no`) 검사를 **재시작 전에** 수행, 실패 시 조각 복원·서비스 미재시작. T1–T7 PASS (`PermitRootLogin yes` 충돌, `Port 22` 충돌, 잘못된 지시어, 재시작 실패 롤백 포함).
- 증빙: [b4-1-recovery.md §3–4.1](b4-1-recovery.md)
- 한계: Agent 원본·SSH 개인키·API 키·과거 로그 내용은 복구하지 않음. 롤백 후에도 `ssh.service`를 되살릴 수 없는 최종 경로는 미검증.
- `check`는 "지속 시스템 설정을 바꾸지 않는" 검사이며 "파일을 전혀 쓰지 않는" 검사가 아닙니다(임시 파일 생성, `monitor.sh` 1회 시험 실행; `--no-run`은 실행만 생략). [recovery §3.2](b4-1-recovery.md)

## 3. 미완료(PENDING) 항목 — 임의로 완료 처리하지 않음

| # | 항목 | 상태 | 해소 조건 |
|---|---|---|---|
| P1 | 제공 Python Agent 원본 | **NOT FOUND** | 원본 파일 확보 |
| P2 | `AGENT_KEY_PATH` | 미확정(빈 값) | Agent가 요구하는 경로·형태 확인 |
| P3 | Agent Boot Sequence 5단계 / `Agent READY` | 미검증 | Agent 실행 |
| P4 | 실제 `0.0.0.0:15034` LISTEN | 미검증 | Agent 실행 |
| P5 | Agent 정상 시 `monitor.sh` exit 0 (및 `AGENT_PROCESS_PATTERN` 확정) | 미검증 | Agent 실행 후 식별 기준 확정 |
| P6 | 공식 미션 원문과 설정값 대조 | 미완료 | 원문 확보. 현재 모든 값은 [관리자료]/[승인된 실습 설계] |
| P7 | 실제 `logrotate.timer` 발동(이 정책 기준) | 미확인 | 2026-11-14 00:00 KST 이후 확인 |
| P8 | 운영 로그 10 MiB 도달 시 실제 순환 | 미확인 | 로그 증가 또는 발동 후 확인 (임시환경에서는 PASS) |

그 외 [확인 필요]: 로그 포맷·CPU/MEM/DISK 임계값·`WARNING` 종료 코드의 공식 값, `agent-*` 계정의 SSH 접속 방식, `PasswordAuthentication` 요구 여부, 실제 UFW 비활성 상태에서의 `WARNING` 시험, 보너스 항목.

## 4. 제출 증빙 목록

원칙: 기존에 확보된 출력은 재사용하고, 새 설치·설정 변경은 하지 않는다. **개인키·비밀번호·실제 API 키는 캡처에 포함하지 않는다**(`api_keys` 디렉터리는 비어 있고 키 파일은 만들지 않았다). 아래 명령은 모두 Mac 터미널에서 실행하며 읽기 전용이다.

범례: ✅ 저장소 문서에 출력이 기록되어 있음 / 📷 **제출용 터미널 캡처는 별도로 찍어야 함** / ⛔ 증빙 불가(PENDING)

| # | 요구 | 캡처할 명령 | 기록된 출력 | 캡처 |
|---|---|---|---|---|
| E1 | SSH 포트·Root 차단 | `orb -m b4-lab sudo sshd -T \| grep -Ei '^(port\|permitrootlogin) '` ; `orb -m b4-lab sudo ss -tlnp \| grep sshd` | ✅ [env §10.5](orbstack-environment.md) | 📷 |
| E2 | Mac→20022 접속 / 22 불가 | `ssh -p 20022 <계정>@<IP>` (키가 있을 때) 또는 `nc`로 배너 확인 | ✅ [env §10.5](orbstack-environment.md) | 📷 (공개키 로그인은 사용자가 키를 등록한 경우에만. 개인키 내용은 캡처 금지) |
| E3 | Root 로그인 거부 | sshd 로그 `ROOT LOGIN REFUSED` 장면 | ✅ [env §10.5](orbstack-environment.md) (임시 키로 시험 후 제거) | 📷 재현하려면 임시 root 키 등록이 필요 → **누락, 필요하면 별도 승인 후** |
| E4 | UFW 상태 | `orb -m b4-lab sudo ufw status verbose` | ✅ [env §11.4](orbstack-environment.md) | 📷 |
| E5 | UFW 허용/차단 | Mac에서 `nc -z <IP> 15034`(refused) / `nc -z <IP> 15035`(timeout) | ✅ [env §11.4](orbstack-environment.md) | 📷 |
| E6 | 계정·그룹 | `orb -m b4-lab id agent-admin agent-dev agent-test` ; `orb -m b4-lab getent group agent-common agent-core` | ✅ [env §12](orbstack-environment.md) | 📷 |
| E7 | 디렉터리 권한·ACL | `orb -m b4-lab sudo getfacl -p /opt/agent-app/upload_files /opt/agent-app/api_keys /var/log/agent-app` ; `stat` | ✅ [permission §11.1](b4-1-permission-plan.md) | 📷 |
| E8 | 사용자별 허용/거부 | `sudo -u agent-dev` 등으로 쓰기 시도 | ✅ [permission §11.3](b4-1-permission-plan.md) | 📷 (테스트 파일은 즉시 삭제) |
| E9 | 환경변수 | `orb -m b4-lab cat /etc/default/agent-app` | ✅ [runtime §2–3](b4-1-agent-runtime.md) | 📷 |
| E10 | Agent 기동 / READY / 15034 LISTEN | — | ⛔ | ⛔ Agent 원본 필요 |
| E11 | `monitor.sh` 소스·배치·권한 | `git show main:bin/monitor.sh` ; `orb -m b4-lab sudo stat -c '%A %U:%G %n' /opt/agent-app/bin/monitor.sh` | ✅ [monitor §1](b4-1-monitor.md) | 📷 |
| E12 | `monitor.sh` 실행 출력 + `echo $?` (장애 감지) | `orb -m b4-lab sudo -u agent-admin /opt/agent-app/bin/monitor.sh; echo $?` | ✅ [monitor §2, §5](b4-1-monitor.md) | 📷 (실행 시 로그 10줄 추가됨, 정상 동작) |
| E13 | `monitor.sh` 정상(exit 0) | — | ⛔ | ⛔ Agent 원본 필요 |
| E14 | 방화벽 WARNING | UFW 비활성 상태에서 실행 | 스텁 검증만 ✅ ([monitor §5](b4-1-monitor.md)) | 실제 UFW를 끄는 시험은 하지 않음 → **누락** |
| E15 | CPU/MEM/DISK | E12 출력에 포함 | ✅ | 📷 (E12와 동일 화면) |
| E16 | `monitor.log` 누적 | `orb -m b4-lab sudo tail -20 /var/log/agent-app/monitor.log` ; `stat` | ✅ [monitor §5.2](b4-1-monitor.md) | 📷 |
| E17 | 로그 순환 설정 | `orb -m b4-lab cat /etc/logrotate.d/agent-app` ; `logrotate -d` | ✅ [rotation §2–3](b4-1-log-rotation.md) | 📷 |
| E18 | 로그 순환 실제 발동 | `journalctl -u logrotate.service` | ⛔ 대기 중 | ⛔ 2026-11-14 00:00 KST 이후 |
| E19 | cron 등록 | `orb -m b4-lab sudo crontab -u agent-admin -l` ; `systemctl is-active cron` | ✅ [cron §1–2](b4-1-cron.md) | 📷 |
| E20 | cron 자동 증가 | 1–2분 간격으로 `wc -l /var/log/agent-app/monitor.log` 두 번 + `grep -c trigger=cron` | ✅ [cron §3](b4-1-cron.md) | 📷 |
| E21 | 환경 복구 | `scripts/bootstrap-orbstack.sh check --no-run` | ✅ [recovery §4](b4-1-recovery.md) | 📷 (작업 15에서 실행: ok=11, diff=0, verify SKIP, agent PENDING) |
| E22 | SSH 사전검증 | [recovery §4.1](b4-1-recovery.md)의 T2 출력 | ✅ | `b4-lab`에서 재현 금지 → 문서 출력으로 대체 |

## 5. 재현·확인에 쓴 환경 정보

- Mac: macOS(x86_64), OrbStack 2.0.5. Machine `b4-lab` running(192.168.139.18), `b4-recovery-test` stopped(검증용, 삭제하지 않음).
- 이 문서의 2026-11-13 "재확인" 수치는 작업 15에서 `b4-lab`에 **읽기 전용 명령만** 실행해 얻은 값입니다(`check --no-run`, `ufw status`, `sshd -T`, `ss`, `stat`, `tail`).
