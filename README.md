# Codyssey B4-1 — Linux 서버 기본 환경 구성

코디세이 B4-1 미션 저장소입니다.
OrbStack Ubuntu **Linux Machine**을 실습 서버로 사용하며, 여기서 만든 Linux 환경과 `monitor.sh`는 이후 **B4-2에서 그대로 재사용**합니다.

- B4-2 저장소: https://github.com/hyun02063185-AX-beginner/Codyssey_B4-2

> **현재 상태 (2026-11-11)**
> - OrbStack Ubuntu Machine `b4-lab`(Ubuntu 24.04.5 LTS, x86_64) 생성 및 기본 실행환경 사전검증 완료 → [검증 기록](docs/orbstack-environment.md#9-기본-실행환경-사전검증-기록)
> - **SSH 완료:** TCP 20022 단독 사용, Root 원격 로그인 차단, Mac에서 실제 접속 검증 → [SSH 검증 기록](docs/orbstack-environment.md#10-ssh-20022-구성-및-검증-기록)
> - **UFW 완료:** 기본 deny(in)/allow(out), 20022·15034/tcp만 허용, Machine IP 기준 실제 허용·차단 검증 재시작 후 자동 복원 검증 완료 → [UFW 검증 기록](docs/orbstack-environment.md#11-ufw-방화벽-구성-및-검증-기록)
> - **사용자·그룹 생성 완료:** `agent-admin/dev/test`, `agent-common/core` 생성 → [12장](docs/orbstack-environment.md#12-사용자그룹-구성-및-검증-기록) (생성 시점에는 소속 미적용이었고, 현재 소속은 바로 아래 항목 참고)
> - **그룹 소속·디렉터리 권한/ACL 적용 완료([승인된 실습 설계], 공식 원문 미대조):** `agent-admin`∈common+core, `agent-dev`∈common, `agent-test` 미가입. `/opt/agent-app/{upload_files,api_keys}`, `/var/log/agent-app` 생성·ACL 적용, 계정별 허용/차단 실측 PASS → [권한 설계·적용 기록](docs/b4-1-permission-plan.md#11-실제-적용-및-검증-작업-8)
> - **환경변수 파일 적용(부분 완료):** `/etc/default/agent-app`(`root:root 0644`)에 `AGENT_HOME/PORT/UPLOAD_DIR/LOG_DIR` 적용·`agent-admin` 새 프로세스에서 로드 검증 PASS. `AGENT_KEY_PATH`는 **PENDING**(빈 값). 제공 Agent 원본은 **NOT FOUND**라 실행·`Agent READY`·15034 LISTEN 검증은 **미실시** → [Agent 실행환경 기록](docs/b4-1-agent-runtime.md)
> - **monitor.sh 구현·1차 검증(Agent 없이 가능한 범위):** [bin/monitor.sh](bin/monitor.sh) → `/opt/agent-app/bin/monitor.sh`(`root:agent-admin 0750`). 프로세스 `PENDING`(식별 기준 미설정)·15034 미LISTEN → exit 1, UFW는 `agent-admin` 권한으로 `UNKNOWN`, CPU/MEM/DISK 수집·임계값·설정 오류(exit 2) 로직 PASS. **Agent 정상 판정·exit 0 실측·cron·로그 기록은 PENDING** → [monitor 기록](docs/b4-1-monitor.md)
> - **나머지 Mission Core는 미착수:** Agent 기동, 로그 기록·순환, cron. Mission Core 전체 완료가 아닙니다.

---

## 1. 실습 환경

| 항목 | 내용 |
| --- | --- |
| Host | 코디세이 교육장 Mac (macOS, `x86_64`) |
| Host 제약 | macOS host에서 `sudo` 사용 불가 |
| Host 초기화 | 교육장 Mac은 주기적으로 초기화됨 → 로컬 상태는 언제든 사라질 수 있음 |
| 가상화 도구 | OrbStack 2.0.5 |
| **B4-1 기본 실습환경** | **OrbStack Ubuntu Linux Machine `b4-lab`** (`ubuntu:noble`, 24.04 LTS) |
| 사용하지 않는 것 | Docker Container(기본 실습환경 아님), AWS EC2(기본환경 아님) |

- host에서는 `sudo`가 안 되지만, OrbStack Linux Machine **내부**에서는 `sudo`를 사용할 수 있습니다(검증 완료).
- Docker Container 대신 Linux Machine을 쓰는 이유, Ubuntu 버전 고정, OrbStack 내부 SSH와 미션 SSH의 차이는 [docs/orbstack-environment.md](docs/orbstack-environment.md)에 정리되어 있습니다.

## 2. 저장소 구조

```
.
├── README.md                     # 미션 개요, 환경, Mission Core 체크리스트, 복구 흐름 요약
├── docs/
│   └── orbstack-environment.md   # OrbStack 역할, Container vs Machine, 버전 고정, SSH 구분, 복구 흐름, 사전검증 기록
└── scripts/
    └── README.md                 # scripts/ 디렉터리 용도, 향후 bootstrap-orbstack.sh 역할
```

향후 추가 예정(아직 없음):

- `scripts/bootstrap-orbstack.sh` — 교육장 Mac 초기화 후 OrbStack Ubuntu Machine을 같은 상태로 재구성하는 스크립트. 역할과 범위는 [scripts/README.md](scripts/README.md) 참고.
- `monitor.sh` — Mission Core 산출물. 저장소 `bin/monitor.sh` → 배포 `/opt/agent-app/bin/monitor.sh`.

## 3. B4-1 Mission Core 체크리스트

### 3.1 작업 원칙

- **제공 Python 앱(Agent)은 수정 대상이 아니라 실행 대상입니다.** 앱 코드는 고치지 않고, 앱이 요구하는 사용자·권한·환경변수·포트 조건을 Linux 환경 쪽에서 맞춥니다.
- **`monitor.sh`는 Bash로 작성합니다.** (shebang `#!/bin/bash` 또는 `#!/usr/bin/env bash`)
- 제공 바이너리/앱의 architecture·실행 조건은 추정하지 않고 실제 확인(`uname -m`, `file`, 실행 결과)한 값만 기록합니다.
- 모든 설정은 수동으로 먼저 수행·검증한 뒤 `scripts/bootstrap-orbstack.sh`로 옮깁니다.

### 3.2 값의 구분과 출처

**출처:** 3.3 요약표의 [관리자료] 값은 **기존 Codyssey 관리 자료**에서 확인된 값입니다. 공식 미션 원문과의 직접 대조는 아직 끝나지 않았습니다.

| 표시 | 의미 |
| --- | --- |
| **[관리자료]** | 기존 Codyssey 관리 자료에 명시된 값. 공식 원문 직접 대조 전 |
| **[원문 대조 완료]** | 공식 미션 원문과 직접 대조해 일치를 확인한 값 (현재 해당 없음) |
| **[설계]** | 요구사항에 없고, 이 저장소의 환경 설계상 선택한 값 |
| **[확인 필요]** | 값이 정해지지 않았거나, 추측하지 않기 위해 비워 둔 항목, 또는 OrbStack 환경에서 동작이 검증되지 않은 항목 |

원문 대조가 끝나면 해당 행을 [원문 대조 완료]로 바꿉니다. 정확한 로그 형식·임계값·세부 권한 모드(숫자 mode)는 추측해 적지 않습니다.

### 3.3 요구사항 요약표

| 영역 | 요구 값 | 구분 | 비고 |
| --- | --- | --- | --- |
| 사용자 | `agent-admin`, `agent-dev`, `agent-test` | [관리자료] | |
| 그룹 | `agent-common`, `agent-core` | [관리자료] | |
| 사용자 ↔ 그룹 소속 | `agent-admin`∈common+core, `agent-dev`∈common, `agent-test` 미가입 (**적용됨**) | [승인된 실습 설계] | 공식 원문 미대조 → 원문 확인 필요. 저장소·Mac에서 원문을 찾지 못함 |
| SSH 포트 | TCP `20022` | [관리자료] | **적용·검증 완료** (22 미사용) |
| SSH Root 원격 로그인 | 차단 | [관리자료] | **적용·검증 완료** — `PermitRootLogin no` |
| SSH 운영 방식 | `ssh.socket` 비활성 + `ssh.service` 상시 실행, 설정은 `/etc/ssh/sshd_config.d/10-b4-mission.conf` | [설계] | 이유: [docs 10.2](docs/orbstack-environment.md#102-운영-방식-결정-socket-비활성--sshservice-상시-실행-설계) |
| SSH 비밀번호 인증 | 기본값(`yes`) 유지 | [확인 필요] | 공식 요구 여부 확인 |
| 방화벽 인바운드 | TCP `20022`, `15034`**만** 허용 | [관리자료] | 그 외 인바운드 차단 |
| 방화벽 아웃바운드 정책 | allow | [설계] | 원문 요구가 있으면 그 값을 따름 → 확인 필요 |
| `upload_files` 디렉터리 | `agent-common` 그룹 R/W | [관리자료] | 경로·소유자·숫자 mode는 [확인 필요] |
| `api_keys` 디렉터리 | `agent-core` 그룹 R/W | [관리자료] | 경로·소유자·숫자 mode는 [확인 필요] |
| `/var/log/agent-app` | `agent-core` 그룹 R/W | [관리자료] | 소유자·숫자 mode는 [확인 필요] |
| 환경변수 | `AGENT_HOME`, `AGENT_PORT`, `AGENT_UPLOAD_DIR`, `AGENT_KEY_PATH`, `AGENT_LOG_DIR` | [관리자료] | 각 변수의 값·적용 범위는 [확인 필요] |
| Agent 기동 성공 기준 | Boot Sequence 5단계 모두 OK → `Agent READY` 출력 → `0.0.0.0:15034` LISTEN | [관리자료] | 실행 사용자·상주 방식은 [확인 필요] |
| `monitor.sh` 언어 | Bash | [관리자료] | |
| `monitor.sh` 점검 항목 | 프로세스, 포트, 방화벽, CPU / MEM / DISK | [관리자료] | 출력 형식·임계값은 [확인 필요] |
| `monitor.sh` 실패 처리 | 프로세스·포트 점검 실패 → `exit 1` / 방화벽 비활성 → `WARNING` | [관리자료] | WARNING 시 종료 코드는 [확인 필요] |
| 로그 파일 | `/var/log/agent-app/monitor.log` | [관리자료] | 로그 라인 형식은 [확인 필요] |
| 로그 순환 | 최대 10MB, 최대 10개 | [관리자료] | 구현 방식(logrotate / 스크립트 내부)은 [확인 필요] |
| cron | `agent-admin` 계정으로 매분 실행 | [관리자료] | |
| Ubuntu 버전 | 24.04 LTS (`ubuntu:noble`) | [설계] | 원문 지정 버전이 있으면 그 값을 따름 → 확인 필요 |
| Machine 이름 | `b4-lab` | [설계] | |

### 3.4 체크리스트

#### 0) 환경 준비
- [x] [설계] `orb create ubuntu:noble b4-lab`으로 Machine 생성 (2026-11-11)
- [x] `uname -m`(x86_64), `/etc/os-release`(24.04.5 LTS), `python3 --version`(3.12.3), PID 1(systemd), `sudo -n true`, `systemctl --version`(255) 확인 → [검증 기록](docs/orbstack-environment.md#9-기본-실행환경-사전검증-기록)
- [ ] 제공 Agent 앱/바이너리의 architecture·Python 요구 버전을 `file`·실행 결과로 확인 (추정 금지)

#### 1) 사용자 / 그룹
- [x] [관리자료] 사용자 `agent-admin`, `agent-dev`, `agent-test` 생성 (홈 `750`, 비밀번호 잠김, sudo 없음)
- [x] [관리자료] 그룹 `agent-common`(GID 1000), `agent-core`(GID 1001) 생성
- [x] 사용자별 그룹 소속 설정 — **[승인된 실습 설계]**(공식 원문 미대조): admin∈common+core, dev∈common, test 미가입. [확인 필요] 원문 대조
- [x] 증빙: `id agent-admin`, `id agent-dev`, `id agent-test`, `getent group agent-common agent-core`

#### 2) 디렉터리 / 파일 권한
- [x] 설계 및 ACL 실측 후 **적용 완료**(작업 8, [승인된 실습 설계]): [docs/b4-1-permission-plan.md](docs/b4-1-permission-plan.md)
- [x] [관리자료] `upload_files` — `agent-common` R/W: `/opt/agent-app/upload_files` `agent-admin:agent-common 2770`+ACL (경로·mode는 [승인된 실습 설계], 원문 확인 필요)
- [x] [관리자료] `api_keys` — `agent-core` R/W: `/opt/agent-app/api_keys` `root:agent-core 2770`+ACL (경로·mode는 [승인된 실습 설계], 원문 확인 필요)
- [x] [관리자료] `/var/log/agent-app` — `agent-core` R/W: `root:agent-core 2770`+ACL (mode는 [승인된 실습 설계], 원문 확인 필요)
- [x] 그룹 외 사용자가 접근할 수 없는지 확인 (`sudo -u`로 agent-dev/agent-test 거부 실측)
- [ ] 증빙: `ls -ld <경로>`, `stat <경로>`

#### 3) SSH
상세 절차·결과: [docs 10장](docs/orbstack-environment.md#10-ssh-20022-구성-및-검증-기록) (2026-11-11)

- [x] openssh-server 설치 (`1:9.6p1-3ubuntu13.20`)
- [x] [설계] `ssh.socket` 비활성, `ssh.service` 활성 — 포트를 `sshd_config` 한 곳에서 관리
- [x] [관리자료] `Port 20022` (`/etc/ssh/sshd_config.d/10-b4-mission.conf`)
- [x] [관리자료] Root 원격 로그인 차단 (`PermitRootLogin no`)
- [x] `sudo sshd -t` 문법 검사 후 서비스 기동
- [x] 증빙: `ss -tlnp` → `0.0.0.0:20022`, `[::]:20022`만 LISTEN, 22 없음
- [x] 증빙: Mac → `ssh -p 20022`로 Ubuntu sshd 접속 성공 (IP, `b4-lab.orb.local` 모두)
- [x] 증빙: Mac → Machine IP `:22` Connection refused
- [x] 증빙: root에 유효 키를 임시 등록해도 거부, sshd 로그 `ROOT LOGIN REFUSED` → 설정에 의한 차단 (임시 키 제거 완료)
- [x] OrbStack 관리 SSH(`ssh b4-lab@orb`, `orb -m`)와 구분해 증빙, 관리 경로 유지 확인 ([docs 5장](docs/orbstack-environment.md#5-orbstack-내부-ssh-vs-미션-ssh))
- [x] `orb restart b4-lab` 후 설정 유지 확인
- [ ] [확인 필요] `agent-*` 사용자의 SSH 접속 방식 (사용자 생성 작업에서 결정)
- [ ] [확인 필요] `PasswordAuthentication` 공식 요구 여부

#### 4) 방화벽 (UFW)
- [x] ufw 설치 (`0.36.2`)
- [x] [관리자료] `20022/tcp` 허용 — 활성화 전에 먼저 추가
- [x] [관리자료] `15034/tcp` 허용
- [x] [관리자료] 그 외 인바운드 차단 (default deny incoming)
- [x] UFW 활성화 (IPv4/IPv6 모두 규칙 적용)
- [x] 증빙: `sudo ufw status verbose` ([11장](docs/orbstack-environment.md#11-ufw-방화벽-구성-및-검증-기록))
- [x] OrbStack Machine에서 UFW가 실제로 패킷을 차단·허용하는지 검증 — Machine IP 기준 PASS (15035 활성화 전 접속 성공 → 후 차단)
- [x] `orb restart b4-lab` 후 UFW 자동 복원 및 허용·차단 재검증 PASS ([11.7](docs/orbstack-environment.md#117-재시작-후-복원-검증-작업-5-1)). 단 이는 OrbStack Machine 재시작 범위이며 Mac 재부팅·OrbStack 앱 재시작은 미검증

#### 5) 환경변수
- [x] `AGENT_HOME`, `AGENT_PORT`, `AGENT_UPLOAD_DIR`, `AGENT_LOG_DIR` 정의 — `/etc/default/agent-app`, 값은 [승인된 실습 설계]/[관리자료](원문 대조 필요)
- [ ] [확인 필요] `AGENT_KEY_PATH` — 파일/디렉터리 여부 미확인(PENDING, 빈 값). 제공 Agent 필요
- [ ] 환경변수를 실제 Agent가 사용하는지 검증 (Agent NOT FOUND)
- [ ] [확인 필요] 각 변수의 값과 적용 위치(로그인 셸 / Agent 실행 환경 / cron 환경) — 파일 로드 방식은 검증됨, 원문 대조·Agent·cron 적용은 미완 — **cron은 로그인 셸 환경변수를 상속하지 않음에 주의**
- [ ] 증빙: Agent·`monitor.sh` 실행 환경에서 실제 값 출력

#### 6) Agent(제공 Python 앱) 기동
- [ ] 제공 앱을 **수정하지 않고** 그대로 배치
- [ ] [확인 필요] 실행 사용자·명령·상주 방식
- [ ] [관리자료] Boot Sequence 5단계 모두 OK
- [ ] [관리자료] `Agent READY` 출력
- [ ] [관리자료] `0.0.0.0:15034` LISTEN — `ss -tlnp | grep 15034`
- [ ] 증빙: 기동 로그, `ps`, `ss` 결과

#### 7) `monitor.sh` (Bash)
- [x] Bash로 작성, `bash -n` 문법 검사 PASS → [bin/monitor.sh](bin/monitor.sh), 상세 [docs/b4-1-monitor.md](docs/b4-1-monitor.md)
- [ ] [관리자료] 점검: Agent 프로세스 — 구현됨, 식별 기준(`AGENT_PROCESS_PATTERN`) **PENDING**(Agent 없음). 실제 Agent 판정 미검증
- [ ] [관리자료] 점검: 포트(15034 LISTEN) — 구현. 미LISTEN·바인딩(0.0.0.0 vs localhost/IPv6)·소유 PID 일치/불일치/확인 불가 판정 fixture 검증 PASS(작업 10-1). Agent의 실제 LISTEN은 PENDING
- [x] [관리자료] 점검: 방화벽 상태 — 구현. root 실행 시 실제 판정 PASS, `agent-admin`(sudo 없음)은 `UNKNOWN`
- [x] [관리자료] 점검: CPU / MEM / DISK 사용량 — 수집·계산 PASS, 임계값 80%는 **[설계 기본값]**(원문 확인 필요)
- [x] [관리자료] 프로세스·포트 점검 실패 시 `exit 1` (식별 기준 미설정도 exit 1, 설정·수집 오류는 exit 2)
- [x] [관리자료] 방화벽 비활성 시 `WARNING` 출력 — 로직은 스텁 출력으로 검증, 실제 UFW 비활성 상태는 미검증
- [x] 배치 경로·소유자·권한: `/opt/agent-app/bin/monitor.sh` `root:agent-admin 0750` ([이 작업의 설계 결정], 원문 확인 필요). 출력 형식은 임시 형식
- [ ] 증빙: 정상(exit 0) / 프로세스 중지 / 방화벽 비활성 각 상황의 출력과 `echo $?` — 현재는 Agent 부재 상황(exit 1)만 실측, 정상은 PENDING

#### 8) 로그
- [ ] [관리자료] `/var/log/agent-app/monitor.log`에 기록
- [ ] [관리자료] 최대 10MB / 최대 10개로 순환 (logrotate는 기본 설치되어 있음 — 사용 여부 [확인 필요])
- [ ] cron 실행 사용자(`agent-admin`)가 로그에 쓸 수 있는지 확인
- [ ] [확인 필요] 로그 라인 형식
- [ ] 증빙: `tail` 결과, 순환 설정 내용

#### 9) cron
- [ ] [관리자료] `agent-admin` 계정의 crontab에 매분(`* * * * *`) `monitor.sh` 등록
- [ ] cron 서비스 동작 확인 (사전검증 결과 cron **설치·active**)
- [ ] 절대 경로 사용, 필요한 환경변수를 crontab 또는 스크립트에서 명시
- [ ] 증빙: `sudo crontab -u agent-admin -l`, 매분 로그가 누적되는 결과

#### 10) 마무리
- [ ] 수동 설정을 `scripts/bootstrap-orbstack.sh`로 재현 가능하게 정리
- [ ] 새 Machine에서 bootstrap 실행 → 위 체크리스트 재검증
- [ ] 제출 요구사항(스크린샷, 출력 결과 등) 정리
- [ ] B4-2에서 사용할 값(Machine 이름, 사용자, 포트, `monitor.sh` 경로) 기록

## 4. 교육장 Mac 초기화 후 복구 흐름 (요약)

Mac이 초기화되면 OrbStack Machine과 그 안의 설정이 모두 사라질 수 있습니다.
따라서 **"상태의 원본은 이 GitHub 저장소"** 라는 원칙으로 작업합니다.

1. OrbStack 실행 확인 (`orb version`)
2. 이 저장소를 다시 clone
3. `orb list`로 `b4-lab` 확인 → 없으면 `orb create ubuntu:noble b4-lab`
4. `scripts/bootstrap-orbstack.sh` 실행 (작성 이후)
5. 체크리스트 기준으로 상태 재검증

상세 절차는 [docs/orbstack-environment.md](docs/orbstack-environment.md#7-교육장-mac-초기화-후-복구-흐름)를 참고합니다.

## 5. B4-1과 B4-2의 관계

- B4-2 저장소: https://github.com/hyun02063185-AX-beginner/Codyssey_B4-2

| 구분 | B4-1 | B4-2 |
| --- | --- | --- |
| 역할 | Linux 서버 기본 환경 **구축** | B4-1 환경을 **재사용**하여 다음 미션 수행 |
| 산출물 | 설정된 Ubuntu Machine + `monitor.sh` + 재현 스크립트 + 문서 | B4-1 산출물 위에서 진행 |
| 의존성 | 없음 | B4-1 결과(Linux 환경, `monitor.sh`)에 의존 |

- **B4-2는 B4-1의 Linux 환경과 `monitor.sh`를 재사용합니다.** 따라서 B4-1 설정은 반드시 재현 가능해야 합니다.
- Mac 초기화로 Machine이 사라져도 `bootstrap-orbstack.sh`로 B4-1 종료 시점 상태를 복구할 수 있어야 B4-2를 이어갈 수 있습니다.
- B4-1에서 정한 값(Machine 이름 `b4-lab`, Ubuntu 24.04, 사용자명, 포트, `monitor.sh` 경로 등)은 B4-2에서 바꾸지 않는 것을 원칙으로 하며, 변경 시 이 README에 기록합니다.
