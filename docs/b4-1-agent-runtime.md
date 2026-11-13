# B4-1 Agent 실행환경 준비 (작업 9)

> **작업 18 현황(최신):** 제공 Agent는 확보·실행 검증 완료(Boot 5/5, `Agent READY`, 0.0.0.0:15034). `AGENT_PROCESS_PATTERN=^/opt/agent-app/bin/agent-app-linux-x86` 설정으로 Agent 실행 중 `monitor.sh`는 `HEALTHY exit 0`, 중지 시 `exit 1`. `monitor.log`는 **공식 형식 1줄/실행**(`[시각] PID:… CPU:…% MEM:…% DISK_USED:…%`)이며 상세 Health Check는 콘솔에만 출력. 과거 상세 로그(10줄/실행)는 그대로 남아 있어 한 파일에 두 형식이 공존. 아래 본문 중 "Agent NOT FOUND / `AGENT_KEY_PATH` PENDING / 임시 로그 형식"은 당시 기록이며 [Agent 실행 기록](b4-1-agent-runtime.md#작업-18-agent-정상-모니터링공식-로그-형식)이 우선합니다.


> **작업 16 정정:** 그룹 소속(common = admin·dev·test, core = admin·dev), monitor.sh 소유권(agent-dev:agent-core 0750), 경고 임계값(20/10/80), `AGENT_KEY_PATH`(`/opt/agent-app/api_keys/t_secret.key`)는 공식 요구에 맞게 변경됐습니다. 이 문서의 해당 값은 당시 기록이며 현행 값은 [공식 정합성 수정](b4-1-official-alignment.md)을 따릅니다.

- 일시: 2026-11-13 / 기준 커밋 `86678af`
- 범위: 환경변수 파일 적용·검증, 제공 Agent 존재 확인. SSH·UFW·그룹 소속·기존 ACL 변경 없음. `monitor.sh`·cron·logrotate·bootstrap 미구현.
- 값의 구분: **[원문]** 공식 원문 확인(현재 없음) / **[Notion 요약]** 변수 이름 5개(원문 미대조) / **[승인된 실습 설계]** 사용자 승인값, 원문 미대조 / **[적용됨]** Ubuntu에 반영 / **[실측]** 테스트 결과.

## 1. 제공 Agent 원본: NOT FOUND

| 확인 위치 | 결과 |
|---|---|
| 저장소 (`git ls-files`) | 문서·README만 존재, Agent 파일 없음 |
| Mac `~/Downloads`, `~/Desktop`, `~/Documents`, `~/Codyssey_B4-2`(빈 디렉터리), 홈 하위 5단계 이름 검색(`agent_app*`, `agent.py` 등) | 없음 (ChatGPT/Claude `.dmg`, 스크린샷만 존재) |
| Machine `b4-lab` 전체(`find / -xdev`: `*agent*app*`, `agent*.py/.zip/.tar*`, `*.pyz`) | `/opt/agent-app`, `/var/log/agent-app`(작업 8에서 만든 디렉터리)만 검색됨 |
| Notion | Boot Sequence·`AGENT_KEY_PATH` 요건 상세 없음. B4-2 페이지에 "제공 agent-leak-app" 이름만 언급 |

임의의 Agent나 모의 서버는 만들지 않았습니다. 따라서 **Agent 실행(`Agent READY`, `0.0.0.0:15034` LISTEN 검증)은 보류(NOT RUN)** 입니다. 실행 안내·Python 버전·아키텍처·필수 라이브러리·실행 계정·Boot Sequence 조건은 모두 미확인입니다.

## 2. 환경변수 구성

설정 파일: `/etc/default/agent-app` — `root:root`, `0644`(`-rw-r--r--`), ACL 없음. 비밀값 없음. 작업 전 해당 파일은 존재하지 않았습니다(덮어쓴 것 없음).

| 변수 | 값 | 출처·확정 여부 | 상태 |
|---|---|---|---|
| `AGENT_HOME` | `/opt/agent-app` | 변수 이름: [Notion 요약] / 값: [승인된 실습 설계], 원문 확인 필요 | 적용 |
| `AGENT_PORT` | `15034` | [관리자료](README, UFW 허용 포트와 일치) / 변수 이름·값 원문 확인 필요 | 적용 |
| `AGENT_UPLOAD_DIR` | `/opt/agent-app/upload_files` | [승인된 실습 설계] | 적용 |
| `AGENT_LOG_DIR` | `/var/log/agent-app` | 경로: README·Notion 일치(원문 미대조) | 적용 |
| `AGENT_KEY_PATH` | *(빈 값)* | 파일/디렉터리 여부 미확인 | **PENDING** |

- `AGENT_KEY_PATH=`는 "정의했지만 비어 있음"입니다. 이 값은 api_keys 디렉터리 경로(`/opt/agent-app/api_keys`)일 수도, 그 아래 특정 키 파일일 수도 있어 **추측하지 않았습니다.** 제공 Agent가 요구하는 형태를 확인한 뒤 채웁니다(디렉터리 안에 파일을 만들 때도 실제 키는 임의 생성하지 않음).
- 파일 형식은 `KEY=VALUE`(따옴표·`export` 없음)로, bash `source`와 systemd `EnvironmentFile=` 양쪽에서 같은 결과를 냅니다.
- 로그인 셸 설정(`~/.bashrc`, `/etc/profile.d`)에는 **의존하지 않습니다.** cron과 systemd는 로그인 환경을 상속하지 않으므로, 사용하는 스크립트가 아래 방식으로 명시 로드해야 합니다.

```bash
set -a; . /etc/default/agent-app; set +a
```

저장소 예제: [config/etc-default-agent-app.example](../config/etc-default-agent-app.example) (비밀값 없음, 실제 파일과 동일한 내용).

## 3. 검증 결과 [실측]

방법: `sudo -u agent-admin env -i PATH=/usr/bin:/bin bash -c '…'`로 로그인 환경이 전혀 없는 새 프로세스에서 수행.

| # | 항목 | 결과 | 판정 |
|---|---|---|---|
| 1 | 설정 파일 로드(구문, 로드) | `bash -n` OK, 로드 후 `AGENT_*` 5개 정의 | PASS |
| 2 | `agent-admin` 새 프로세스의 값(`env -i` + 명시 로드) | 5개 값이 설정과 일치, `AGENT_KEY_PATH`는 정의됨·빈 값 | PASS |
| 3 | 로드하지 않은 환경 | `sudo -iu agent-admin` 로그인 셸, `env -i`, cron 유사 `sh -c` 모두 `AGENT_*` 0개 → 로그인 셸에 의존하지 않으며 **명시 로드가 필수**임을 확인 | PASS |
| 4 | 디렉터리 존재 | `AGENT_HOME`, `AGENT_UPLOAD_DIR`, `AGENT_LOG_DIR` 모두 존재, `AGENT_HOME` 통과 가능 | PASS |
| 5 | 값 ↔ 실제 디렉터리 일치, 쓰기 | 작업 8 구성(`root:root 755`, `agent-admin:agent-common 2770`, `root:agent-core 2770`)과 일치. `agent-admin`이 업로드·로그 디렉터리에 쓰기·읽기·삭제 성공(권한·ACL 유지) | PASS |
| 6 | `AGENT_PORT` 값 | 숫자 1~65535, UFW 허용 포트(15034)와 일치 | PASS |
| 7 | systemd `EnvironmentFile` 호환 | `systemd-run -P -p User=agent-admin -p EnvironmentFile=…`으로 5개 값 동일 확인 | PASS |
| 8 | 다른 계정의 파일 읽기 | `agent-dev`, `agent-test` 모두 읽기 가능(비밀 없는 0644이므로 의도됨) | PASS |
| 9 | 비밀값 없음 | 파일 내 비밀 형태 값 없음 | PASS |
| 10 | `AGENT_KEY_PATH` 값 확정 | 빈 값 | **PENDING** |
| 11 | 환경변수를 실제 Agent가 사용하는 테스트 | Agent 없음 | **PENDING (NOT RUN)** |
| 12 | Agent 기동(`Agent READY`, `0.0.0.0:15034` LISTEN), Boot Sequence 5단계 | Agent 없음, 15034는 현재 LISTEN 없음 | **PENDING (NOT RUN)** |

위 PASS는 "환경변수 파일이 올바르게 정의·로드되고 경로·권한과 일치한다"까지만 의미합니다. Agent가 이 값을 실제로 사용해 기동하는지는 검증되지 않았습니다.

### 회귀 [실측]

| 항목 | 결과 | 판정 |
|---|---|---|
| SSH | `port 20022`, `permitrootlogin no`, Mac → 20022 접속 성공, `ssh b4-lab@orb` 성공 | PASS |
| UFW | active, deny(in)/allow(out), 20022·15034 허용 4개 유지 | PASS |
| 그룹 소속 | admin ∈ common+core, dev ∈ common, test 미가입 (변경 없음) | PASS |
| 디렉터리 권한·ACL | 소유자·mode·`group:agent-core:rwx`/mask/other 유지 | PASS |
| 정리 | 테스트 파일 0개(3개 디렉터리 모두 비어 있음), `agent-*` 프로세스 0개 | PASS |

## 4. 초기화 후 재현 명령 (검증된 절차)

사용자·그룹(12장), 그룹 소속·디렉터리(권한 설계 11장) 적용 후:

```bash
sudo tee /etc/default/agent-app >/dev/null <<'EOT'
AGENT_HOME=/opt/agent-app
AGENT_PORT=15034
AGENT_UPLOAD_DIR=/opt/agent-app/upload_files
AGENT_LOG_DIR=/var/log/agent-app
AGENT_KEY_PATH=
EOT
sudo chown root:root /etc/default/agent-app
sudo chmod 0644 /etc/default/agent-app
bash -n /etc/default/agent-app

# 검증
sudo -u agent-admin env -i PATH=/usr/bin:/bin bash -c 'set -a; . /etc/default/agent-app; set +a; env | grep ^AGENT_ | sort'
```

(저장소의 예제 파일을 `sudo install -m 0644 -o root -g root config/etc-default-agent-app.example /etc/default/agent-app`로 설치해도 같습니다.)

## 5. 미완료·재확인 항목

1. **제공 Agent 확보**(최우선): 파일 경로·종류, Python 버전·아키텍처, 필수 라이브러리, 실행 명령·실행 계정, Boot Sequence 5단계 조건, 포트 바인딩 방식(`0.0.0.0:15034`).
2. `AGENT_KEY_PATH`가 파일인지 디렉터리인지, 값과 위치 확정. 값이 api_keys 하위 파일이면 접근 계정(현재 `agent-core` 소속인 `agent-admin`만)도 재확인.
3. Agent 실행 계정과 그 계정의 그룹 소속(현재 `agent-dev`는 core 비소속).
4. 5개 변수의 이름·값·경로를 공식 원문과 대조(현재 [Notion 요약]·[승인된 실습 설계]).
5. cron/`monitor.sh`에서 위 명시 로드 방식이 실제로 동작하는지는 해당 작업에서 실측.
6. 변수를 Agent에 전달하는 방식(systemd 서비스 `EnvironmentFile=` 또는 실행 스크립트의 `source`)은 Agent 확인 후 결정.

---

# 작업 17: 제공 Agent 실행 및 Boot Sequence 검증

기준 SHA `338ffe7`. 검증 순서: `b4-recovery-test` → PASS 후 `b4-lab`.

## 제공 파일 확인

| 항목 | 결과 |
|---|---|
| ZIP | `~/Downloads/agent-app.zip` (13,847,175 B), SHA256 `b0489f1035369b4a8785cd84f2f0ff99f2b04f76d4caa1eca07229abb48a7732` |
| 내부 파일 | `agent-app-linux-x86`, `agent-app-linux-arm64`, `__MACOSX/` 메타데이터 2개. 경로 이탈(`..`, 절대경로) 없음 |
| 실행 파일 | `agent-app-linux-x86` 6,498,144 B, SHA256 `cdbae8c066e734916b7cd25dc9e651818acf63b2e6817125ede5e85a4de0ff5a` (ZIP에서 꺼낸 것과 `~/Downloads/agent-app/` 압축 해제본 동일) |
| 형식 | ELF 64-bit, little-endian, ET_EXEC, machine `0x3e`(x86-64). Machine 아키텍처 `x86_64`와 일치 (`file` 명령은 Machine에 없어 헤더를 직접 확인) |
| 동적 라이브러리 | `libdl`, `libz`, `libpthread`, `libc` — 모두 Ubuntu 24.04 Machine에서 해석됨 |

파일 내용은 변경하지 않았고 ZIP·실행 파일은 저장소에 포함하지 않습니다.

## 배포

```bash
# 파일은 Mac에서 Machine으로 stdin 스트리밍 (sudo는 Machine 안에서만 사용)
orb -m <machine> sudo install -o root -g agent-core -m 0750 /dev/stdin /opt/agent-app/bin/agent-app-linux-x86 < agent-app-linux-x86
```

`root:agent-core 0750`: `agent-admin`·`agent-dev`가 실행하고, 쓰기 권한은 root만 가집니다. 배포 후 SHA256이 위 값과 일치함을 확인했습니다.

## 실행 방법 (`agent-admin`, 환경변수 명시 로드)

```bash
sudo runuser -u agent-admin -- env -i PATH=/usr/bin:/bin HOME=/home/agent-admin bash -c \
  'cd ~; set -a; . /etc/default/agent-app; set +a; exec /opt/agent-app/bin/agent-app-linux-x86'
```

UID 1000(`agent-admin`), 보조 그룹 `agent-common agent-core`. 종료는 SIGINT(Ctrl+C 동등)로 수행했습니다.

## 발견: `AGENT_KEY_PATH`는 디렉터리이며 파일명은 `secret.key`

작업 16 설정(`AGENT_KEY_PATH=/opt/agent-app/api_keys/t_secret.key`)으로 실행한 결과, 제공 Agent가 직접 거부했습니다.

| 시도 | 환경 | 결과 |
|---|---|---|
| 1 | `AGENT_KEY_PATH=…/api_keys/t_secret.key` | `[2/5] FAIL` — `Key Path Mismatch. Expected: /opt/agent-app/api_keys` (3~5단계 Skipped) |
| 2 | `AGENT_KEY_PATH=/opt/agent-app/api_keys`, `secret.key` 없음 | `[2/5] OK`, `[3/5] FAIL` — `Missing File: secret.key (Expected location: /opt/agent-app/api_keys/secret.key)` |
| 3 | 위 경로 + `api_keys/secret.key`(`agent_api_key_test`, `root:agent-core 0640`) | 5/5 OK, `Agent READY` |

원인 분류: 시도 1·2는 **설정 불일치**(Agent 결함 아님). 이에 따라 `config/etc-default-agent-app.example`, `machine-setup.sh`(`keyfile` 단계), 문서를 정정했습니다. 이미 있던 `t_secret.key`는 삭제하지 않았고 더 이상 관리하지 않습니다. 시도 1·2는 `b4-recovery-test`에서 환경변수 임시 덮어쓰기로만 수행했고, `b4-lab`에는 정정된 설정으로만 실행했습니다.

## Boot Sequence 결과 (`b4-recovery-test`, `b4-lab` 동일)

```
>>> Starting Agent Boot Sequence...
[1/5] Checking User Account               [OK]   Running as service user 'agent-admin' (uid=1000)
[2/5] Verifying Environment Variables     [OK]   All required Envs correct
[3/5] Checking Required Files             [OK]   Verified 'secret.key' with correct key string.
[4/5] Checking Port Availability          [OK]   Port 15034 is available.
[5/5] Verifying Log Permission            [OK]   Log directory is writable: /var/log/agent-app
All Boot Checks Passed!
Agent READY
```

stderr 출력은 없었고(stdout/stderr를 함께 기록), 이후 `[INFO]` 로그가 나옵니다: `Agent listening at port 15034`, `Agent Worker Started`, 순환 부하(`Cycle: 0 -> 256MB/Lv10 -> 0`)로 메모리·CPU를 단계적으로 올렸다 내립니다(`nice=10`). 이 부하 때문에 공식 임계값(CPU 20 / MEM 10)이 의미를 가집니다. Agent는 `/var/log/agent-app/agent_app.log`에도 기록합니다(`agent-admin:agent-core 660`).

| 실행 | PID(부모/자식) |
|---|---|
| `b4-recovery-test` | 3164 / 3167 |
| `b4-lab` | 36865 / 36869 |

## 포트·프로세스 검증

- `ss -ltnp`(agent-admin 권한): `LISTEN 0.0.0.0:15034`, 소켓 소유 PID = **자식 프로세스**(3167 / 36869). 부모는 PyInstaller형 부트로더로 소켓을 직접 잡지 않습니다.
- Mac → Machine IP `:15034` TCP 연결 성공(`b4-recovery-test` 192.168.139.99, `b4-lab` 192.168.139.18). UFW 허용 규칙만으로 판단하지 않고 실제 LISTEN 소켓과 연결을 확인했습니다.
- 약 60초 이상 유지됨을 확인, 메모리 단계가 25MB씩 오르내림.
- SIGINT 종료: `Stop signal received` → `Agent Shutdown. Releasing resources.`, 잔여 프로세스 없음, 15034 해제.

## `monitor.sh` 관찰 (Agent 실행 중)

| 조건 | PROCESS | PORT | 결과 |
|---|---|---|---|
| `AGENT_PROCESS_PATTERN` 미설정(현재 설정, cron 실행 포함) | **PENDING** | OK(`0.0.0.0` LISTEN, "소유 PID 미평가") | `UNHEALTHY exit=1` |
| 패턴 `^/opt/agent-app/bin/agent-app-linux-x86` 임시 지정 | OK pid=[부모 자식] | OK, 소유 PID 일치 | `HEALTHY exit=0` (UFW는 비root라 UNKNOWN) |

**Agent 실행 성공과 모니터링 완료는 다릅니다.** Agent는 정상 기동했지만, `AGENT_PROCESS_PATTERN`이 환경 파일에 설정되지 않아 현재 cron의 `monitor.sh`는 계속 PENDING/`exit 1`을 기록합니다(작업 범위 밖이라 변경하지 않음). 패턴은 인자에 패턴 문자열이 들어가는 `env`/`runuser` 래퍼까지 매칭하므로(테스트 중 `pid=[…3182 3184]`로 확인) 앵커(`^`)를 쓰는 것이 안전합니다. UFW 상태는 비root라 UNKNOWN으로 남는 것도 기존과 같습니다(이후 작업).

## `b4-lab` 적용 범위

변경: `AGENT_KEY_PATH` 한 줄(백업 `/var/backups/b4-bootstrap`), `api_keys/secret.key` 생성, Agent 바이너리 배포. 변경 없음: SSH·UFW·사용자·그룹·ACL·cron(1개 유지). `monitor.log`는 삭제·초기화 없이 2100줄 → 2120줄로 증가했고, Agent 실행 중 cron 1회(20:26:01)가 그대로 기록됐습니다.

## 판정

| 항목 | 판정 |
|---|---|
| 일반 계정(agent-admin)으로 실행 | PASS |
| Boot Sequence 5/5 `[OK]` | PASS (설정 정정 후) |
| `Agent READY` | PASS |
| `0.0.0.0:15034` LISTEN, 소유 PID | PASS |
| 정상 종료·잔여 프로세스 없음 | PASS |
| `monitor.sh` 프로세스 판정 | PENDING (`AGENT_PROCESS_PATTERN` 미설정) |

---

# 작업 18: Agent 정상 모니터링(공식 로그 형식)

`AGENT_PROCESS_PATTERN=^/opt/agent-app/bin/agent-app-linux-x86`를 환경 파일에 반영했고(작업 17에서 부모 PID·자식 PID 일치, 소켓 소유 = 자식 확인), 작업 17의 `PENDING`이던 `monitor.sh` 프로세스 판정이 해결됐습니다.

| 상황 | `monitor.sh` | 비고 |
|---|---|---|
| Agent 실행 중 (두 Machine) | `HEALTHY exit 0`, `PID:<자식>` 기록 | cron 예약 실행 4회 연속 공식 형식 기록 |
| Agent 중지 | `UNHEALTHY exit 1`, `PID:N/A` 기록 | 포트 LISTEN 없음도 FAIL |

자세한 변경·검증은 [monitor 기록 작업 18](b4-1-monitor.md#작업-18-공식-로그-형식agent-정상-모니터링). Agent는 검증 후 SIGINT로 종료했으며 상주 서비스로 구성하지 않았습니다(종료 후 잔여 프로세스 없음, 15034 해제).

**증빙으로 남기는 불일치:** 과제 설명은 `AGENT_KEY_PATH`가 `/opt/agent-app/api_keys/t_secret.key` 파일이라고 했지만 실제 제공 Agent는 디렉터리 `/opt/agent-app/api_keys`와 그 안의 `secret.key`를 요구합니다(작업 17 표 참고). 설정은 Agent 요구에 맞췄습니다.

남은 항목: UFW 비활성 경고 검증, 로그 보존 정책 추가 조정(후속 작업).
