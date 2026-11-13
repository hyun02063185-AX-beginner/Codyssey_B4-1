# B4-1 monitor.sh 구현 및 1차 검증 (작업 10)

- 일시: 2026-11-13 / 기준 커밋 `dec6b17`
- 소스: [bin/monitor.sh](../bin/monitor.sh) (Bash 전용) → 배포: `/opt/agent-app/bin/monitor.sh`
- 범위: 점검 스크립트 구현·1차 검증. **cron 등록, 로그 파일 기록, 로그 순환, bootstrap은 포함하지 않음**(다음 작업). 제공 Agent는 없고 대체 구현도 하지 않음.
- 값의 구분: **[설계 기본값]** 이 작업에서 정한 임시값(공식 요구 아님) / **[원문 미확인]** / **[실측]**.

## 1. 배포 위치·권한 (설계 결정, 원문 미확인)

| 경로 | 소유자:그룹 | mode | 이유 |
|---|---|---|---|
| `/opt/agent-app/bin` | `root:root` | `0755` | 기존 `/opt/agent-app`(root:root 755)과 동일. 일반 계정이 스크립트를 바꿔치기할 수 없음 |
| `/opt/agent-app/bin/monitor.sh` | `root:agent-admin` | `0750` | cron 계정 `agent-admin`만 실행(그룹 r-x), 수정 불가. 그 외 일반 계정은 실행·열람 불가 |

기존 권한 설계(작업 7~8)의 `upload_files`/`api_keys`/로그 디렉터리와 충돌하지 않으며 ACL은 추가하지 않았습니다. 소유자·mode의 공식 정책이 확인되면 조정합니다. [실측] `agent-admin` 실행 가능, `agent-dev`/`agent-test` 실행 `Permission denied`, `agent-admin`의 스크립트 수정·`bin/` 쓰기 불가.

## 2. 실행 방법

```bash
sudo -u agent-admin env -i PATH=/usr/bin:/bin /opt/agent-app/bin/monitor.sh; echo "exit=$?"
```

- `/etc/default/agent-app`을 **스크립트가 직접 `source`** 합니다(`MONITOR_ENV_FILE`로 다른 파일 지정 가능). 로그인 셸·`.bashrc`에 의존하지 않으므로 `env -i`에서도 동작합니다.
- 필수 변수: `AGENT_HOME`, `AGENT_PORT`(정수 1~65535), `AGENT_UPLOAD_DIR`, `AGENT_LOG_DIR`. 하나라도 없거나 잘못되면 점검 없이 종료 코드 2.
- `AGENT_KEY_PATH`는 비어 있어도 됩니다(모니터링에 불필요, 안내 메시지만 출력).
- 출력은 stdout만 사용합니다. 라인 형식은 `YYYY-MM-DD HH:MM:SS [LEVEL] CATEGORY message`이며 **로그 포맷의 공식 지정은 [원문 미확인]** 이라 임시 형식입니다.

### 실제 출력 (agent-admin, env -i, 2026-11-13)

```
[INFO] START user=agent-admin uid=1000 host=b4-lab env_file=/etc/default/agent-app
[INFO] CONFIG AGENT_HOME=/opt/agent-app AGENT_PORT=15034 AGENT_UPLOAD_DIR=/opt/agent-app/upload_files AGENT_LOG_DIR=/var/log/agent-app
[INFO] CONFIG AGENT_KEY_PATH is empty (PENDING in setup); not needed for monitoring, continuing
[PENDING] PROCESS agent identification criteria not configured (AGENT_PROCESS_PATTERN unset); not assuming any python process is the Agent
[FAIL] PORT tcp/15034 not LISTEN
[UNKNOWN] FIREWALL cannot read ufw status as uid=1000 (needs root; no sudo granted). hint only: ufw.conf ENABLED=yes
[OK] CPU usage=0.2% (threshold 80% [design default])
[OK] MEM usage=3.6% (total=16434648kB available=15840160kB) (threshold 80% [design default])
[OK] DISK usage=0.2% path=/ mount=/ (threshold 80% [design default])
[INFO] SUMMARY result=UNHEALTHY exit=1 fail=1 pending=1 warning=0 unknown=1 error=0
exit=1
```
(각 라인 앞의 타임스탬프는 생략)

## 3. 점검 항목과 판정

| 항목 | 방법 | 판정 |
|---|---|---|
| **A. Agent 프로세스** | `pgrep -f "$AGENT_PROCESS_PATTERN"`(확장 정규식, 자신·부모 PID 제외). 패턴은 **Agent 확보 후 `/etc/default/agent-app` 등에서 설정**. 임의의 python 프로세스를 Agent로 보지 않음 | 패턴 미설정 → `PENDING`(정상 아님, exit 1) / 패턴 불일치 → `FAIL` / 일치 → `OK` |
| **B. TCP 포트** | `ss -H -ltnp`에서 `AGENT_PORT`의 실제 LISTEN 소켓 확인. UFW 허용 규칙은 보지 않음. 포트가 열려 있어도 "Agent 정상"으로 단정하지 않으며, 프로세스 일치 시에는 listener PID와 대조 | LISTEN 없음 → `FAIL` / 있음 → `OK`(소유자 PID는 가능한 경우만 표시) |
| **C. UFW** | `ufw status` 출력의 `Status:` 행. `ufw.service`/`ufw.conf`는 판정에 쓰지 않고 hint로만 표기 | `active` → `OK` / `inactive` → `WARNING` / 권한 부족 → `UNKNOWN` / ufw 없음 → `WARNING` / 그 외 실패 → `ERROR` |
| **D. CPU** | `/proc/stat` 집계 `cpu` 행을 1초 간격(`MONITOR_CPU_INTERVAL`)으로 2회 읽어 `100×(ΔTotal−ΔIdle)/ΔTotal`. Total = user+nice+system+idle+iowait+irq+softirq+steal, Idle = idle+iowait | 임계값 **초과**(`>`) → `WARNING` |
| **D. MEM** | `/proc/meminfo`: `100×(MemTotal−MemAvailable)/MemTotal` | 동일 |
| **D. DISK** | `df -Pk $MONITOR_DISK_PATH`(기본 `/`): `100×used/(used+avail)` (df의 `Use%`와 같은 기준, 반올림 없음) | 동일 |

임계값(모두 **[설계 기본값]**, 공식 요구값 아님): `MONITOR_CPU_WARN=80`, `MONITOR_MEM_WARN=80`, `MONITOR_DISK_WARN=80`(%). 환경변수 또는 env 파일로 변경 가능. 수치 수집이 실패하면 `ERROR`(값을 추정하지 않음).

### UFW 점검 권한 제약

`ufw status`는 root 권한이 필요합니다. `agent-admin`에게는 sudo를 주지 않았으므로(요구 없음) **cron으로 `agent-admin`이 실행하면 방화벽 상태는 항상 `UNKNOWN`** 입니다. 이를 `OK`로 처리하지 않습니다. 선택지(다음 작업에서 결정):
1. `UNKNOWN`을 그대로 수용(현재 동작).
2. `/etc/sudoers.d/`에 `ufw status` 한 가지 명령만 NOPASSWD 허용(권한 추가이므로 승인 필요).
3. root cron(`agent-admin` crontab 요구와 충돌 가능, 원문 확인 필요).

root로 실행하면 실제 상태를 판정합니다([실측] `ufw active` → `OK`).

## 4. 종료 코드 (설계 정의, 공식 정의는 [원문 미확인])

| 코드 | 의미 |
|---|---|
| `0` | Agent 프로세스 확인(`OK`) **그리고** 포트 LISTEN(`OK`). WARNING/UNKNOWN은 있어도 0 |
| `1` | 실제 장애 또는 확인 불가: 프로세스 `FAIL`, 프로세스 식별 기준 미설정 `PENDING`, 포트 LISTEN 없음 |
| `2` | 모니터링 자체의 오류만 있는 경우: 설정 오류(env 파일 없음, 잘못된 포트·임계값), 필수 명령 없음, 수치 수집 실패, `ufw status` 예상 외 실패 |

- 장애(1)와 모니터링 오류(2)가 함께 있으면 **1이 우선**합니다.
- 방화벽 비활성은 `WARNING`이며 종료 코드에 영향 없음(README: "WARNING 시 종료 코드 [확인 필요]" → 0으로 정함).
- **Agent가 없는 현재 환경에서는 exit 0(전체 Health Check PASS)이 나올 수 없습니다.**

## 5. 테스트 결과 [실측, Ubuntu `b4-lab`]

판정은 PASS / FAIL / PENDING으로 구분합니다. 수치·판정 로직은 고정 입력 파일, `MONITOR_*` 테스트 훅(`MONITOR_PROC_STAT(_2)`, `MONITOR_MEMINFO`, `MONITOR_UFW_CMD`, `MONITOR_ENV_FILE`)과 임시 env 파일로 검증했고, 테스트 후 `/tmp` 임시 파일은 삭제했습니다.

| # | 항목 | 결과 | 판정 |
|---|---|---|---|
| 1 | `bash -n` (저장소·배포본, 배포본은 root로 읽어 검사) | 통과 | PASS |
| 2 | `agent-admin`(uid 1000)으로 실행, `env -i` | 설정 파일 로드, exit 1 | PASS |
| 3 | CPU/MEM/DISK 수집 | MEM 3.6% = `free -k` 3.6%, DISK 0.2% ≤ `df` Use% 1%(df는 올림), CPU 0.3% ≈ `vmstat` 0%(시점 상이, ±5pt 허용) | PASS |
| 4 | 계산 로직(고정 입력) | CPU 66.7%(ΔTotal 300, ΔIdle 100), MEM 85.0%, 임계값 경계(`>` 엄격): 60→WARNING, 66.7→OK, MEM 80→WARNING, 85→OK, DISK 임계 0→WARNING | PASS |
| 5 | Agent 부재 | 패턴 미설정 `PENDING` → exit 1 / 패턴 설정 + 프로세스 없음 `FAIL` → exit 1 | PASS |
| 6 | 15034 미리스닝 검출 | `FAIL PORT tcp/15034 not LISTEN`, `ss`로 독립 확인 | PASS |
| 7a | UFW: `agent-admin` | `UNKNOWN`(권한 부족), hint는 hint로만 표기 | PASS |
| 7b | UFW: root 실제 상태 | `ufw active` → `OK` | PASS |
| 7c | UFW 판정 로직(스텁 명령 출력) | inactive → `WARNING`, active → `OK`, ufw 없음 → `WARNING`, 예상 외 실패 → `ERROR` | PASS (로직만; **실제 UFW를 끄고 비활성 상태를 확인하지는 않음**) |
| 8 | 임계값 → WARNING | CPU/MEM/DISK 모두 확인 | PASS |
| 9 | 잘못된 설정 → exit 2 | env 파일 없음, `AGENT_PORT`=`abc`/`99999`/`0`/빈 값, `AGENT_HOME` 빈 값, 임계값 `abc`/`150`, 없는 디스크 경로, `CPU_INTERVAL=0`: 모두 exit 2 | PASS (10/10) |
| 10 | 수집 실패 → ERROR | CPU 카운터 진행 없음, meminfo 없음: `ERROR` | PASS |
| 11 | 종료 코드 우선순위 | ERROR만 → 2, FAIL+ERROR → 1, 프로세스 FAIL + 포트 LISTEN → 1, 패턴 미설정 + 포트 LISTEN → 1 | PASS |
| 12 | 실행·수정 권한 | `agent-admin` 실행 가능 / 수정·`bin/` 쓰기 불가 / `agent-dev`·`agent-test` 실행 불가 | PASS |
| 13 | 회귀 | SSH 20022(Mac 접속, `ssh b4-lab@orb`), `permitrootlogin no`, UFW 규칙 4개, 그룹 소속, 디렉터리 소유·ACL, `agent-*` sudo 없음, `/etc/default/agent-app` 644 root:root 유지 | PASS |
| 14 | 임시 파일·프로세스 정리 | 3개 디렉터리 비어 있음, `agent-*` 프로세스 0개, `/tmp` 임시 디렉터리 삭제 | PASS |
| — | 실제 Agent 프로세스 식별·정상 판정 | Agent 원본 NOT FOUND | **PENDING** |
| — | Agent의 15034 LISTEN 점검, listener PID 대조 | Agent 없음 | **PENDING** |
| — | 정상(exit 0) 전체 Health Check | Agent 없음 | **PENDING** |
| — | 실제 UFW 비활성 상태에서의 WARNING | UFW를 변경하지 않음 | **PENDING** |
| — | cron(환경 최소화·`agent-admin` 계정)에서의 실행 | cron 작업 분리 | **PENDING** |

**주의: 판정 메커니즘 검증에는 stand-in을 사용했습니다.** exit 0 경로는 `sshd` 프로세스(`/usr/sbin/sshd`)와 20022 포트를 대역으로 지정해 "프로세스 일치 + LISTEN → 0"이라는 *로직*만 확인한 것입니다. 이것은 Agent의 정상 실행이나 Boot Sequence를 의미하지 않으며 위 PENDING 항목은 그대로입니다. 가짜 Agent 프로세스·서버는 만들지 않았습니다.

테스트 중 하네스 오류 2건(0750 파일을 일반 사용자로 `bash -n`, 기대 패턴 문자열 오기)이 있었으나 스크립트 결함이 아니었고 올바른 방식으로 재확인해 PASS했습니다.

## 6. Mac 초기화 후 재설치·배포

전제: 사용자·그룹·권한(권한 설계 11장), `/etc/default/agent-app`(Agent 실행환경 4장) 구성 완료.

```bash
# 저장소 복제 후 (Mac에서)
cd Codyssey_B4-1
bash -n bin/monitor.sh

# Machine 내부 배포 (sudo 사용자). 저장소의 bin/monitor.sh를 stdin으로 전달
orb -m b4-lab bash -c '
  sudo install -d -o root -g root -m 0755 /opt/agent-app/bin &&
  sudo tee /opt/agent-app/bin/monitor.sh >/dev/null &&
  sudo chown root:agent-admin /opt/agent-app/bin/monitor.sh &&
  sudo chmod 0750 /opt/agent-app/bin/monitor.sh' < bin/monitor.sh

# 검증
orb -m b4-lab sudo cmp /opt/agent-app/bin/monitor.sh "$PWD/bin/monitor.sh" && echo IDENTICAL
orb -m b4-lab sudo -u agent-admin env -i PATH=/usr/bin:/bin /opt/agent-app/bin/monitor.sh; echo "exit=$?"
```

Agent 확보 후: `/etc/default/agent-app`에 `AGENT_PROCESS_PATTERN=<Agent 명령행 정규식>`을 추가합니다(`config/etc-default-agent-app.example`도 함께 갱신).

## 7. 남은 문제·다음 작업

1. 제공 Agent 확보 → `AGENT_PROCESS_PATTERN` 확정, 실제 프로세스·LISTEN·listener PID 검증, 정상 경로(exit 0) 실측.
2. UFW 점검 권한 방식 결정(§3): 현재 `agent-admin` 실행 시 `UNKNOWN`.
3. 임계값·로그 포맷·WARNING 시 종료 코드·종료 코드 정의를 공식 원문과 대조.
4. cron 등록(`agent-admin`, 매분) 및 cron 환경(PATH 최소)에서의 실행 검증, `monitor.log` 기록(그룹 쓰기 mode 주의: 권한 설계 11.4), 로그 순환(10MB×10)은 별도 작업.
5. `agent-admin` 소속 변경이 cron 세션에 반영되는지 실측.
