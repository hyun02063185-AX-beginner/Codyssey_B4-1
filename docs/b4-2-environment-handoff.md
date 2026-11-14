# B4-2 환경 인수인계

> **현재 상태(작업 22, 2026-11-14):** 이 문서는 현재 구현과 일치하도록 갱신됐습니다. 제공 Agent는 실행·모니터링 검증 완료(수동 실행, 상주 서비스 아님), `monitor.sh`는 Agent 실행 시 `exit 0`·중지 시 `exit 1`, `monitor.log`는 공식 형식 1줄/실행, `logrotate`는 `size 9M`·`rotate 9`입니다. 필수 13개 항목 모두 PASS이고 `logrotate.timer`도 2026-11-14 00:00:01 KST에 설정 설치 후 처음 실행·성공했습니다(로그가 9 MiB 미만이라 순환은 없음, 정상). 남은 것은 Owner의 화면 캡처와 최종 검수뿐입니다. 과거 작업 문서(`b4-1-*.md`)의 옛 서술(Agent 없음, 10줄/실행 등)은 기록용이며 이 문서와 [b4-1-final-evidence.md](b4-1-final-evidence.md)가 우선합니다.

B4-2는 B4-1에서 만든 Linux 환경과 `monitor.sh`를 **그대로 재사용**합니다. 이 문서는 B4-2 작업자가 바로 쓸 수 있는 값·명령·주의사항만 모았습니다. 근거와 실측은 [b4-1-final-evidence.md](b4-1-final-evidence.md)와 각 상세 문서에 있습니다.

- B4-2 저장소: https://github.com/hyun02063185-AX-beginner/Codyssey_B4-2
- 이 저장소: https://github.com/hyun02063185-AX-beginner/Codyssey_B4-1
- 인수인계 시점: 2026-11-14 (작업 22, 최종 마감)

> **먼저 읽을 것.** 제공 Agent 바이너리(`agent-app-linux-x86`)와 ZIP은 **저장소에 없습니다**(수동 배포 방법·해시는 [b4-1-agent-runtime.md](b4-1-agent-runtime.md)). 값은 공식 요구값과 제공 Agent 실행 결과로 확정했고, 최종 원문 대조·완료 판정은 Owner 검수 대상입니다.

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

## 3. 사용자·그룹·접근 권한 (공식 구성)

| 계정 | 보조 그룹 | upload_files | api_keys | /var/log/agent-app |
|---|---|---|---|---|
| `agent-admin` | `agent-common`, `agent-core` | R/W | R/W | R/W |
| `agent-dev` | `agent-common`, `agent-core` | R/W | R/W | R/W |
| `agent-test` | `agent-common` | R/W | 거부 | 거부 |

- sudo: `agent-dev`·`agent-test`는 **없음**. `agent-admin`은 `/etc/sudoers.d/90-b4-agent-admin-ufw-status`(`0440`)로 **`/usr/sbin/ufw status` 한 명령만** 비밀번호 없이 허용(방화벽 상태 점검용). B4-2에서도 더 부여하지 마세요.
- 그룹: `agent-common` = admin·dev·test, `agent-core` = admin·dev (공식). 키 파일 `api_keys/secret.key`는 `root:agent-core 0640`.

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
AGENT_KEY_PATH=/opt/agent-app/api_keys   # 키 디렉터리(제공 Agent가 요구). 안의 secret.key = 실습 문자열(root:agent-core 0640)
AGENT_PROCESS_PATTERN=^/opt/agent-app/bin/agent-app-linux-x86   # monitor.sh의 Agent 식별 기준
```

- 과제 설명은 `AGENT_KEY_PATH=…/api_keys/t_secret.key`(파일)지만 **제공 Agent는 디렉터리 `/opt/agent-app/api_keys`와 `secret.key`를 요구**합니다(실행 오류·정상 부팅 증거: [final-evidence §3](b4-1-final-evidence.md)).

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
| 설정 변수 | `AGENT_PROCESS_PATTERN`(설정됨), 시험용 `MONITOR_CPU_WARN`/`MEM_WARN`/`DISK_WARN`·`MONITOR_LOG_FILE` 등 |

- **Agent가 실행 중이면 `exit 0`, 중지되어 있으면 `exit 1`**(프로세스·포트 FAIL)이 정상 동작입니다. Agent는 상주 서비스가 아니라 필요할 때 `agent-admin`으로 수동 실행합니다(실행 명령: [final-evidence §2.5](b4-1-final-evidence.md)). 그래서 cron 로그에는 Agent 중지 구간이 `PID:N/A`로 남는 것이 정상입니다.
- 로그를 쓰려면 `agent-core` 그룹이 필요합니다(`agent-admin`은 소속). 다른 계정으로 실행하면 로그 열기 실패 → exit 2.
- 판정 규칙 전체: [b4-1-monitor.md §3–4](b4-1-monitor.md)

## 6. `monitor.log` 와 logrotate

| 항목 | 값 |
|---|---|
| 로그 | `/var/log/agent-app/monitor.log`, `agent-admin:agent-core 0660` |
| 형식 | **공식(작업 18):** `[YYYY-MM-DD HH:MM:SS] PID:… CPU:…% MEM:…% DISK_USED:…%` 1줄/실행(Agent 없으면 `PID:N/A`). 작업 17 이전 기록은 `YYYY-MM-DD HH:MM:SS [LEVEL] CATEGORY message` 상세 형식이 그대로 남아 있음. 상세 Health Check는 콘솔에만 출력(cron은 버림) |
| 혼재 | 과거 상세 형식 줄(2,280줄)은 삭제하지 않고 같은 파일에 남아 있음 — 형식 검증·분석은 `grep -E '^\[[0-9-]{10} '`로 공식 형식 줄만 골라서 |
| 순환 | `/etc/logrotate.d/agent-app`: `size 9M`(9 MiB = 9,437,184 B), `rotate 9`(활성+순환본 9=최대 10개), `create 0660 agent-admin agent-core`, `su agent-admin agent-core`, rename+create |
| 발동 | 기존 `logrotate.timer` 일 1회(00:00 KST) |

- 확인: `orb -m b4-lab sudo tail -20 /var/log/agent-app/monitor.log`
- **순환은 엄격한 최대 크기 보장이 아닙니다**(일 1회 검사 사이에 9 MiB 임계값 초과 가능). 설정 설치 후 타이머 실행 확인 완료(2026-11-14 00:00:01 KST, 성공). 타이머가 돌아도 로그가 9 MiB 미만이면 순환하지 않는 것이 정상이며 아직 순환은 없습니다.
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
- `pause`/`resume`은 다른 crontab 항목을 보존합니다. 매분 실행이 공식 형식 1줄씩 쌓이므로, 분석 실험 전에 `pause`하고 끝나면 `resume`하세요.
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
- 장애 감지 로그: Agent 중지 구간(`PID:N/A`)과 실행 구간(`PID:<n>`)이 모두 공식 형식으로 누적되어 있어 로그 읽기 연습에 쓸 수 있음. 과거 상세 형식(Agent 부재 시절 `exit 1`) 줄도 남아 있음

## 10. 제공 Agent 의존 항목 (현재 상태)

| 항목 | 지금 상태 |
|---|---|
| 제공 Agent 설치·실행 (실행 계정·명령·Python 요구 확인) | **완료(작업 17)** — `/opt/agent-app/bin/agent-app-linux-x86`(`root:agent-core 0750`) 수동 배포, `agent-admin`으로 실행 |
| `AGENT_KEY_PATH` 값 | 확정(작업 17): `/opt/agent-app/api_keys` (디렉터리, 안에 `secret.key`) |
| `AGENT_PROCESS_PATTERN` 설정 → 프로세스 점검 판정 | **설정됨(작업 18)** `^/opt/agent-app/bin/agent-app-linux-x86` → Agent 실행 시 exit 0 |
| Boot Sequence 5단계 `[OK]`, `Agent READY` | PASS(작업 17) |
| `0.0.0.0:15034` LISTEN, 소유 PID 일치 | PASS(작업 17·18) |
| `monitor.sh` exit 0 (정상 Health Check) | PASS(작업 18, Agent 실행 중). 중지 시 exit 1 |
| 상주 서비스(systemd 등)로 Agent 상시 실행 | **이번 범위 밖**(수동 실행). 필요하면 B4-2에서 별도 설계 |
| B4-2의 `agent-leak-app` 등 장애 분석 대상 | **B4-1 Agent와 별개** — 별도로 확보 필요 |
| 공식 원문 최종 대조·완료 판정 | Owner 검수 — 값이 바뀌면 이 문서와 [b4-1-final-evidence.md](b4-1-final-evidence.md)를 함께 갱신 |

Agent 수동 배포(저장소에 없음): `orb -m b4-lab sudo install -o root -g agent-core -m 0750 /dev/stdin /opt/agent-app/bin/agent-app-linux-x86 < agent-app-linux-x86`, SHA256 `cdbae8c066e734916b7cd25dc9e651818acf63b2e6817125ede5e85a4de0ff5a` 확인. `machine-setup.sh`의 `agent` 단계는 배포 상태를 표시만 하고 설치하지 않습니다.
