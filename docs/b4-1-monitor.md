# B4-1 monitor.sh 구현 및 1차 검증 (작업 10)

- 일시: 2026-11-13 / 기준 커밋 `dec6b17` (작업 10-1 판정 보완: 기준 `cd4606c`, §3·§4·§5.1·§6 갱신)
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
| `0` | Agent 프로세스 확인(`OK`) **그리고** `0.0.0.0:<포트>` LISTEN **그리고** 소유 PID가 Agent 프로세스와 일치(`OK`). WARNING/UNKNOWN은 있어도 0 |
| `1` | 실제 장애 또는 확인 불가: 프로세스 `FAIL`/식별 기준 미설정 `PENDING`, 포트 LISTEN 없음, 잘못된 바인딩(loopback·특정 IP), PID 불일치, 소유 PID 확인 불가 `PENDING`, IPv6 와일드카드만(IPv4 미확인) `PENDING` |
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
3. 임계값·로그 포맷·WARNING 시 종료 코드·종료 코드 정의를 공식 원문과 대조.
4. cron 등록(`agent-admin`, 매분) 및 cron 환경(PATH 최소)에서의 실행 검증, `monitor.log` 기록(그룹 쓰기 mode 주의: 권한 설계 11.4), 로그 순환(10MB×10)은 별도 작업.
5. `agent-admin` 소속 변경이 cron 세션에 반영되는지 실측.
