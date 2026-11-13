# Codyssey B4-1 — Linux 서버 기본 환경 구성

코디세이 B4-1 미션 저장소입니다.
OrbStack Ubuntu **Linux Machine**을 실습 서버로 사용하며, 여기서 만든 Linux 환경과 `monitor.sh`는 이후 **B4-2에서 그대로 재사용**합니다.

- B4-2 저장소: https://github.com/hyun02063185-AX-beginner/Codyssey_B4-2

> **현재 상태 (2026-11-13)** — Mission Core 중 **제공 Agent가 필요한 부분을 제외하고 구현·검증 완료**. Mission Core 전체 완료는 아닙니다.
>
> | 영역 | 상태 | 상세 |
> |---|---|---|
> | Ubuntu Machine `b4-lab` (24.04.5, x86_64) | 완료 | [환경 문서 9장](docs/orbstack-environment.md#9-기본-실행환경-사전검증-기록) |
> | SSH 20022 + Root 차단 | 완료(Mac 실제 접속·`ROOT LOGIN REFUSED` 확인) | [10장](docs/orbstack-environment.md#10-ssh-20022-구성-및-검증-기록) |
> | UFW (deny in / allow out, 20022·15034) | 완료(실제 허용·차단, `orb restart` 후 복원 확인) | [11장](docs/orbstack-environment.md#11-ufw-방화벽-구성-및-검증-기록) |
> | 사용자 3·그룹 2·소속, `/opt/agent-app` 권한·ACL | 완료 — **[승인된 실습 설계]**(공식 원문 미대조) | [권한 설계·적용](docs/b4-1-permission-plan.md) |
> | 환경변수 `/etc/default/agent-app` | `AGENT_HOME/PORT/UPLOAD_DIR/LOG_DIR` 완료, **`AGENT_KEY_PATH` PENDING**(Agent 필요) | [Agent 실행환경](docs/b4-1-agent-runtime.md) |
> | `monitor.sh` (프로세스·포트·UFW·CPU/MEM/DISK) | 구현·배포·검증. Agent 부재 시 `exit 1`이 **예상된 장애 감지 결과** | [monitor 기록](docs/b4-1-monitor.md) |
> | `monitor.log` 기록 · 10MB/10개 순환(logrotate) | 완료(순환은 임시 환경에서 검증, 실제 타이머 발동은 PENDING) | [monitor 기록](docs/b4-1-monitor.md), [로그 순환](docs/b4-1-log-rotation.md) |
> | `agent-admin` cron 매분 자동 실행 | 완료(예약 실행 연속 확인, `trigger=cron`) | [cron 기록](docs/b4-1-cron.md) |
> | **환경 복구 자동화** (`bootstrap-orbstack.sh`) | **완료** — 새 Machine `b4-recovery-test`에 GitHub 파일만으로 재구축, `b4-lab`과 동일 확인, 반복 실행 안전 | [복구 자동화](docs/b4-1-recovery.md) |
> | **제공 Agent** 설치·기동 (Boot Sequence, `Agent READY`, 0.0.0.0:15034 LISTEN) | **PENDING** — 원본 미확보 | [Agent 실행환경](docs/b4-1-agent-runtime.md) |
>
> **제출 문서:** [요구사항 수행 내역서](docs/b4-1-final-evidence.md)(항목별 PASS/PENDING·증빙 목록) · [B4-2 인수인계](docs/b4-2-environment-handoff.md)
>
> 남은 의존성: ① **제공 Agent 원본** ② **공식 미션 원문 대조**(모든 설정값은 [승인된 실습 설계]/[관리자료]) ③ logrotate 타이머의 실제 발동 확인(다음 00:00 KST 이후).

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
├── README.md                          # 개요, 현재 상태, Mission Core 체크리스트, 복구 절차 요약
├── bin/
│   └── monitor.sh                     # 점검 스크립트 원본 → 배포 /opt/agent-app/bin/monitor.sh
├── config/                            # Machine에 설치되는 설정 파일 (비밀정보 없음)
│   ├── sshd-b4-mission.conf           # /etc/ssh/sshd_config.d/10-b4-mission.conf
│   ├── etc-default-agent-app.example  # /etc/default/agent-app
│   ├── etc-logrotate.d-agent-app      # /etc/logrotate.d/agent-app
│   └── crontab-agent-admin.example    # agent-admin crontab 예시
├── scripts/
│   ├── bootstrap-orbstack.sh          # (Mac) Machine 생성·적용·점검·검증 — 복구 자동화 진입점
│   ├── machine-setup.sh               # (Machine 안, root) 단계별 check/apply/snapshot
│   ├── monitor-cron.sh                # agent-admin cron 작업 install/pause/resume/remove/status
│   └── README.md
└── docs/
    ├── orbstack-environment.md        # OrbStack 역할, 버전 고정, SSH 구분, 사전검증·SSH·UFW·사용자 기록
    ├── b4-1-permission-plan.md        # 권한·ACL 설계와 적용·검증
    ├── b4-1-agent-runtime.md          # 환경변수·Agent 실행 준비(Agent NOT FOUND)
    ├── b4-1-monitor.md                # monitor.sh·monitor.log 구현·검증
    ├── b4-1-log-rotation.md           # logrotate 순환 설계·검증
    ├── b4-1-cron.md                   # cron 매분 실행 검증
    ├── b4-1-recovery.md               # 환경 복구 자동화와 재구축 검증
    ├── b4-1-final-evidence.md         # 제출용 요구사항 수행 내역서·증빙 목록
    └── b4-2-environment-handoff.md    # B4-2 환경 인수인계
```

**아직 없는 것:** 제공 Agent(원본 미확보). 저장소에는 Agent를 포함하지 않으며, 대체 구현도 하지 않습니다.

## 3. B4-1 Mission Core 체크리스트

### 3.1 작업 원칙

- **제공 Python 앱(Agent)은 수정 대상이 아니라 실행 대상입니다.** 앱 코드는 고치지 않고, 앱이 요구하는 사용자·권한·환경변수·포트 조건을 Linux 환경 쪽에서 맞춥니다.
- **`monitor.sh`는 Bash로 작성합니다.** (shebang `#!/bin/bash` 또는 `#!/usr/bin/env bash`)
- 제공 바이너리/앱의 architecture·실행 조건은 추정하지 않고 실제 확인(`uname -m`, `file`, 실행 결과)한 값만 기록합니다.
- 모든 설정은 수동으로 먼저 수행·검증한 뒤 `scripts/bootstrap-orbstack.sh`로 옮겼고(작업 14), 새 Machine에서 재현됨을 확인했습니다.

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
| 로그 순환 | 최대 10MB, 최대 10개 | [관리자료] | logrotate 사용·활성 1 + 순환본 9 = 최대 10개·10 MiB 이상에서 순환은 [승인된 실습 설계]. 크기는 일 1회 검사라 엄격한 최대 크기가 아님 |
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
- [x] 증빙: `ls -ld`, `stat`, `getfacl` ([권한 설계 11장](docs/b4-1-permission-plan.md))

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
- [ ] [확인 필요] `agent-*` 사용자의 SSH 접속 방식 (현재 비밀번호 잠금·키 없음 = 접속 불가, 원문 확인 후 결정)
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
- [x] [관리자료] `/var/log/agent-app/monitor.log`에 기록 — 스크립트가 직접 append(cron 리디렉션 비의존), `agent-admin:agent-core 0660`, 3회 누적·터미널과 동일 PASS ([상세](docs/b4-1-monitor.md#21-monitorlog-누적-기록-작업-11)). cron 환경 실측·Agent 정상 기록은 PENDING
- [x] [관리자료] 최대 10MB / 최대 10개로 순환 — logrotate 사용, 활성 1 + 순환본 9 = 최대 10개, 10 MiB 이상이면 순환 ([상세](docs/b4-1-log-rotation.md)). 검사는 일 1회라 **엄격한 최대 크기 보장은 아님**. 실제 타이머 발동·실제 크기 도달 순환은 PENDING, 크기·개수의 원문 대조 필요
- [x] `agent-admin`이 로그에 쓸 수 있는지 확인(`sudo -u agent-admin`으로 실측 PASS). 실제 cron 세션에서의 확인은 cron 작업에서 PENDING
- [ ] [확인 필요] 로그 라인 형식 — 현재 `YYYY-MM-DD HH:MM:SS [LEVEL] CATEGORY message` 임시 설계 형식, 공식 원문 대조 필요
- [ ] 증빙: `tail` 결과(확보: 3회 실행 후 로그, [상세](docs/b4-1-monitor.md#52-monitorlog-기록-테스트-작업-11-실측)), 순환 설정 내용(적용: `/etc/logrotate.d/agent-app`, [config/etc-logrotate.d-agent-app](config/etc-logrotate.d-agent-app))

#### 9) cron
- [x] [관리자료] `agent-admin` 계정의 crontab에 매분(`* * * * *`) `monitor.sh` 등록 ([cron 기록](docs/b4-1-cron.md))
- [x] cron 서비스 동작 확인 (`cron 3.0pl1-184ubuntu2`, enabled·active, `agent-admin` 세션 정상 개설)
- [x] 절대 경로 사용, 환경변수는 스크립트가 `/etc/default/agent-app`을 직접 로드(cron 환경에는 `AGENT_*` 없음을 관찰로 확인)
- [x] 증빙: `sudo crontab -u agent-admin -l`, 매분 로그 누적(6회 이상, `trigger=cron`) — [cron 기록 §3](docs/b4-1-cron.md). 정상(exit 0) 기록은 Agent 확보 후 PENDING

#### 10) 마무리
- [x] 수동 설정을 `scripts/bootstrap-orbstack.sh`로 재현 가능하게 정리 (작업 14, [복구 자동화](docs/b4-1-recovery.md))
- [x] 새 Machine(`b4-recovery-test`)에서 bootstrap 실행 → 재검증 PASS(`b4-lab`과 동일, 반복 실행 안전). Agent 관련 항목은 PENDING
- [x] 제출 수행 내역서·증빙 목록 정리 → [b4-1-final-evidence.md](docs/b4-1-final-evidence.md) (공식 제출 원문은 미확인; 터미널 캡처 자체는 사용자가 찍어야 함, 목록은 §4)
- [x] B4-2에서 사용할 값(Machine 이름, 사용자, 포트, `monitor.sh` 경로) 기록 → [b4-2-environment-handoff.md](docs/b4-2-environment-handoff.md)

## 4. 교육장 Mac 초기화 후 복구 (요약)

**"상태의 원본은 이 GitHub 저장소"** 입니다. Mac 쪽에서는 sudo를 쓰지 않고, 필요한 권한 작업은 Machine 안에서만 수행합니다. 자세한 설명·검증 결과는 [docs/b4-1-recovery.md](docs/b4-1-recovery.md).

| | 초기화로 사라짐 | GitHub로 재현됨 |
|---|---|---|
| 내용 | 기존 Machine과 그 안의 데이터(`monitor.log`·순환본, 업로드 파일, 저장소에 없는 수동 변경), 사용자 비밀번호, Mac의 SSH 키쌍, push하지 않은 로컬 커밋 | OrbStack Machine 생성, SSH 20022·Root 차단, UFW, 사용자·그룹·소속, `/opt/agent-app` 권한·ACL, 환경변수 파일, `monitor.sh`, `monitor.log` 권한, logrotate, `agent-admin` cron |
| 복구 불가(저장소에 없음) | SSH 개인키·API 키·비밀번호, **제공 Agent 원본(PENDING)** | |

**절차 A — 처음 쓰는 Mac에서 새 Machine 구성**

```bash
git clone https://github.com/hyun02063185-AX-beginner/Codyssey_B4-1.git && cd Codyssey_B4-1
scripts/bootstrap-orbstack.sh all          # = create + apply + verify (소요 약 1분 + cron 확인 대기)
# 단계별: create → apply → verify --wait-cron 240
```

**절차 B — 이미 구성된 Machine 점검·복구**

```bash
scripts/bootstrap-orbstack.sh check                    # 지속 상태 변경 없음: 단계별 OK/DIFF (--no-run: monitor.sh도 실행 안 함)
scripts/bootstrap-orbstack.sh apply --allow-existing   # 차이가 있는 단계만 복구(기존 로그·다른 crontab 항목 보존, 삭제 없음)
```

- 다른 이름의 Machine: `--machine NAME`. 기존 `b4-lab`을 삭제·초기화하는 기능은 없습니다.
- SSH는 서비스를 재시작하기 **전에** `sshd -t`·`sshd -T`로 검증하고, 충돌(예: `00-*.conf`의 `PermitRootLogin yes`, `Port 22`)이 있으면 조각을 원복한 채 중단합니다(작업 14-1).
- 반복 실행해도 같은 결과(idempotent)이며, 단계가 실패하면 그 단계에서 멈춥니다.
- 상세: [환경 문서 7장](docs/orbstack-environment.md#7-교육장-mac-초기화-후-복구-흐름).

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
