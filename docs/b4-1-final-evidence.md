# B4-1 요구사항 수행 내역서 (제출용, 최종)

- 기준: GitHub `main` (작업 21, 2026-11-13). 저장소: https://github.com/hyun02063185-AX-beginner/Codyssey_B4-1
- 실습 환경: OrbStack Linux Machine `b4-lab` (Ubuntu 24.04.5 LTS, x86_64). 재구축 검증용 `b4-recovery-test`.
- 제출물: ① 이 수행 내역서 ② `monitor.sh` 소스 → [bin/monitor.sh](../bin/monitor.sh)
- 값의 기준: 그룹 구성·`monitor.sh` 소유권·임계값·로그 형식·테스트 키 문자열은 **공식 요구값**(작업 16~19에서 Owner가 제공), 키 경로는 **제공 Agent 실행 결과**로 확정했습니다. 공식 미션 원문 전체를 저장소에 보관하지는 않으며, 최종 대조는 Owner 검수에서 합니다.
- **전체 미션 완료 판정은 Owner 최종 검수 이후입니다.** 이 문서는 구현·검증 상태를 보고합니다.
- 과거 기록(작업 15 시점 수행 내역서)은 [archive/b4-1-final-evidence-task15.md](archive/b4-1-final-evidence-task15.md)에 보관했습니다. 현재 상태와 다르니 참고용으로만 보세요.

## 0. 판정 표기

| 표기 | 뜻 |
|---|---|
| **PASS** | 이 저장소에 기록된 실측(명령·출력)으로 확인됨 |
| **PENDING** | 시간·외부 요인으로 아직 확인할 수 없음. 완료로 간주하지 않음 |
| **CAPTURE PENDING** | 제출용 화면 캡처가 아직 없음(§4) |

## 1. 한눈에 보기

| # | 필수 요구사항 | 판정 | 상세 |
|---|---|---|---|
| 1 | SSH 포트 20022, Root 원격 로그인 차단 | **PASS** | §2.1 |
| 2 | UFW 활성, TCP 20022/15034만 인바운드 허용 | **PASS** | §2.2 |
| 3 | 계정 3개·그룹 2개 구성 | **PASS** | §2.3 |
| 4 | upload_files / api_keys / `/var/log/agent-app` 권한·ACL | **PASS** | §2.3 |
| 5 | 환경변수 5개 | **PASS** (키 경로는 과제 설명과 Agent 요구가 다름 — §3) | §2.4 |
| 6 | 제공 앱 실행: Boot Sequence 5단계 `[OK]`, `Agent READY`, `0.0.0.0:15034` LISTEN | **PASS** | §2.5 |
| 7 | `$AGENT_HOME/bin/monitor.sh` Bash 구현, 소유자/권한 | **PASS** | §2.6 |
| 8 | 프로세스·TCP 15034 Health Check, 실패 시 `exit 1` | **PASS** | §2.6 |
| 9 | 방화벽 점검, 비활성 시 WARNING만 | **PASS** | §2.7 |
| 10 | CPU/MEM/DISK 수집, 임계값 초과 시 WARNING | **PASS** | §2.8 |
| 11 | `monitor.log` 공식 형식 누적 기록 | **PASS** | §2.9 |
| 12 | 로그 최대 10MB / 10개 | 설정·순환 동작 **PASS** / **타이머 실제 실행 기록 PENDING** | §2.10 |
| 13 | agent-admin crontab 매분 실행, 로그 자동 증가 | **PASS** | §2.11 |
| + | 환경 복구 자동화 (`bootstrap-orbstack.sh`) | **PASS** | §2.12 |

PENDING은 항목 12의 한 가지뿐입니다: 설정 설치 후 `logrotate.timer`가 이 설정을 실행한 기록(첫 기회 2026-11-14 00:00~01:00 KST). 제출용 화면 캡처는 모두 **CAPTURE PENDING**입니다(§4). 보너스 과제(`report.sh`, 7일 압축/30일 삭제)는 착수하지 않았습니다.

실측 원본: [evidence/task21-b4-lab-regression.txt](evidence/task21-b4-lab-regression.txt)(본환경 전체 회귀, 2026-11-13 21:22~21:24 KST). 아래 "결과"는 별도 표기가 없으면 이 파일의 값입니다.

## 2. 항목별 수행 내역

명령 표기: `B …` = Mac 터미널에서 `orb -m b4-lab sudo …`(Mac에는 sudo 불필요). 조회·읽기 전용 명령만 적었으며 상태를 바꾸는 명령은 따로 표시합니다.

### 2.1 SSH 포트 20022 · Root 로그인 차단 — PASS

| | |
|---|---|
| 요구사항 | SSH 포트 20022, Root 원격 로그인 차단 |
| 적용값 | `/etc/ssh/sshd_config.d/10-b4-mission.conf` ([config/sshd-b4-mission.conf](../config/sshd-b4-mission.conf)): `Port 20022`, `PermitRootLogin no`. `ssh.service` 상시 실행, `ssh.socket` 비활성 |
| 명령 | `B sshd -T \| grep -E '^(port\|permitrootlogin) '` / `B ss -tlnp \| grep sshd` / Mac: `ssh -p 20022 <계정>@<Machine IP>` |
| 결과 | `port 20022`, `permitrootlogin no`; LISTEN `0.0.0.0:20022`, `[::]:20022`(22 없음); `ssh.service` active, `ssh.socket` disabled; Mac에서 `SSH-2.0-OpenSSH_9.6p1 Ubuntu-3ubuntu13.20` 응답 |
| 증빙 위치 | [evidence/task21-b4-lab-regression.txt](evidence/task21-b4-lab-regression.txt) `## OS/SSH`, [orbstack-environment.md §10](orbstack-environment.md) |

### 2.2 UFW — PASS

| | |
|---|---|
| 요구사항 | UFW 활성, 20022/15034만 인바운드 허용 |
| 적용값 | `deny incoming / allow outgoing`, `allow 20022/tcp`(SSH), `allow 15034/tcp`(Agent), `ufw.service` enabled |
| 명령 | `B ufw status verbose` / Mac: 20022·22·15034·15035 TCP 연결 시도(§4 E4) |
| 결과 | `Status: active`, `Default: deny (incoming), allow (outgoing)`, 허용 규칙 4줄(v4·v6 각 20022, 15034). Mac→Machine: 20022 열림, 22 timeout, 15035 timeout(UFW drop), 15034는 Agent 중지 시 refused(방화벽 통과·리스너 없음)·실행 시 열림 |
| 증빙 위치 | 회귀 파일 `## UFW`, [orbstack-environment.md §11](orbstack-environment.md) |

### 2.3 사용자·그룹·ACL — PASS (요구 3·4)

| | |
|---|---|
| 요구사항 | `agent-common`: admin·dev·test / `agent-core`: admin·dev. 디렉터리별 접근: admin·dev는 upload_files·api_keys·로그 R/W, test는 upload_files R/W만 |
| 적용값 | 그룹 소속 위와 같음, `agent-*` 계정 sudo 없음(예외 `agent-admin`의 `ufw status` 한 명령, §2.7). `/opt/agent-app` `root:root 755`, `upload_files` `agent-admin:agent-common 2770`+ACL, `api_keys`·`/var/log/agent-app` `root:agent-core 2770`+ACL |
| 명령 | `B getent group agent-common agent-core` / `B id agent-admin` (dev·test 각각) / `B stat -c '%U:%G %a %n' …` / `B getfacl -p /opt/agent-app/api_keys` / 계정별 임시 파일 생성·삭제 시험(§4 E7) |
| 결과 | `agent-common:agent-admin,agent-dev,agent-test`, `agent-core:agent-admin,agent-dev`. R/W 표: admin·dev 세 곳 모두 R/W, test는 `upload_files=R/W`, `api_keys`·로그는 `no/no`. sudo: admin은 `(root) NOPASSWD: /usr/sbin/ufw status` 한 줄, dev·test는 `not allowed` |
| 증빙 위치 | 회귀 파일 `## accounts`·`## ACL matrix`, [b4-1-official-alignment.md](b4-1-official-alignment.md), [b4-1-permission-plan.md](b4-1-permission-plan.md)(설계 당시 기록) |

### 2.4 환경변수 5개 — PASS

| | |
|---|---|
| 요구사항 | `AGENT_HOME`, `AGENT_PORT`, `AGENT_UPLOAD_DIR`, `AGENT_KEY_PATH`, `AGENT_LOG_DIR` |
| 적용값 | `/etc/default/agent-app`(`root:root 0644`, 원본 [config/etc-default-agent-app.example](../config/etc-default-agent-app.example)): `AGENT_HOME=/opt/agent-app`, `AGENT_PORT=15034`, `AGENT_UPLOAD_DIR=/opt/agent-app/upload_files`, `AGENT_LOG_DIR=/var/log/agent-app`, **`AGENT_KEY_PATH=/opt/agent-app/api_keys`**. 추가: `AGENT_PROCESS_PATTERN=^/opt/agent-app/bin/agent-app-linux-x86`(모니터링용) |
| 키 파일 | `/opt/agent-app/api_keys/secret.key` = 공식 실습 문자열 `agent_api_key_test` 한 줄, `root:agent-core 0640`(admin·dev 읽기, test 거부). 실제 비밀키 아님 |
| 명령 | `B grep -v '^#' /etc/default/agent-app` / `B stat -c '%U:%G %a' /opt/agent-app/api_keys/secret.key` / 내용 일치 여부만 확인(내용 출력 금지, §4 E9) |
| 결과 | 위 값과 일치, `secret.key content ok: yes` |
| 증빙 위치 | 회귀 파일 `## env`, §3(경로 불일치) |

### 2.5 제공 Agent 실행 — PASS

| | |
|---|---|
| 요구사항 | 일반 계정으로 실행, Boot Sequence 5단계 `[OK]`, `Agent READY`, `0.0.0.0:15034` LISTEN |
| 적용값 | `/opt/agent-app/bin/agent-app-linux-x86`(`root:agent-core 0750`, SHA256 `cdbae8c066e734916b7cd25dc9e651818acf63b2e6817125ede5e85a4de0ff5a`, ZIP SHA256 `b0489f10…7732`). 바이너리·ZIP은 저장소에 없음(수동 배포) |
| 실행 | `agent-admin`(uid 1000), 환경변수를 `/etc/default/agent-app`에서 명시 로드: `runuser -u agent-admin -- env -i PATH=/usr/bin:/bin HOME=/home/agent-admin bash -c 'cd ~; set -a; . /etc/default/agent-app; set +a; exec setsid /opt/agent-app/bin/agent-app-linux-x86'`(`sudo`는 Machine 안, 종료는 SIGINT) |
| 결과 | `[1/5]~[5/5]` 모두 `[OK]`, `All Boot Checks Passed!`, `Agent READY`. `LISTEN 0.0.0.0:15034`, 소켓 소유 PID = 자식 프로세스. Mac→Machine IP:15034 연결 성공(작업 17). SIGINT 후 잔여 프로세스 없음, 15034 해제. 상주 서비스로는 구성하지 않음(검증 때만 수동 실행) |
| 증빙 위치 | 회귀 파일 `## agent run`, [b4-1-agent-runtime.md](b4-1-agent-runtime.md) 작업 17·18 |

### 2.6 `monitor.sh` 소유권·Health Check — PASS (요구 7·8)

| | |
|---|---|
| 요구사항 | `/opt/agent-app/bin/monitor.sh` Bash, `agent-dev:agent-core 0750`, cron 실행 계정 `agent-admin`. 프로세스·TCP 15034 점검, 실패 시 `exit 1` |
| 적용값 | `agent-dev:agent-core 750`(`agent-admin`은 `agent-core` 그룹 r-x로 실행, `agent-test`는 `Permission denied`). 프로세스: `pgrep -f '^/opt/agent-app/bin/agent-app-linux-x86'`(부모·자식 둘 다 일치) + LISTEN 소켓 소유 PID가 그중 하나일 때만 OK |
| 명령 | `B stat -c '%U:%G %a' /opt/agent-app/bin/monitor.sh` / `B runuser -u agent-admin -- env -i PATH=/usr/bin:/bin MONITOR_LOG_FILE=/tmp/x.log /opt/agent-app/bin/monitor.sh; echo rc=$?`(Agent 실행 중 / 중지 후 각각; 임시 로그 사용) |
| 결과 | Agent 실행 중: `OK PROCESS pid=[48270 48272]`, `OK PORT … owner pid=[48272] matches`, **`HEALTHY exit 0`**. Agent 중지 후: `FAIL PROCESS`, `FAIL PORT tcp/15034 not LISTEN`, **`UNHEALTHY exit 1`** |
| 종료 코드 정책 | 0 정상(경고는 허용) / 1 Health Check 실패 / 2 모니터링 자체 오류(확인된 실패가 있으면 1 우선) |
| 증빙 위치 | 회귀 파일 `## agent run`, [b4-1-monitor.md](b4-1-monitor.md) |

### 2.7 방화벽 점검 — PASS

| | |
|---|---|
| 요구사항 | 방화벽 활성 확인, 비활성이면 WARNING만(종료 코드 영향 없음) |
| 적용값 | 최소 권한 sudoers `/etc/sudoers.d/90-b4-agent-admin-ufw-status`(`root:root 0440`): `agent-admin ALL=(root) NOPASSWD: /usr/sbin/ufw status`. 인수까지 정확히 일치해야 하며 와일드카드·`ALL` 없음. `monitor.sh`는 `sudo -n /usr/sbin/ufw status`를 사용 |
| 판정 | active → `[OK] FIREWALL` / inactive → `[WARNING] FIREWALL`(exit 0 유지) / 권한 거부 → `[UNKNOWN]` / 그 외 실패 → `[ERROR]` |
| 결과(본환경) | `[OK] FIREWALL ufw active (checked via sudo)`; 비활성 판정은 **UFW를 끄지 않고** 읽기 전용 스텁으로 시연: `[WARNING] FIREWALL ufw inactive`, `HEALTHY exit 0` |
| 결과(테스트 Machine) | **실제 `ufw disable`** 후 Agent 실행 상태에서 `WARNING`, `HEALTHY exit 0`, cron 실행에서도 동일, 모니터링 지속. `ufw --force enable` 후 규칙·정책이 시험 전과 완전히 동일, SSH 20022 유지. 허용 외 sudo 명령(`ufw status verbose`, `disable`, `/bin/bash` 등)·dev/test sudo 모두 거부 |
| 증빙 위치 | 회귀 파일 `UFW inactive WARNING via read-only stub`, [b4-1-monitor.md 작업 19](b4-1-monitor.md#작업-19-ufw-상태-점검과-최소-권한) |

### 2.8 CPU / MEM / DISK — PASS

| | |
|---|---|
| 요구사항 | 사용량 수집, CPU > 20%, MEM > 10%, DISK_USED > 80%이면 WARNING |
| 적용값 | `monitor.sh` 기본값 CPU 20 / MEM 10 / DISK 80(`MONITOR_*_WARN`로 시험 시 변경 가능). **반올림 전 값으로 `>` 비교**(정확히 임계값은 OK, 20.04%는 WARNING) |
| 명령 | 고정 입력 파일 시험 훅 `MONITOR_MEMINFO`, `MONITOR_PROC_STAT(_2)`(§4 E14) / 실제 값은 monitor 실행 출력 |
| 결과 | CPU 20.0%·MEM 10.0%(정확히 임계값) → `[OK]`; 20.1%·10.1% → `[WARNING] … (raw 20.100000) > threshold`. DISK 기본 `threshold 80%`(실측 0.4%). 실제 Agent 실행 중 CPU 3.7~6.6%, MEM 5.0~5.9% |
| 증빙 위치 | 회귀 파일 `thresholds`, [b4-1-monitor.md](b4-1-monitor.md) 작업 16·18 |

### 2.9 `monitor.log` 공식 형식 — PASS

| | |
|---|---|
| 요구사항 | `[YYYY-MM-DD HH:MM:SS] PID:… CPU:..% MEM:..% DISK_USED:..%` 누적 기록 |
| 적용값 | **실행당 정확히 1줄**(실행 끝에서 열기→1회 write→닫기). PID = 확인된 Agent PID(LISTEN 소유 PID 우선), Agent가 없으면 `PID:N/A`(만들어내지 않음). 상세 Health Check는 콘솔 전용. `/var/log/agent-app/monitor.log` `agent-admin:agent-core 660` |
| 명령 | `B tail -5 /var/log/agent-app/monitor.log` / 형식 검증: `B grep -cE '^\[[0-9-]{10} [0-9:]{8}\] PID:([0-9]+\|N/A) CPU:[0-9.]+% MEM:[0-9.]+% DISK_USED:[0-9.]+%$' /var/log/agent-app/monitor.log` |
| 결과 | `[2026-11-13 21:23:02] PID:N/A CPU:0.5% MEM:4.7% DISK_USED:0.4%` 형태(Agent 실행 중에는 `PID:48272`). 동시 실행 20회 → 20줄 모두 유효, 쓰기 실패 시 `ERROR LOG`·exit 2 |
| **참고(혼재)** | 작업 17 이전에 쌓인 **상세 형식 줄(실행당 10줄, 2,280줄)** 은 삭제·변환하지 않고 같은 파일에 남아 있습니다. 새 기록은 공식 형식만 추가됩니다. 따라서 파일 전체를 형식 검사하면 과거 줄이 불일치로 나옵니다(형식 검증은 최근 줄 기준으로 하세요) |
| 증빙 위치 | 회귀 파일 `## cron + official log`, [b4-1-monitor.md 작업 18](b4-1-monitor.md#작업-18-공식-로그-형식agent-정상-모니터링) |

### 2.10 로그 순환 최대 10MB / 10개 — 설정·동작 PASS, 타이머 실행 기록 PENDING

| | |
|---|---|
| 요구사항 | 로그 최대 10MB, 최대 10개 파일 |
| 적용값 | `/etc/logrotate.d/agent-app`(`root:root 0644`, [config/etc-logrotate.d-agent-app](../config/etc-logrotate.d-agent-app)): `su agent-admin agent-core`, **`size 9M`**(9 MiB = 9,437,184 B), `rotate 9`(활성+순환본 9=**최대 10개**), `create 0660 agent-admin agent-core`, `missingok`, `notifempty`, `nocompress`. 실행: systemd `logrotate.timer`(daily) |
| 10MB 해석 | 십진 10 MB와 10 MiB 두 해석 모두 만족하도록 9 MiB 선택. 하루 증가량 약 90~105 KB → 순환 직전 최대 약 9.54 MB |
| **한계** | **엄격한 최대 크기 보장이 아닙니다.** 크기는 logrotate 실행 시점(일 1회)에만 검사되므로 "임계값 도달 후 주기적 순환"입니다. 과제 목적을 넘는 복잡한 구현(시간 단위 타이머 등)은 추가하지 않았습니다. 디스크 상한 ≈ 96 MB |
| 명령 | `B cat /etc/logrotate.d/agent-app` / `B logrotate -d /etc/logrotate.d/agent-app`(변경 없음) / `B systemctl list-timers logrotate.timer` / `B journalctl -u logrotate.service --no-pager` / `B grep agent-app /var/lib/logrotate/status` |
| 결과(동작, 테스트 Machine) | `logrotate -d`: `9437184 bytes (9 rotations)`. 9,437,183 B 순환 안 함 / 9,437,184 B 이상 순환. 연속 14회 순환 후 파일 10개(활성+`.1`~`.9`), 가장 오래된 세대부터 삭제, 모두 `agent-admin:agent-core 660`, `.1` sha256 = 순환 직전 파일. 실제 `logrotate.service` 실행 `Result=success`. `monitor.sh` 30회 연속 실행 중 서비스 순환 3회 → 기록 증가분 정확히 30(손실 0) |
| 결과(본환경) | 설정 파일 설치·`logrotate -d` 오류 없음. `monitor.log` 약 270 KB(임계값의 약 3%)라 순환은 아직 일어나지 않았고, 일어나지 않는 것이 정상. 기존 로그 삭제·초기화 없음 |
| **PENDING** | 설정 설치(2026-11-13 오후) 이후 `logrotate.timer`가 이 설정을 실행한 기록이 아직 없음. `logrotate.timer` active/enabled, 다음 예약 2026-11-14 00:00 KST(±1h), 마지막 실행 11-13 00:00:40은 설치 이전. **타이머 실행 사실과 본환경 로그의 실제 순환은 별개이며**, 타이머가 돌아도 로그가 9 MiB 미만이면 `does not need rotating`이 정상 → 본환경 실제 순환은 수개월 후. 2026-11-14 01:00 KST 이후 확인 명령은 [b4-1-log-rotation.md 작업 20 §4](b4-1-log-rotation.md#작업-20-운영-검증과-공식-요구사항-정합성) |
| 증빙 위치 | 회귀 파일 `## logrotate`, [b4-1-log-rotation.md](b4-1-log-rotation.md) |

### 2.11 cron 매분 실행 — PASS

| | |
|---|---|
| 요구사항 | `agent-admin` crontab으로 `monitor.sh` 매분 실행, 로그 자동 증가 |
| 적용값 | `agent-admin` crontab: `* * * * * MONITOR_TRIGGER=cron /opt/agent-app/bin/monitor.sh >/dev/null 2>&1`(관리 블록 1개, 다른 항목 보존). root crontab 없음. 관리: [scripts/monitor-cron.sh](../scripts/monitor-cron.sh) |
| 명령 | `B crontab -u agent-admin -l` / 두 번 측정(70초 이상 간격): `B wc -l /var/log/agent-app/monitor.log` / `B tail -3 /var/log/agent-app/monitor.log` |
| 결과 | 63초 사이 `2319 → 2320줄`(분당 1줄 증가), 최근 줄이 매분 `HH:MM:02` 시각, 형식 유효. Agent 실행 중에는 `PID:<n>`, 중지 중에는 `PID:N/A`. **카운트 기준은 "줄 수 증가"입니다**(과거 `trigger=cron` 문자열 세기·실행당 10줄 기준은 공식 형식에서는 쓰지 않음) |
| 증빙 위치 | 회귀 파일 `## cron + official log`, [b4-1-cron.md](b4-1-cron.md) |

### 2.12 환경 복구 자동화 — PASS

| | |
|---|---|
| 내용 | `scripts/bootstrap-orbstack.sh`(Mac, sudo 불필요) → `scripts/machine-setup.sh`(Machine 안 root). 단계: `preflight packages ssh ufw accounts sudoers dirs envfile keyfile monitor logfile logrotate cron verify agent`. 멱등(2회차 `changed=0`), 기존 데이터·로그 삭제 없음, SSH 변경은 사전 `sshd -T` 검증·롤백 |
| 명령 | `scripts/bootstrap-orbstack.sh check --no-run`(변경 없음) |
| 결과 | `b4-lab`: `ok=13 diff=0`(Agent 단계는 항상 수동 항목으로 표시). `b4-recovery-test`: 동일, `apply` 2회차 `unchanged=14 changed=0` |
| 한계 | 제공 Agent·SSH 개인키·API 키는 복구 대상이 아님(저장소에 넣지 않음). 상세: [b4-1-recovery.md](b4-1-recovery.md) |

## 3. 공식 설명과 제공 Agent의 차이 (증빙으로 보존)

| | 과제 설명 | 제공 Agent가 요구한 값 |
|---|---|---|
| `AGENT_KEY_PATH` | `$AGENT_HOME/api_keys/t_secret.key`(파일) | `/opt/agent-app/api_keys`(**디렉터리**) |
| 키 파일 | `t_secret.key` | `/opt/agent-app/api_keys/secret.key` |
| 키 내용 | `agent_api_key_test` | 동일(`Verified 'secret.key' with correct key string`) |

작업 17에서 `b4-recovery-test`에 환경변수를 임시로 바꿔 가며 확인한 실행 결과:

| 시도 | 설정 | Agent 출력 |
|---|---|---|
| 1 | `AGENT_KEY_PATH=/opt/agent-app/api_keys/t_secret.key` | `[1/5] OK` → `[2/5] Verifying Environment Variables [FAIL]` `>>> Key Path Mismatch. Expected: /opt/agent-app/api_keys`, 3~5단계 `Skipped`, `System Boot Failed. Process Terminated.` |
| 2 | `AGENT_KEY_PATH=/opt/agent-app/api_keys`, `secret.key` 없음 | `[2/5] OK`, `[3/5] [FAIL]` `>>> Missing File: secret.key (Expected location: /opt/agent-app/api_keys/secret.key)` |
| 3 | 위 경로 + `secret.key`(`agent_api_key_test`, `root:agent-core 0640`) | `[1/5]~[5/5]` 모두 `[OK]` → `All Boot Checks Passed!` → `Agent READY` → `Agent listening at port 15034` |

판단: 실제 실행 파일의 검증이 기준이므로 시도 3의 구성을 채택했습니다(저장소 설정·복구 스크립트·본환경 모두 동일). 과거 작업 16에서 만든 `t_secret.key`는 삭제하지 않았으나 더 이상 사용·관리하지 않습니다. 상세: [b4-1-agent-runtime.md](b4-1-agent-runtime.md) 작업 17.

## 4. 제출 증빙 절차

`B`는 `orb -m b4-lab sudo`입니다. 모든 명령은 **조회 전용**이며(괄호로 표시한 것만 예외) 본환경 설정을 바꾸지 않습니다. 화면 캡처는 아직 찍지 않았으므로 전부 **CAPTURE PENDING**입니다. 아래 명령을 터미널에 실행하고 출력 전체가 보이게 캡처하세요.

| ID | 증빙 | 명령 | 캡처 |
|---|---|---|---|
| E1 | SSH 20022·Root 차단 | `B sshd -T \| grep -E '^(port\|permitrootlogin) '` ; `B ss -tlnp \| grep sshd` | CAPTURE PENDING |
| E2 | Mac에서 SSH 응답 | `IP=$(orb -m b4-lab bash -c "ip -4 -o addr show scope global \| awk '{print \$4}' \| cut -d/ -f1 \| head -1"); perl -MIO::Socket::INET -e '$s=IO::Socket::INET->new(PeerAddr=>"'$IP':20022",Timeout=>5); print scalar <$s>'` | CAPTURE PENDING |
| E3 | Root 로그인 거부 | `B sshd -T \| grep permitrootlogin` (실제 root 접속 시도는 키를 요구하므로 실효 설정으로 증빙) | CAPTURE PENDING |
| E4 | UFW 규칙·정책 | `B ufw status verbose` | CAPTURE PENDING |
| E5 | UFW 허용/차단 동작 | Mac: 20022(열림), 22·15035(timeout), 15034(Agent 중지: refused / 실행: open) — `perl -MIO::Socket::INET -e '$s=IO::Socket::INET->new(PeerAddr=>"<IP>:<포트>",Timeout=>4); print $s?"open":"fail $!"'` | CAPTURE PENDING |
| E6 | 사용자·그룹 | `B getent group agent-common agent-core` ; `B id agent-admin` ; `B id agent-dev` ; `B id agent-test` | CAPTURE PENDING |
| E7 | 디렉터리 권한·ACL·R/W 표 | `B stat -c '%U:%G %a %n' /opt/agent-app /opt/agent-app/upload_files /opt/agent-app/api_keys /var/log/agent-app` ; `B getfacl -p /opt/agent-app/api_keys` ; R/W 표는 [회귀 파일](evidence/task21-b4-lab-regression.txt) `## ACL matrix`(임시 파일을 만들고 즉시 삭제하는 시험이라 변경 후 원복됨 — *예외*) | CAPTURE PENDING |
| E8 | sudo 최소 권한 | `B sudo -l -U agent-admin` ; `B sudo -l -U agent-dev` ; `B sudo -l -U agent-test` | CAPTURE PENDING |
| E9 | 환경변수·키 경로 | `B grep -v '^#' /etc/default/agent-app` ; `B stat -c '%U:%G %a %n' /opt/agent-app/api_keys/secret.key` ; `B bash -c '[ "$(cat /opt/agent-app/api_keys/secret.key)" = agent_api_key_test ] && echo key-ok'` | CAPTURE PENDING |
| E10 | Agent Boot 5/5·READY·LISTEN | §2.5의 실행 명령(*예외: Agent를 수동 실행·SIGINT 종료, 설정 변경 없음*) 후 `B ss -ltnp \| grep 15034` | CAPTURE PENDING |
| E11 | monitor.sh 소유권·배포본 일치 | `B stat -c '%U:%G %a %n' /opt/agent-app/bin/monitor.sh` ; `B cmp /opt/agent-app/bin/monitor.sh - < bin/monitor.sh && echo IDENTICAL` | CAPTURE PENDING |
| E12 | monitor.sh 정상(exit 0)/장애(exit 1) | §2.6 명령을 Agent 실행 중·중지 후 각각(임시 로그 사용, 실제 로그에 상세 줄 안 씀) | CAPTURE PENDING |
| E13 | 방화벽 WARNING | 회귀 파일 `UFW inactive WARNING via read-only stub`와 같은 스텁 명령(본환경 UFW는 건드리지 않음) | CAPTURE PENDING |
| E14 | CPU/MEM/DISK 기준 | 회귀 파일 `## thresholds` 시험 명령(고정 입력 파일) 및 monitor 출력의 `threshold 20%/10%/80%` | CAPTURE PENDING |
| E15 | 공식 monitor.log 최근 줄 | `B tail -5 /var/log/agent-app/monitor.log` ; `B stat -c '%U:%G %a' /var/log/agent-app/monitor.log` | CAPTURE PENDING |
| E16 | cron 등록·자동 증가 | `B crontab -u agent-admin -l` ; `B wc -l /var/log/agent-app/monitor.log`(70초 이상 간격으로 2회) | CAPTURE PENDING |
| E17 | logrotate 설정·검증 | `B cat /etc/logrotate.d/agent-app` ; `B logrotate -d /etc/logrotate.d/agent-app` ; `B systemctl list-timers logrotate.timer` | CAPTURE PENDING |
| E18 | 타이머 실제 실행(2026-11-14 01:00 KST 이후만) | `B journalctl -u logrotate.service --since '2026-11-14 00:00' --no-pager` ; `B grep agent-app /var/lib/logrotate/status` | PENDING (시각 미도래) |
| E19 | bootstrap 정합성 | `scripts/bootstrap-orbstack.sh check --no-run`(Mac, sudo 불필요) → `diff=0` | CAPTURE PENDING |

저장소에 제출용 화면 캡처 파일은 없습니다(Desktop의 2026-11-09 스크린샷은 B4-1 환경 구성 이전의 것이라 증빙으로 사용하지 않음). 텍스트 증빙은 [evidence/task21-b4-lab-regression.txt](evidence/task21-b4-lab-regression.txt)와 각 상세 문서에 있습니다.

## 5. 남은 실측·제약사항

| 구분 | 내용 |
|---|---|
| PENDING | 설정 설치 후 `logrotate.timer` 실행 기록(2026-11-14 00:00~01:00 KST 이후 E18로 확인). 본환경 `monitor.log` 실제 순환은 수개월 후(요구 동작은 테스트 Machine에서 입증) |
| CAPTURE PENDING | E1~E17, E19 제출용 화면 캡처 |
| 제약 | 로그 순환은 절대 최대 크기 보장이 아님(§2.10). Agent는 상주 서비스가 아니라 검증 때 수동 실행. `agent_app.log`(Agent 자체 로그, 같은 디렉터리)는 순환 설정 대상 아님. `monitor.log`에는 과거 상세 형식과 공식 형식이 공존 |
| Owner 검수 | 공식 미션 원문 전체와의 최종 대조, 전체 미션 완료 판정 |

## 6. 이력 문서

작업별 상세 기록은 참고용입니다(일부 서술은 당시 상태이며 각 문서 상단의 "현황" 안내가 우선): [orbstack-environment.md](orbstack-environment.md), [b4-1-permission-plan.md](b4-1-permission-plan.md), [b4-1-agent-runtime.md](b4-1-agent-runtime.md), [b4-1-monitor.md](b4-1-monitor.md), [b4-1-cron.md](b4-1-cron.md), [b4-1-log-rotation.md](b4-1-log-rotation.md), [b4-1-recovery.md](b4-1-recovery.md), [b4-1-official-alignment.md](b4-1-official-alignment.md), B4-2 인수인계 [b4-2-environment-handoff.md](b4-2-environment-handoff.md), 작업 15 시점 수행 내역서 [archive/](archive/b4-1-final-evidence-task15.md).
