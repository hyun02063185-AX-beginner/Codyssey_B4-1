# B4-2 환경 인수인계

> **작업 19 현황(최신):** `agent-admin`은 `/etc/sudoers.d/90-b4-agent-admin-ufw-status`(root:root 0440)로 **정확히 `/usr/sbin/ufw status`만** 비밀번호 없이(`sudo -n`) 실행할 수 있고, `monitor.sh`는 UFW 활성 `OK` / 비활성 `WARNING`(exit 영향 없음) / 권한 거부 `UNKNOWN`을 구분합니다. 이 문서의 "sudo 없음 / UFW UNKNOWN / UFW 비활성 PENDING" 서술은 당시 기록이며 [monitor 기록 작업 19](b4-1-monitor.md#작업-19-ufw-상태-점검과-최소-권한)가 우선합니다. `agent-dev`·`agent-test`는 여전히 sudo 없음.


> **작업 18 현황(최신):** 제공 Agent는 확보·실행 검증 완료(Boot 5/5, `Agent READY`, 0.0.0.0:15034). `AGENT_PROCESS_PATTERN=^/opt/agent-app/bin/agent-app-linux-x86` 설정으로 Agent 실행 중 `monitor.sh`는 `HEALTHY exit 0`, 중지 시 `exit 1`. `monitor.log`는 **공식 형식 1줄/실행**(`[시각] PID:… CPU:…% MEM:…% DISK_USED:…%`)이며 상세 Health Check는 콘솔에만 출력. 과거 상세 로그(10줄/실행)는 그대로 남아 있어 한 파일에 두 형식이 공존. 아래 본문 중 "Agent NOT FOUND / `AGENT_KEY_PATH` PENDING / 임시 로그 형식"은 당시 기록이며 [Agent 실행 기록](b4-1-agent-runtime.md#작업-18-agent-정상-모니터링공식-로그-형식)이 우선합니다.


B4-2는 B4-1에서 만든 Linux 환경과 `monitor.sh`를 **그대로 재사용**합니다. 이 문서는 B4-2 작업자가 바로 쓸 수 있는 값·명령·주의사항만 모았습니다. 근거와 실측은 [b4-1-final-evidence.md](b4-1-final-evidence.md)와 각 상세 문서에 있습니다.

- B4-2 저장소: https://github.com/hyun02063185-AX-beginner/Codyssey_B4-2
- 이 저장소: https://github.com/hyun02063185-AX-beginner/Codyssey_B4-1
- 인수인계 시점: 2026-11-13 (작업 15)

> **먼저 읽을 것.** 제공 Agent는 작업 17·18에서 실행·모니터링 검증을 마쳤습니다(바이너리는 저장소에 없음, 수동 배포). 모든 값은 공식 원문과 대조되지 않았습니다 — [관리자료] 또는 [승인된 실습 설계]입니다.

## 1. Machine

| 항목 | 값 |
|---|---|
| 호스트 | 교육장 Mac (macOS x86_64, **sudo 불가**), OrbStack 2.0.5 |
| 실습 Machine | **`b4-lab`** (OrbStack Linux Machine, `ubuntu:noble`) |
| OS | Ubuntu **24.04.5 LTS**, x86_64, Python 3.12.3, systemd |
| 접속 | `orb -m b4-lab <명령>` / root 명령은 `orb -m b4-lab sudo <명령>` (Machine 안에서만 sudo 가능) |
| IP·호스트명 | 가변(예: `192.168.139.18`), `b4-lab.orb.local` — `orb list`로 확인 |
| 검증용 Machine | `b4-recovery-test` (중지 상태, 삭제 금지 — 복구 스크립트 시험용) |
| 원칙 | `b4-lab`은 삭제·초기화하지 않는다. B4-2에서 장애 실험이 필요하면 **새 Machine 또는 복제 환경**에서 한다. |

## 2. 포트

| 포트 | 용도 | 상태 |
|---|---|---|
| TCP **20022** | Ubuntu sshd (미션 SSH). UFW 허용 | LISTEN (`0.0.0.0`, `[::]`) |
| TCP **15034** | Agent 포트. UFW 허용 | Agent 실행 중에만 LISTEN(상주 서비스 아님). 중지 상태에서는 refused |
| TCP 22 | 미사용 | UFW drop (timeout) |
| 그 외 인바운드 | UFW default deny | 차단 (아웃바운드는 allow) |

- **OrbStack 관리 SSH(`orb -m`, `ssh b4-lab@orb`, `b4-lab.orb.local:22`)는 Ubuntu sshd(20022)와 별개**입니다. Root 차단·UFW와 무관하게 유지됩니다. 헷갈리지 마세요 ([orbstack-environment.md §5](orbstack-environment.md)).
- Root 원격 로그인은 `PermitRootLogin no`. 설정: `/etc/ssh/sshd_config.d/10-b4-mission.conf`, `ssh.socket` 비활성 + `ssh.service` 상시 실행.
- `agent-*` 계정은 비밀번호가 잠겨 있고 SSH 키가 없어 **SSH로 로그인할 수 없습니다.** 계정 전환은 `orb -m b4-lab sudo -u agent-admin …`.

## 3. 사용자·그룹·접근 권한 [승인된 실습 설계]

| 계정 | 보조 그룹 | upload_files | api_keys | /var/log/agent-app |
|---|---|---|---|---|
| `agent-admin` | `agent-common`, `agent-core` | R/W | R/W | R/W |
| `agent-dev` | `agent-common`, `agent-core` | R/W | R/W | R/W |
| `agent-test` | `agent-common` | R/W | 거부 | 거부 |

- sudo는 **어느 agent-* 계정에도 없습니다.** B4-2에서도 부여하지 마세요(필요하면 먼저 권한 설계를 갱신).
- `agent-admin`이 `api_keys`까지 R/W인 것은 단순 검증용으로 **의도한 설계**입니다(공식 원문 확인 후 조정 가능).

| 경로 | 소유자:그룹 | mode |
|---|---|---|
| `/opt/agent-app` (= `AGENT_HOME`) | `root:root` | `0755` |
| `/opt/agent-app/upload_files` | `agent-admin:agent-common` | `2770` + ACL |
| `/opt/agent-app/api_keys` | `root:agent-core` | `2770` + ACL (`secret.key` 실습 문자열 1개, 실제 키 없음) |
| `/var/log/agent-app` | `root:agent-core` | `2770` + ACL |
| `/opt/agent-app/bin` | `root:root` | `0755` |

- 파일 생성 프로그램이 **명시적 mode 0644**를 요청하면 ACL mask가 `r--`가 되어 그룹 쓰기가 막힐 수 있습니다. B4-2에서 파일을 만드는 코드는 이 점을 확인하세요([permission §11.4](b4-1-permission-plan.md)).

## 4. Agent 환경변수 파일

- 경로: **`/etc/default/agent-app`** (`root:root 0644`, `KEY=VALUE`, 비밀값 없음). 원본: [config/etc-default-agent-app.example](../config/etc-default-agent-app.example)

```
AGENT_HOME=/opt/agent-app
AGENT_PORT=15034
AGENT_UPLOAD_DIR=/opt/agent-app/upload_files
AGENT_LOG_DIR=/var/log/agent-app
AGENT_KEY_PATH=/opt/agent-app/api_keys   # 키 디렉터리. 안의 secret.key = 실습 문자열(root:agent-core 0640)
```

- **로그인 셸·cron에는 자동으로 들어가지 않습니다.** 사용하려면 명시적으로 로드: `set -a; . /etc/default/agent-app; set +a` (systemd는 `EnvironmentFile=/etc/default/agent-app`). `monitor.sh`는 이미 이렇게 로드합니다.
- 비밀값(실제 API 키 등)을 이 파일에 넣지 마세요(0644, 모든 계정이 읽음).

## 5. `monitor.sh`

| 항목 | 값 |
|---|---|
| 경로 | **`/opt/agent-app/bin/monitor.sh`** (= `$AGENT_HOME/bin/monitor.sh`), `agent-dev:agent-core 0750` |
| 소스 | [bin/monitor.sh](../bin/monitor.sh) (Bash). 저장소와 배포본 sha256 일치 확인됨 |
| 실행 | `orb -m b4-lab sudo -u agent-admin /opt/agent-app/bin/monitor.sh; echo $?` |
| 점검 | Agent 프로세스, TCP 15034(주소·소유 PID), UFW, CPU/MEM/DISK(공식 임계 CPU>20 / MEM>10 / DISK>80%) |
| 종료 코드 | `0` 정상 / `1` 프로세스·포트 실패 또는 확인 불가 / `2` 모니터링 자체 오류 (1이 2보다 우선) |
| 방화벽 | 비활성 → `WARNING`만(exit 영향 없음). `agent-admin`은 `sudo -n /usr/sbin/ufw status`만 허용(작업 19)되어 실제 상태 판정, 권한 거부 시 `UNKNOWN` |
| 설정 변수 | `AGENT_PROCESS_PATTERN`(Agent 식별 기준 — **미설정**), `MONITOR_CPU_WARN`/`MEM_WARN`/`DISK_WARN` 등 |

- **현재 `exit 1`은 정상 동작입니다.** Agent가 없어서 `PENDING PROCESS` + `FAIL PORT`가 나오는 것이 "예상된 장애 감지"입니다. B4-2의 장애 분석 입력으로 이 로그를 쓰되, **Agent가 없는 상태에서의 exit 1을 실제 장애로 오해하지 마세요.**
- 로그를 쓰려면 `agent-core` 그룹이 필요합니다(`agent-admin`은 소속). 다른 계정으로 실행하면 로그 열기 실패 → exit 2.
- 판정 규칙 전체: [b4-1-monitor.md §3–4](b4-1-monitor.md)

## 6. `monitor.log` 와 logrotate

| 항목 | 값 |
|---|---|
| 로그 | `/var/log/agent-app/monitor.log`, `agent-admin:agent-core 0660` |
| 형식 | **공식(작업 18):** `[YYYY-MM-DD HH:MM:SS] PID:… CPU:…% MEM:…% DISK_USED:…%` 1줄/실행(Agent 없으면 `PID:N/A`). 작업 17 이전 기록은 `YYYY-MM-DD HH:MM:SS [LEVEL] CATEGORY message` 상세 형식이 그대로 남아 있음. 1회 실행 = 10줄, 마지막이 `SUMMARY result=… exit=…` |
| 구분 | `START … trigger=cron\|manual` 로 cron/수동 구분 |
| 순환 | `/etc/logrotate.d/agent-app`: `size 10M`, `rotate 9`(활성+순환본 9=최대 10개), `create 0660 agent-admin agent-core`, `su agent-admin agent-core`, rename+create |
| 발동 | 기존 `logrotate.timer` 일 1회(00:00 KST) |

- 확인: `orb -m b4-lab sudo tail -20 /var/log/agent-app/monitor.log`
- **순환은 엄격한 최대 크기 보장이 아닙니다**(일 1회 검사 사이에 10 MiB 초과 가능). 이 정책의 실제 타이머 발동은 **미확인(PENDING)** — 2026-11-14 00:00 KST 이후 `journalctl -u logrotate.service`로 확인.
- 분석할 때 순환본(`monitor.log.1`, …)도 같이 보세요. 로그를 직접 지우거나 `truncate`하지 마세요.

## 7. cron 관리·중지·재개

`agent-admin` crontab에 매분 실행이 등록되어 있습니다(관리 블록 `# BEGIN/END B4-1 monitor`):

```
* * * * * MONITOR_TRIGGER=cron /opt/agent-app/bin/monitor.sh >/dev/null 2>&1
```

Mac 터미널에서, 저장소 루트(`cd Codyssey_B4-1`)에서 (스크립트는 root로 실행되어야 하므로 `sudo`로 감싼다):

```bash
orb -m b4-lab sudo crontab -u agent-admin -l                                  # 현재 등록 보기
# 저장소 스크립트로 관리 (stdin 전달; 경로는 저장소 루트 기준)
orb -m b4-lab sudo bash -s -- status  < scripts/monitor-cron.sh
orb -m b4-lab sudo bash -s -- pause   < scripts/monitor-cron.sh                  # 장애 실험 중 로그 오염 방지
orb -m b4-lab sudo bash -s -- resume  < scripts/monitor-cron.sh
orb -m b4-lab sudo bash -s -- install < scripts/monitor-cron.sh                  # 중복 없이 (재)등록
orb -m b4-lab sudo bash -s -- remove  < scripts/monitor-cron.sh
```

- 같은 명령이 [b4-1-cron.md §6](b4-1-cron.md)에 검증된 형태로 기록되어 있습니다. `status`는 ACTIVE / PAUSED / NOT_INSTALLED를 출력합니다.
- `pause`/`resume`은 다른 crontab 항목을 보존합니다. 매분 실행이 로그에 `trigger=cron`으로 쌓이므로, 분석 실험 전에 `pause`하고 끝나면 `resume`하세요.
- **알려진 공백:** cron이 출력을 버리므로 로그 쓰기 실패는 "새 줄이 안 생김"으로만 보입니다.

## 8. GitHub 기반 복구 (Mac 초기화 후)

상태의 원본은 이 GitHub 저장소입니다. **Mac에서 sudo 없이** 동작합니다.

```bash
git clone https://github.com/hyun02063185-AX-beginner/Codyssey_B4-1.git && cd Codyssey_B4-1
scripts/bootstrap-orbstack.sh all                       # = create + apply + verify (새 Machine, 약 1분 + cron 확인)
scripts/bootstrap-orbstack.sh check --no-run            # 기존 Machine 점검 (지속 설정 변경 없음, monitor.sh 미실행)
scripts/bootstrap-orbstack.sh apply --allow-existing    # 차이 나는 단계만 복구 (로그·타 crontab 항목 보존)
scripts/bootstrap-orbstack.sh snapshot                  # 상태 스냅샷 (Machine 간 비교용)
```

- 다른 이름: `--machine NAME`. 기존 Machine을 삭제·초기화하는 기능은 없습니다.
- SSH 단계는 재시작 **전에** `sshd -t`/`sshd -T`로 검증하고, 충돌이 있으면 조각을 복원한 채 중단합니다.
- **복구되지 않는 것:** 제공 Agent 원본, SSH 개인키·API 키·비밀번호, Mac의 키쌍, 기존 `monitor.log` 내용, 업로드 파일.
- 상세: [b4-1-recovery.md](b4-1-recovery.md)

## 9. B4-2에서 바로 재사용 가능한 항목

- Machine `b4-lab`, Ubuntu 24.04.5, 계정·그룹·권한 구조(§3), 포트·UFW(§2)
- `monitor.sh`(경로·종료 코드·로그 형식이 고정) — 프로세스/포트/UFW/CPU·MEM·DISK 점검과 `monitor.log`
- `agent-admin` 매분 cron, logrotate 설정, `monitor-cron.sh`의 pause/resume
- 환경변수 파일 구조와 명시 로드 방식(§4)
- `bootstrap-orbstack.sh` — 같은 환경을 새 Machine에 재구성, `snapshot`으로 일치 확인
- 장애 감지 로그: Agent 부재 상황의 `exit 1` 기록이 이미 누적되어 있어, 로그 읽기 연습용으로 쓸 수 있음

## 10. 제공 Agent가 확보되어야 가능한 항목

| 항목 | 지금 상태 |
|---|---|
| 제공 Agent 설치·실행 (실행 계정·명령·Python 요구 확인) | **완료(작업 17)** — `/opt/agent-app/bin/agent-app-linux-x86`(`root:agent-core 0750`) 수동 배포, `agent-admin`으로 실행 |
| `AGENT_KEY_PATH` 값 | 확정(작업 17): `/opt/agent-app/api_keys` (디렉터리, 안에 `secret.key`) |
| `AGENT_PROCESS_PATTERN` 설정 → 프로세스 점검 판정 | **설정됨(작업 18)** `^/opt/agent-app/bin/agent-app-linux-x86` → Agent 실행 시 exit 0 |
| Boot Sequence 5단계 `[OK]`, `Agent READY` | PASS(작업 17) |
| `0.0.0.0:15034` LISTEN, 소유 PID 일치 | PASS(작업 17·18) |
| `monitor.sh` exit 0 (정상 Health Check) | 미검증 |
| B4-2의 `agent-leak-app` 등 장애 분석 대상 | **B4-1 Agent 파일의 존재 증거가 아님** — 별도로 확보 필요 |
| 공식 원문과의 값 대조(포트·권한·임계값·로그 형식·소속) | 미완료 — 값이 바뀌면 이 문서와 [b4-1-final-evidence.md](b4-1-final-evidence.md)를 함께 갱신 |

Agent를 확보하면: ① 파일/아키텍처 확인 → ② 실행 계정·`AGENT_KEY_PATH` 결정 → ③ `AGENT_PROCESS_PATTERN` 설정 → ④ `monitor.sh` 재검증 → ⑤ `machine-setup.sh`의 `agent` 단계 구현 순으로 진행하세요.

## 11. 변경하지 말 것 (B4-1 값 고정)

Machine 이름 `b4-lab`, Ubuntu 24.04, 사용자·그룹명, 포트 20022/15034, `monitor.sh` 경로, 로그 경로는 B4-2에서 바꾸지 않는 것이 원칙입니다. 바꾸면 README와 이 문서에 기록하세요.
