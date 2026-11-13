# B4-1 monitor.sh 구현 및 1차 검증 (작업 10)

> **작업 16 정정:** 그룹 소속(common = admin·dev·test, core = admin·dev), monitor.sh 소유권(agent-dev:agent-core 0750), 경고 임계값(20/10/80), `AGENT_KEY_PATH`(`/opt/agent-app/api_keys/t_secret.key`)는 공식 요구에 맞게 변경됐습니다. 이 문서의 해당 값은 당시 기록이며 현행 값은 [공식 정합성 수정](b4-1-official-alignment.md)을 따릅니다.

- 일시: 2026-11-13 / 기준 커밋 `dec6b17` (작업 10-1 판정 보완: 기준 `cd4606c`, §3·§4·§5.1·§6 갱신)
- 소스: [bin/monitor.sh](../bin/monitor.sh) (Bash 전용) → 배포: `/opt/agent-app/bin/monitor.sh`
- 범위: 점검 스크립트 구현·1차 검증. 작업 11에서 `monitor.log` 누적 기록 추가(§2.1, §5.2). **cron 등록, 로그 순환, bootstrap은 포함하지 않음**(다음 작업). 제공 Agent는 없고 대체 구현도 하지 않음.
- 값의 구분: **[설계 기본값]** 이 작업에서 정한 임시값(공식 요구 아님) / **[원문 미확인]** / **[실측]**.

## 1. 배포 위치·권한 (설계 결정, 원문 미확인)

| 경로 | 소유자:그룹 | mode | 이유 |
|---|---|---|---|
| `/opt/agent-app/bin` | `root:root` | `0755` | 기존 `/opt/agent-app`(root:root 755)과 동일. 일반 계정이 스크립트를 바꿔치기할 수 없음 |
| `/opt/agent-app/bin/monitor.sh` | `agent-dev:agent-core` | `0750` | (작업 16 정정, 이전 `root:agent-admin`) cron 계정 `agent-admin`이 `agent-core` 그룹 r-x로 실행, 소유자 `agent-dev`만 수정. 그 외 일반 계정은 실행·열람 불가 |

기존 권한 설계(작업 7~8)의 `upload_files`/`api_keys`/로그 디렉터리와 충돌하지 않으며 ACL은 추가하지 않았습니다. 소유자·mode의 공식 정책이 확인되면 조정합니다. [실측] `agent-admin` 실행 가능, `agent-dev`/`agent-test` 실행 `Permission denied`, `agent-admin`의 스크립트 수정·`bin/` 쓰기 불가.

## 2. 실행 방법

```bash
sudo -u agent-admin env -i PATH=/usr/bin:/bin /opt/agent-app/bin/monitor.sh; echo "exit=$?"
```

- `/etc/default/agent-app`을 **스크립트가 직접 `source`** 합니다(`MONITOR_ENV_FILE`로 다른 파일 지정 가능). 로그인 셸·`.bashrc`에 의존하지 않으므로 `env -i`에서도 동작합니다.
- 필수 변수: `AGENT_HOME`, `AGENT_PORT`(정수 1~65535), `AGENT_UPLOAD_DIR`, `AGENT_LOG_DIR`. 하나라도 없거나 잘못되면 점검 없이 종료 코드 2.
- `AGENT_KEY_PATH`는 비어 있어도 됩니다(모니터링에 불필요, 안내 메시지만 출력).
- 출력은 **stdout과 `$AGENT_LOG_DIR/monitor.log` 양쪽**에 동일한 텍스트로 나갑니다(작업 11, §2.1). 라인 형식은 `YYYY-MM-DD HH:MM:SS [LEVEL] CATEGORY message`이며 **로그 포맷의 공식 지정은 [원문 미확인]** 이라 임시 형식입니다.

### 2.1 monitor.log 누적 기록 (작업 11)

| 항목 | 내용 |
|---|---|
| 경로 | `$AGENT_LOG_DIR/monitor.log` = `/var/log/agent-app/monitor.log`. 테스트용 재정의 `MONITOR_LOG_FILE` |
| 기록 주체 | **스크립트 자신**이 파일 디스크립터(fd 9, append 모드)로 기록. cron 출력 리디렉션에 의존하지 않음 |
| 내용 | stdout에 나간 모든 줄(START~SUMMARY)과 **동일한 텍스트**. SUMMARY에 `log=<경로>`/`FAILED`/`disabled` 필드 추가 |
| 덮어쓰기 | 없음. `>>`(append)로만 열며 truncate·초기화 코드 없음. 기존 로그의 앞부분은 실행 전후로 바이트 단위 동일함을 검증 |
| 생성 | 파일이 없으면 열면서 생성(`umask 007`; 디렉터리 default ACL이 있으면 ACL 기준으로 `rw-rw----`). 심볼릭 링크 경로와 일반 파일이 아닌 경로는 거부 |
| 권한(적용) | `-rw-rw---- agent-admin:agent-core` (0660), ACL 엔트리 없음(`group::rw-`, `other::---`). 소유자 `agent-admin`은 설계 결정이며 원문 미확인 |
| 형식 | **임시 설계 형식**, 공식 로그 포맷은 [원문 미확인] — 대조 필요 |
| START 필드(작업 13) | `groups=`(프로세스의 실효 보조 그룹), `trigger=`(`MONITOR_TRIGGER` 값, 기본 `manual`, cron은 `cron`; 영숫자·`_`·`-`, 16자로 제한). 판정 로직은 변경 없음 |
| 비밀 | 고정 필드만 출력. `AGENT_KEY_PATH`가 설정돼 있어도 값은 출력·기록하지 않고 "설정됨(값은 기록하지 않음)"만 남김. 환경변수 전체를 덤프하지 않음 |
| 로그 쓰기 실패 | `ERROR LOG`로 감지(열기 실패, 심볼릭 링크, 비일반 파일, 실행 중 쓰기 실패). 점검·화면 출력은 끝까지 수행하고 SUMMARY에 `log=FAILED`·`error≥1`. 종료 코드는 §4(장애가 있으면 1 우선, 그 외 2) |
| 로그 경로를 알 수 없음 | env 파일을 읽을 수 없거나 `AGENT_LOG_DIR`이 비어 있으면 로그 비활성(`log=disabled`), 설정 오류이므로 exit 2 |

env 파일을 읽기 전에 발생한 줄(START 등)은 메모리에 보관했다가 로그를 연 뒤 기록하므로 로그에도 START부터 남습니다. 동시에 여러 번 실행돼도 줄 단위 append라 줄이 섞이거나 깨지지 않습니다(§5.2).

### 실제 출력 (agent-admin, env -i, 2026-11-13)

```
[INFO] START user=agent-admin uid=1000 groups=agent-admin,agent-common,agent-core trigger=manual host=b4-lab env_file=/etc/default/agent-app
[INFO] CONFIG AGENT_HOME=/opt/agent-app AGENT_PORT=15034 AGENT_UPLOAD_DIR=/opt/agent-app/upload_files AGENT_LOG_DIR=/var/log/agent-app
[INFO] CONFIG AGENT_KEY_PATH is empty ; not needed for monitoring, continuing
[PENDING] PROCESS agent identification criteria not configured (AGENT_PROCESS_PATTERN unset); not assuming any python process is the Agent
[FAIL] PORT tcp/15034 not LISTEN
[UNKNOWN] FIREWALL cannot read ufw status as uid=1000 (needs root; no sudo granted). hint only: ufw.conf ENABLED=yes
[OK] CPU usage=0.2% (threshold 80%)
[OK] MEM usage=3.6% (total=16434648kB available=15840160kB) (threshold 80%)
[OK] DISK usage=0.2% path=/ mount=/ (threshold 80%)
[INFO] SUMMARY result=UNHEALTHY exit=1 fail=1 pending=1 warning=0 unknown=1 error=0
exit=1
```
(각 라인 앞의 타임스탬프는 생략)

## 3. 점검 항목과 판정

| 항목 | 방법 | 판정 |
|---|---|---|
| **A. Agent 프로세스** | `pgrep -f "$AGENT_PROCESS_PATTERN"`(확장 정규식, 자신·부모 PID 제외). 패턴은 **Agent 확보 후 `/etc/default/agent-app` 등에서 설정**. 임의의 python 프로세스를 Agent로 보지 않음 | 패턴 미설정 → `PENDING`(정상 아님, exit 1) / 패턴 불일치 → `FAIL` / 일치 → `OK` |
| **B. TCP 포트** | `ss -H -ltnp`에서 `AGENT_PORT`의 실제 LISTEN 소켓을 확인(UFW 허용 규칙은 보지 않음). 바인딩 주소와 소유 PID를 **둘 다** 판정(§3.1) | LISTEN 없음 → `FAIL` / 잘못된 바인딩 → `FAIL` / 확인 불가 → `PENDING` / 바인딩·소유자 확인 → `OK` |
| **C. UFW** | `ufw status` 출력의 `Status:` 행. `ufw.service`/`ufw.conf`는 판정에 쓰지 않고 hint로만 표기 | `active` → `OK` / `inactive` → `WARNING` / 권한 부족 → `UNKNOWN` / ufw 없음 → `WARNING` / 그 외 실패 → `ERROR` |
| **D. CPU** | `/proc/stat` 집계 `cpu` 행을 1초 간격(`MONITOR_CPU_INTERVAL`)으로 2회 읽어 `100×(ΔTotal−ΔIdle)/ΔTotal`. Total = user+nice+system+idle+iowait+irq+softirq+steal, Idle = idle+iowait | 임계값 **초과**(`>`) → `WARNING` |
| **D. MEM** | `/proc/meminfo`: `100×(MemTotal−MemAvailable)/MemTotal` | 동일 |
| **D. DISK** | `df -Pk $MONITOR_DISK_PATH`(기본 `/`): `100×used/(used+avail)` (df의 `Use%`와 같은 기준, 반올림 없음) | 동일 |

### 3.1 포트 판정 규칙 (작업 10-1)

**바인딩** — 요구 형태는 `0.0.0.0:<포트>`(IPv4 전체) 입니다.

| `ss` 로컬 주소 | 분류 | 판정 |
|---|---|---|
| `0.0.0.0:P` | IPv4 전체 | 충족 |
| `127.x.x.x:P`, `[::1]:P` | localhost 전용 | `FAIL` (다른 호스트에서 접근 불가) |
| `192.168.x.x:P` 등 특정 IP | 일부 인터페이스만 | `FAIL` |
| `[::]:P`, `*:P` | IPv6(또는 dual-stack) 와일드카드 | **`PENDING`** — IPv4 접근 가능 여부는 소켓의 `IPV6_V6ONLY` 설정에 달려 있고 `ss`로는 알 수 없음. `0.0.0.0`과 동등하게 취급하지 않음 |

`0.0.0.0` 리스너가 있으면 충족이며, 동일 포트의 loopback 등 추가 소켓이 같은 PID 소유이면 허용합니다. `127.0.0.53%lo`처럼 `%인터페이스` 접미사는 제거하고 분류합니다. 포트 매칭은 `:P`로 끝나는 주소만 인정(`:115034`, `:150340` 무시).

**소유 PID** — Agent 프로세스가 `OK`로 확인된 경우에만 평가합니다.

| 상황 | 판정 |
|---|---|
| 포트를 쥔 PID가 모두 보이고 전부 Agent PID와 일치 | `OK` |
| 보이는 PID 중 Agent PID가 아닌 것이 하나라도 있음(불일치, 다중 PID, 다른 프로세스가 같은 포트를 추가 점유) | `FAIL` — "포트가 열려 있으니 정상"으로 판정하지 않음 |
| 소켓의 PID가 이 uid에게 보이지 않음(`ss -p`는 자신의 프로세스·root에게만 PID 표시) | **`PENDING`** — "확인 불가"를 "확인 완료"로 표시하지 않음. 일부 소켓만 안 보여도 보수적으로 `PENDING` |
| Agent 프로세스 미확인(`PENDING`/`FAIL`) | 소유자는 "미평가"로 표기하고 LISTEN 사실만 보고 |

따라서 **exit 0은 "프로세스 확인 + `0.0.0.0` 바인딩 + 소유 PID 일치 확인"이 모두 충족될 때만** 나옵니다. Agent를 다른 사용자로 실행하면 `agent-admin`은 PID를 볼 수 없어 항상 `PENDING`이므로, Agent 실행 계정과 모니터 실행 계정의 관계를 Agent 확보 후 정해야 합니다(같은 계정으로 실행하거나, `ss`를 읽을 권한 설계).

임계값(공식 요구값, 작업 16에서 수정; 이전 설계 기본값은 80/80/80): `MONITOR_CPU_WARN=20`, `MONITOR_MEM_WARN=10`, `MONITOR_DISK_WARN=80`(%). 값이 임계값과 정확히 같으면 경고하지 않음(`>`). 환경변수 또는 env 파일로 변경 가능. 수치 수집이 실패하면 `ERROR`(값을 추정하지 않음).

### UFW 점검 권한 제약

`ufw status`는 root 권한이 필요합니다. `agent-admin`에게는 sudo를 주지 않았으므로(요구 없음) **cron으로 `agent-admin`이 실행하면 방화벽 상태는 항상 `UNKNOWN`** 입니다. 이를 `OK`로 처리하지 않습니다. 선택지(다음 작업에서 결정):
1. `UNKNOWN`을 그대로 수용(현재 동작).
2. `/etc/sudoers.d/`에 `ufw status` 한 가지 명령만 NOPASSWD 허용(권한 추가이므로 승인 필요).
3. root cron(`agent-admin` crontab 요구와 충돌 가능, 원문 확인 필요).

root로 실행하면 실제 상태를 판정합니다([실측] `ufw active` → `OK`).

## 4. 종료 코드 (설계 정의, 공식 정의는 [원문 미확인])

| 코드 | 의미 |
|---|---|
| `0` | Agent 프로세스 확인(`OK`) **그리고** `0.0.0.0:<포트>` LISTEN **그리고** 소유 PID가 Agent 프로세스와 일치(`OK`). WARNING/UNKNOWN은 있어도 0 |
| `1` | 실제 장애 또는 확인 불가: 프로세스 `FAIL`/식별 기준 미설정 `PENDING`, 포트 LISTEN 없음, 잘못된 바인딩(loopback·특정 IP), PID 불일치, 소유 PID 확인 불가 `PENDING`, IPv6 와일드카드만(IPv4 미확인) `PENDING` |
| `2` | 모니터링 자체의 오류만 있는 경우: 설정 오류(env 파일 없음, 잘못된 포트·임계값), 필수 명령 없음, 수치 수집 실패, `ufw status` 예상 외 실패, **로그 열기/쓰기 실패** |

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

### 5.1 판정 보완 테스트 (작업 10-1) [실측]

실제 Agent 대용 서버·프로세스는 만들지 않았습니다. 포트·PID 판정은 `ss -H -ltnp` 형식의 **입력 파일**(`MONITOR_SS_FILE` 테스트 훅)로, 프로세스는 실제 `sshd` 마스터(`/usr/sbin/sshd`, stand-in이며 Agent 아님)로 격리 검증했습니다. 소유 PID 필드는 stand-in의 실제 PID로 구성했습니다. 전체 **42건 PASS / 0 FAIL**.

| 상황 | 기대 | 결과 |
|---|---|---|
| 프로세스 PID = 포트 PID (`0.0.0.0`) | `OK`, exit 0 (로직 전용) | PASS |
| IPv4 + IPv6 소켓 모두 가시·일치 | exit 0 | PASS |
| 두 PID 불일치 (`pid=1`) | `FAIL`, exit 1 | PASS |
| 다중 PID 중 비-Agent PID 포함 | `FAIL` | PASS |
| 같은 포트를 다른 PID가 추가 점유 | `FAIL` | PASS |
| 포트 PID 확인 불가(`users:` 없음) | `PENDING`, exit 1, `OK`로 표시 안 됨 | PASS |
| 소켓 일부만 PID 비가시 | `PENDING`(보수적) | PASS |
| `127.0.0.1` 전용 / `[::1]` 전용 / 특정 IP 전용 | `FAIL` | PASS ×3 |
| `[::]`만 / `*`만 | `PENDING`("IPv4 도달 미확인") | PASS ×2 |
| loopback v4 + `[::]`(0.0.0.0 없음) | `PENDING` | PASS |
| `0.0.0.0` + 동일 PID loopback 추가 | exit 0 | PASS |
| `127.0.0.53%lo` 스코프 주소 | loopback 인식 | PASS |
| 15034 미LISTEN(유사 포트 `115034`/`150340` 존재, 빈 출력, 실제 `ss`) | `FAIL`, exit 1 | PASS ×3 (독립 `ss` 확인 포함) |
| Agent 식별 기준 미설정 + 포트 정상 | `PENDING` exit 1, 포트 소유자 "미평가" | PASS |
| 패턴 설정 + 프로세스 없음 / 실환경 기본 | `FAIL` / `PENDING`+포트 `FAIL`, exit 1 | PASS ×2 |
| 설정 오류(env 파일 없음, 포트 `abc`/`99999`, `AGENT_HOME` 빈 값, `MEM_WARN=150`, 잘못된 디스크 경로) | exit 2 | PASS ×6 |
| 확인된 정상 + 수집 실패(ERROR) | exit 2 / PID 불일치와 겹치면 exit 1 우선 | PASS ×2 |
| 확인된 정상 + UFW inactive·DISK WARNING | WARNING만, exit 0 | PASS |
| 실제 `ss` 파싱: `agent-admin`이 root 소유 sshd(20022) 확인 | PID 비가시 → `PENDING`, exit 1 | PASS |
| 실제 `ss` 파싱: root가 같은 sshd 확인(stand-in) | PID 가시·일치 → exit 0 (메커니즘) | PASS |
| 권한(`agent-dev`/`agent-test` 실행 불가, `agent-admin` 수정 불가) / 정리 | | PASS |

**기존 스위트(작업 10) 재실행: 40 PASS / 3 FAIL, 모두 해석됨.** ① `process PENDING`은 이전과 동일한 **테스트 하네스의 기대 패턴 오기**(`PENDING PROCESS` ≠ 실제 `[PENDING] PROCESS`, 스크립트 정상)이며 이번 스위트에서 올바른 패턴으로 PASS. ②③ 작업 10의 "stand-in(sshd) → exit 0/2" 두 항목은 **의도된 동작 변경**입니다. 이제 `agent-admin`은 root 소유 sshd의 PID를 볼 수 없어 `PENDING`(exit 1)이 되며(작업 10의 판정은 이 경우를 `OK`로 표시했음 — 이것이 이번에 고친 "잘못된 정상 판정" 가능성), 동일 경로는 위 fixture·root 테스트로 대체되었습니다.

**여전히 PENDING(실제 Agent 필요):** 실제 Agent 프로세스 식별·`AGENT_PROCESS_PATTERN` 확정, Agent의 실제 `0.0.0.0:15034` 바인딩·소유 PID 일치, 실제 정상(exit 0) Health Check, Agent 실행 계정과 모니터 실행 계정 간 PID 가시성, 실제 UFW 비활성 상태의 WARNING, cron 환경 실행. `[::]` 와일드카드가 IPv4로 도달 가능한지는 실제 Agent 소켓에서 확인해야 합니다.

### 5.2 monitor.log 기록 테스트 (작업 11) [실측]

판정 로직은 그대로이며 로그 기록만 추가했습니다. "정상" 경로가 필요한 로그 실패 테스트는 §5.1의 입력 파일(`MONITOR_SS_FILE`)과 stand-in `sshd` PID를 사용한 로직 전용 입력입니다(Agent 아님, 가짜 Agent·서버 없음).

| # | 항목 | 결과 | 판정 |
|---|---|---|---|
| 1 | `bash -n`(저장소·배포본), 배포본 == 저장소 | 통과, 동일 | PASS |
| 2 | 로그 생성·권한 | 실제 `/var/log/agent-app/monitor.log`가 없어서 `install -o agent-admin -g agent-core -m 0660`으로 생성(기존 로그가 있으면 건드리지 않는 조건부 절차). `-rw-rw---- agent-admin:agent-core`, `other::---` | PASS |
| 3 | `agent-admin` 연속 3회 실행 | 매회 exit 1, 매회 정확히 10줄 추가(총 30줄), 직전 로그 prefix 바이트 단위 동일(sha256), 각 회차 터미널 출력 = 로그에 추가된 10줄(`diff` 일치) | PASS (3×3) |
| 4 | 타임스탬프·SUMMARY | 3개 SUMMARY가 모두 `exit=1`, `log=/var/log/agent-app/monitor.log`, 타임스탬프 서로 다르고 오름차순, 모든 줄이 `YYYY-MM-DD HH:MM:SS [LEVEL]`로 시작 | PASS |
| 5 | 장애 기록 | `[PENDING] PROCESS`(식별 기준 미설정), `[FAIL] PORT tcp/15034 not LISTEN`이 로그에 기록. 종료 코드 1 유지 | PASS |
| 6 | 접근 차단 | 로그 파일 존재 확인 후 `agent-dev`·`agent-test`: 읽기·쓰기·디렉터리 목록 모두 거부. `agent-admin` 읽기 가능 | PASS |
| 7 | 기존 로그 보존 | 센티널 2줄이 든 임시 로그에 실행 → 센티널이 맨 앞에 그대로, 실행 결과가 뒤에 추가 | PASS |
| 8 | 자동 생성(실제 로그 디렉터리, 별도 파일명) | 소유 `agent-admin`, 그룹 `agent-core`(setgid 상속), `-rw-rw----`, mask `rw-`(default ACL 적용) → 검증 후 테스트 파일 삭제 | PASS |
| 9 | 로그 쓰기 실패 | ① 로그 디렉터리 없음 + Agent 부재 → `ERROR LOG`, **exit 1 우선**, `log=FAILED` ② 같은 실패 + 정상(로직 전용) → exit 2 `MONITOR_ERROR`(대조군: 쓰기 가능 로그면 exit 0) ③ 읽기 전용 로그 → exit 2, 파일 불변 ④ 심볼릭 링크 → 거부·exit 2·대상 불변 ⑤ 디렉터리 경로 → 거부·exit 2 ⑥ 실행 중 쓰기 실패(`/dev/full`, ENOSPC) → `ERROR LOG write … failed`, 점검 출력은 끝까지 유지, exit 2 ⑦ 같은 실패 + Agent 부재 → exit 1 | PASS (8) |
| 10 | 로그 비활성 | `AGENT_LOG_DIR` 빈 값 / env 파일 없음 → exit 2, `log=disabled` | PASS (2) |
| 11 | 비밀정보 | 센티널 값(`AGENT_KEY_PATH`·`AGENT_API_KEY`·`AGENT_PASSWORD`)을 env에 넣고 실행 → stdout·로그에 센티널 없음(로그를 `sudo`로 읽어 검증), "값은 기록하지 않음" 문구만 기록. 실제 `monitor.log`에도 비밀형 문자열 없음(`key`가 들어간 줄은 "AGENT_KEY_PATH is empty" 안내뿐) | PASS |
| 12 | 동시 실행 6개 | 줄 수 합(60) = 로그 줄 수, 깨진 줄 없음, SUMMARY 6개 | PASS |
| 13 | 회귀: 판정 로직 | 작업 10-1 스위트 재실행 **42 PASS / 0 FAIL**. 작업 10 스위트 40 PASS / 3 FAIL — 3건은 작업 10-1에서 이미 설명한 것과 동일(하네스 패턴 오기 1건 + 판정 강화에 따른 의도된 변경 2건), 이번 변경과 무관 | PASS |
| 14 | 회귀: 환경 | SSH 20022(Mac 접속·`ssh b4-lab@orb`), `permitrootlogin no`, UFW active·규칙 유지, 그룹 소속, 디렉터리 소유·mode·ACL(`/var/log/agent-app`의 `group:agent-core:rwx`·default 포함), `agent-*` sudo 없음, `/etc/default/agent-app` 644 유지 | PASS |
| 15 | 정리 | 임시 파일·`agent-*` 프로세스 0개, 회귀 스위트는 임시 로그로 우회해 실제 로그 오염 없음(전후 40줄) | PASS |

**테스트 하네스 오류(스크립트 결함 아님) 2건:** ① `sudo wc -l < $LOG`의 리다이렉션을 일반 사용자 셸이 열어 읽기 실패(줄 수 비교가 공란) ② `agent-admin` 소유 0660 임시 로그를 `sudo` 없이 `grep`해 읽기 자체가 실패 — 이 때문에 "센티널 없음" 검사가 **읽기 실패로 우연히 참**이 되어 첫 결과는 유효하지 않았습니다. 두 항목은 `sudo`로 읽도록 고쳐 다시 실행했고(대조: 로그가 비어 있지 않음을 먼저 확인) 위 표는 재실행 결과입니다.

**실제 `monitor.log` 현재 상태:** 이 검증으로 생성된 4회분(40줄, Agent 부재 상황의 `exit=1` 기록)이 들어 있습니다. 새 파일이었으므로 덮어쓴 기존 내용은 없으며, 삭제·초기화하지 않았습니다. cron이 이어서 누적합니다.

**PENDING:** 실제 Agent가 있는 정상(exit 0) 기록, cron 환경(최소 PATH, `agent-admin` crontab)에서의 기록과 그룹 소속 반영, 로그 순환(10MB×10)과 순환 후 파일 mode, 디스크 부족 등 실환경의 쓰기 실패, 공식 로그 포맷 대조.

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

# 로그 파일: 없을 때만 생성 (기존 로그는 건드리지 않음). 스크립트가 없으면 자동 생성도 하지만 소유자를 고정하려면 사전 생성
orb -m b4-lab bash -c 'sudo test -e /var/log/agent-app/monitor.log || sudo install -o agent-admin -g agent-core -m 0660 /dev/null /var/log/agent-app/monitor.log'
# 검증 1: 배포본 == 저장소 파일 (Machine의 파일을 stdout으로 받아 Mac에서 비교)
orb -m b4-lab sudo cat /opt/agent-app/bin/monitor.sh | cmp - bin/monitor.sh && echo IDENTICAL
# 보조: SHA-256 (두 값이 같아야 함)
shasum -a 256 bin/monitor.sh
orb -m b4-lab sudo sha256sum /opt/agent-app/bin/monitor.sh
# 검증 2: 실행
orb -m b4-lab sudo -u agent-admin env -i PATH=/usr/bin:/bin /opt/agent-app/bin/monitor.sh; echo "exit=$?"
```

비교 명령 메모(작업 10-1): 작업 10의 `orb -m b4-lab sudo cmp /opt/agent-app/bin/monitor.sh "$PWD/bin/monitor.sh"`는 OrbStack이 Mac 홈 디렉터리를 Machine의 같은 경로로 공유한다는 **환경 의존**이 있어 저장소가 공유 경로 밖에 있으면 동작하지 않습니다(이때 `cmp`는 오류 종료 코드를 내므로 오탐 `IDENTICAL`은 나오지 않음). 위 스트림 방식은 공유 마운트에 의존하지 않습니다. [실측] 동일 파일 `IDENTICAL`, SHA-256 일치(`c2960192…bb8`, 작업 10-1 배포본), 내용을 1줄 바꾼 대조군은 `cmp`가 비정상 종료. 배포본은 `0750 root:agent-admin`이라 `sudo`가 필요합니다.

Agent 확보 후: `/etc/default/agent-app`에 `AGENT_PROCESS_PATTERN=<Agent 명령행 정규식>`을 추가합니다(`config/etc-default-agent-app.example`도 함께 갱신).

## 7. 남은 문제·다음 작업

1. 제공 Agent 확보 → `AGENT_PROCESS_PATTERN` 확정, 실제 프로세스·LISTEN·listener PID 검증, 정상 경로(exit 0) 실측. Agent 실행 계정이 `agent-admin`이 아니면 PID가 보이지 않아 `PENDING`이 되므로 계정 관계를 정할 것.
2. UFW 점검 권한 방식 결정(§3): 현재 `agent-admin` 실행 시 `UNKNOWN`.
3. 임계값·**로그 포맷**·WARNING 시 종료 코드·종료 코드 정의를 공식 원문과 대조(현재 모두 임시 설계).
4. cron 등록(작업 13)과 로그 순환(작업 12)은 완료됐고 `create 0660 agent-admin agent-core`로 `monitor.log`의 소유자·그룹·mode가 유지됨을 검증했습니다([cron 기록](b4-1-cron.md), [로그 순환 기록](b4-1-log-rotation.md)). 남은 것은 실제 `logrotate.timer` 발동 확인(PENDING)입니다.
5. (해결) `agent-admin` 소속 변경이 cron 세션에 반영됨 — 작업 13에서 cron 프로세스의 `groups=agent-admin,agent-common,agent-core`로 실측([cron 기록](b4-1-cron.md)).
