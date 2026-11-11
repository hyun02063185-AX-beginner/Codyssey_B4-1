# Codyssey B4-1 — Linux 서버 기본 환경 구성

코디세이 B4-1 미션 저장소입니다.
OrbStack Ubuntu **Linux Machine**을 실습 서버로 사용하며, 여기서 만든 Linux 환경과 `monitor.sh`는 이후 **B4-2에서 그대로 재사용**합니다.

- B4-2 저장소: https://github.com/hyun02063185-AX-beginner/Codyssey_B4-2

> **현재 상태 (2026-11-11)**
> - OrbStack Ubuntu Machine `b4-lab`(Ubuntu 24.04.5 LTS, x86_64) 생성 및 기본 실행환경 사전검증 완료 → [검증 기록](docs/orbstack-environment.md#9-기본-실행환경-사전검증-기록)
> - **Mission Core는 아직 구현하지 않았습니다.** 사용자/그룹, SSH, UFW, 환경변수, Agent, `monitor.sh`, 로그, cron 모두 미착수입니다.

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
- `monitor.sh` — Mission Core 산출물. 저장소 내 위치는 작성 시 확정.

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
| 사용자 ↔ 그룹 소속 | _(미기입)_ | [확인 필요] | 어느 사용자가 어느 그룹에 속하는지 원문 확인 |
| SSH 포트 | TCP `20022` | [관리자료] | |
| SSH Root 원격 로그인 | 차단 | [관리자료] | `PermitRootLogin` 설정값은 원문 확인 후 확정 |
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
- [ ] [관리자료] 사용자 `agent-admin`, `agent-dev`, `agent-test` 생성
- [ ] [관리자료] 그룹 `agent-common`, `agent-core` 생성
- [ ] [확인 필요] 사용자별 그룹 소속 설정
- [ ] 증빙: `id agent-admin`, `id agent-dev`, `id agent-test`, `getent group agent-common agent-core`

#### 2) 디렉터리 / 파일 권한
- [ ] [관리자료] `upload_files` — `agent-common` R/W (경로·mode [확인 필요])
- [ ] [관리자료] `api_keys` — `agent-core` R/W (경로·mode [확인 필요])
- [ ] [관리자료] `/var/log/agent-app` — `agent-core` R/W (mode [확인 필요])
- [ ] 그룹 외 사용자가 접근할 수 없는지 확인
- [ ] 증빙: `ls -ld <경로>`, `stat <경로>`

#### 3) SSH
- [ ] openssh-server 설치 (사전검증 결과 **미설치**)
- [ ] [관리자료] `Port 20022`
- [ ] [관리자료] Root 원격 로그인 차단
- [ ] `sudo sshd -t` 문법 검사 후 재시작
- [ ] 증빙: `ss -tlnp | grep 20022`, Machine sshd로 `ssh -p 20022` 접속 성공, root 접속 거부
- [ ] OrbStack 기본 SSH(`ssh b4-lab@orb`)가 아닌 미션 sshd 경로로 증빙 ([docs](docs/orbstack-environment.md#5-orbstack-내부-ssh-vs-미션-ssh))
- [ ] [확인 필요] Ubuntu 24.04의 `ssh.socket`(소켓 활성화)이 포트 변경에 미치는 영향 확인

#### 4) 방화벽 (UFW)
- [ ] ufw 설치 (사전검증 결과 **미설치**)
- [ ] [관리자료] `20022/tcp` 허용 — **활성화 전에 먼저 추가**(차단 방지)
- [ ] [관리자료] `15034/tcp` 허용
- [ ] [관리자료] 그 외 인바운드 차단 (default deny incoming)
- [ ] UFW 활성화
- [ ] 증빙: `sudo ufw status verbose`
- [ ] [확인 필요] OrbStack Machine에서 UFW가 실제로 패킷을 차단·허용하는지 검증

#### 5) 환경변수
- [ ] [관리자료] `AGENT_HOME`, `AGENT_PORT`, `AGENT_UPLOAD_DIR`, `AGENT_KEY_PATH`, `AGENT_LOG_DIR` 정의
- [ ] [확인 필요] 각 변수의 값과 적용 위치(로그인 셸 / Agent 실행 환경 / cron 환경) — **cron은 로그인 셸 환경변수를 상속하지 않음에 주의**
- [ ] 증빙: Agent·`monitor.sh` 실행 환경에서 실제 값 출력

#### 6) Agent(제공 Python 앱) 기동
- [ ] 제공 앱을 **수정하지 않고** 그대로 배치
- [ ] [확인 필요] 실행 사용자·명령·상주 방식
- [ ] [관리자료] Boot Sequence 5단계 모두 OK
- [ ] [관리자료] `Agent READY` 출력
- [ ] [관리자료] `0.0.0.0:15034` LISTEN — `ss -tlnp | grep 15034`
- [ ] 증빙: 기동 로그, `ps`, `ss` 결과

#### 7) `monitor.sh` (Bash)
- [ ] Bash로 작성, `bash -n monitor.sh` 문법 검사
- [ ] [관리자료] 점검: Agent 프로세스
- [ ] [관리자료] 점검: 포트(15034 LISTEN)
- [ ] [관리자료] 점검: 방화벽 상태
- [ ] [관리자료] 점검: CPU / MEM / DISK 사용량 (임계값 [확인 필요])
- [ ] [관리자료] 프로세스·포트 점검 실패 시 `exit 1`
- [ ] [관리자료] 방화벽 비활성 시 `WARNING` 출력
- [ ] [확인 필요] 출력 형식, 배치 경로·소유자·실행 권한
- [ ] 증빙: 정상 / 프로세스 중지 / 방화벽 비활성 각 상황의 출력과 `echo $?`

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
