# Codyssey B4-1 — Linux 서버 기본 환경 구성

코디세이 B4-1 미션 저장소입니다.
OrbStack Ubuntu **Linux Machine**을 실습 서버로 사용하며, 여기서 만든 Linux 환경과 `monitor.sh`는 이후 **B4-2에서 그대로 재사용**합니다.

- B4-2 저장소: https://github.com/hyun02063185-AX-beginner/Codyssey_B4-2

> **현재 상태 (2026-11-14, 작업 22 최종 마감)** — Mission Core 13개 항목 **13/13 PASS**(logrotate 타이머 2026-11-14 00:00:01 KST 실행·성공 확인, 로그가 9 MiB 미만이라 순환은 미발생=정상). 제출용 화면 캡처 10장(S1~S10) 중 **S1·S2 화면은 Owner 촬영본 등록**([증빙](docs/evidence/screenshots/README.md); Mac 실제 TCP 연결 시험은 별도 확인 필요), **S3~S10은 Owner 촬영 대기**([체크리스트](docs/b4-1-final-evidence.md#4-제출-증빙-화면-구성-10장--s1s2-화면-확보-s3s10-owner-촬영-대기)). 전체 미션 완료 판정은 Owner 최종 검수 이후입니다.
>
> | 영역 | 상태 | 상세 |
> |---|---|---|
> | Ubuntu Machine `b4-lab` (24.04.5, x86_64) | PASS | [환경 문서 9장](docs/orbstack-environment.md#9-기본-실행환경-사전검증-기록) |
> | SSH 20022 + Root 차단 | PASS | [10장](docs/orbstack-environment.md#10-ssh-20022-구성-및-검증-기록) |
> | UFW (deny in / allow out, 20022·15034만 허용) | PASS | [11장](docs/orbstack-environment.md#11-ufw-방화벽-구성-및-검증-기록) |
> | 사용자 3·그룹 2(공식 구성: common = admin·dev·test, core = admin·dev), `/opt/agent-app` 권한·ACL | PASS | [공식 정합성](docs/b4-1-official-alignment.md) |
> | 환경변수 5개 (`AGENT_KEY_PATH=/opt/agent-app/api_keys` — 제공 Agent 요구, 과제 설명의 `t_secret.key`와 다름) | PASS | [수행 내역서 §3](docs/b4-1-final-evidence.md) |
> | 제공 Agent: Boot 5/5 `[OK]`, `Agent READY`, `0.0.0.0:15034` LISTEN, 정상 종료 (수동 실행, 상주 서비스 아님) | PASS | [Agent 실행환경](docs/b4-1-agent-runtime.md) |
> | `monitor.sh` (`agent-dev:agent-core 0750`): Agent 실행 시 `exit 0`, 중지 시 `exit 1`, 방화벽 WARNING은 exit 영향 없음, 임계값 CPU>20/MEM>10/DISK>80 | PASS | [monitor 기록](docs/b4-1-monitor.md) |
> | `monitor.log` 공식 형식 `[시각] PID:… CPU:…% MEM:…% DISK_USED:…%` (실행당 1줄; 과거 상세 줄과 공존) | PASS | [monitor 기록 작업 18](docs/b4-1-monitor.md#작업-18-공식-로그-형식agent-정상-모니터링) |
> | 로그 순환: `size 9M`·`rotate 9`(최대 10개). 절대 최대 크기 보장 아님(일 1회 검사) | PASS (타이머 실행 확인, 순환 미발생=정상) | [로그 순환](docs/b4-1-log-rotation.md) |
> | `agent-admin` cron 매분 자동 실행 | PASS | [cron 기록](docs/b4-1-cron.md) |
> | 환경 복구 자동화 (`bootstrap-orbstack.sh`) | PASS (`check --no-run` → `diff=0`) | [복구 자동화](docs/b4-1-recovery.md) |
>
> **제출 문서:** [요구사항 수행 내역서](docs/b4-1-final-evidence.md)(항목별 요구·설정·명령·결과·증빙 위치·판정, 증빙 절차) · [B4-2 인수인계](docs/b4-2-environment-handoff.md) · 실측 원본 [최종 회귀 출력](docs/evidence/task22-closeout-regression.txt)
>
> 남은 사항(Owner): ① 제출용 화면 캡처 촬영 ② 공식 원문 최종 대조·완료 판정.
>
> **교육장 Mac 초기화 시 복구:** GitHub 저장소(`git clone` → `scripts/bootstrap-orbstack.sh apply`)로 SSH 20022·UFW·계정·권한·환경변수·`monitor.sh`·logrotate·cron이 복구됩니다. **수동 준비물**(저장소에 없음): ① 제공 Agent ZIP/바이너리(`/opt/agent-app/bin/agent-app-linux-x86`, `root:agent-core 0750`; 해시·방법은 [Agent 실행환경](docs/b4-1-agent-runtime.md)) ② Mac의 SSH 키쌍·사용자 비밀번호 ③ 이전 Machine 안의 `monitor.log` 이력. 확인: `scripts/bootstrap-orbstack.sh check --no-run`(Agent 항목만 PEND). 이 README의 아래 3장 이후는 작업 중 작성한 체크리스트이며, 현재 상태는 위 표와 수행 내역서가 우선합니다.

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
    ├── b4-1-agent-runtime.md          # 환경변수·Agent 실행·정상 모니터링 기록(작업 17·18)
    ├── b4-1-monitor.md                # monitor.sh·monitor.log 구현·검증
    ├── b4-1-log-rotation.md           # logrotate 순환 설계·검증
    ├── b4-1-cron.md                   # cron 매분 실행 검증
    ├── b4-1-recovery.md               # 환경 복구 자동화와 재구축 검증
    ├── b4-1-final-evidence.md         # 제출용 요구사항 수행 내역서·증빙 목록
    └── b4-2-environment-handoff.md    # B4-2 환경 인수인계
```

**저장소에 없는 것:** 제공 Agent 바이너리·ZIP(수동 배포, 파일명·해시·방법만 [기록](docs/b4-1-agent-runtime.md)). 대체 구현은 하지 않습니다.

## 3. B4-1 Mission Core 체크리스트

### 3.1 작업 원칙

- **제공 Python 앱(Agent)은 수정 대상이 아니라 실행 대상입니다.** 앱 코드는 고치지 않고, 앱이 요구하는 사용자·권한·환경변수·포트 조건을 Linux 환경 쪽에서 맞춥니다.
- **`monitor.sh`는 Bash로 작성합니다.** (shebang `#!/bin/bash` 또는 `#!/usr/bin/env bash`)
- 제공 바이너리/앱의 architecture·실행 조건은 추정하지 않고 실제 확인(`uname -m`, `file`, 실행 결과)한 값만 기록합니다.
- 모든 설정은 수동으로 먼저 수행·검증한 뒤 `scripts/bootstrap-orbstack.sh`로 옮겼고(작업 14), 새 Machine에서 재현됨을 확인했습니다.

### 3.2 값의 구분과 출처

**출처:** 3.3 요약표의 [관리자료] 값은 기존 Codyssey 관리 자료의 값이며, 그룹 구성·임계값·`monitor.sh` 소유권·로그 형식·테스트 키 문자열은 Owner가 제공한 공식 요구값(작업 16~19)으로 갱신됐습니다. 미션 원문 전체와의 최종 대조는 Owner 검수에서 합니다.

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
| 사용자 ↔ 그룹 소속 | `agent-common` = admin·dev·test, `agent-core` = admin·dev (**적용됨**) | [공식 요구] | 작업 16 |
| SSH 포트 | TCP `20022` | [관리자료] | **적용·검증 완료** (22 미사용) |
| SSH Root 원격 로그인 | 차단 | [관리자료] | **적용·검증 완료** — `PermitRootLogin no` |
| SSH 운영 방식 | `ssh.socket` 비활성 + `ssh.service` 상시 실행, 설정은 `/etc/ssh/sshd_config.d/10-b4-mission.conf` | [설계] | 이유: [docs 10.2](docs/orbstack-environment.md#102-운영-방식-결정-socket-비활성--sshservice-상시-실행-설계) |
| SSH 비밀번호 인증 | 기본값(`yes`) 유지 | [확인 필요] | 공식 요구 여부 확인 |
| 방화벽 인바운드 | TCP `20022`, `15034`**만** 허용 | [관리자료] | 그 외 인바운드 차단 |
| 방화벽 아웃바운드 정책 | allow | [설계] | 원문 요구가 있으면 그 값을 따름 → 확인 필요 |
| `upload_files` 디렉터리 | `agent-common` 그룹 R/W | [관리자료] | 경로·소유자·숫자 mode는 [확인 필요] |
| `api_keys` 디렉터리 | `agent-core` 그룹 R/W (`root:agent-core 2770`+ACL) | [공식 요구] | `AGENT_KEY_PATH`는 이 디렉터리, 안에 `secret.key`(제공 Agent 요구) |
| `/var/log/agent-app` | `agent-core` 그룹 R/W | [관리자료] | 소유자·숫자 mode는 [확인 필요] |
| 환경변수 | `AGENT_HOME`, `AGENT_PORT`, `AGENT_UPLOAD_DIR`, `AGENT_KEY_PATH`, `AGENT_LOG_DIR` | [관리자료] | 각 변수의 값·적용 범위는 [확인 필요] |
| Agent 기동 성공 기준 | Boot Sequence 5단계 모두 OK → `Agent READY` 출력 → `0.0.0.0:15034` LISTEN | [관리자료] | 실행 사용자·상주 방식은 [확인 필요] |
| `monitor.sh` 언어 | Bash | [관리자료] | |
| `monitor.sh` 점검 항목 | 프로세스, 포트, 방화벽, CPU / MEM / DISK | [관리자료] | 임계값 CPU>20/MEM>10/DISK>80 [공식 요구], 로그 형식 공식 |
| `monitor.sh` 실패 처리 | 프로세스·포트 점검 실패 → `exit 1` / 방화벽 비활성 → `WARNING` | [관리자료] | WARNING 시 종료 코드는 [확인 필요] |
| 로그 파일 | `/var/log/agent-app/monitor.log` | [관리자료] | 공식 형식 `[시각] PID:… CPU:…% MEM:…% DISK_USED:…%`(작업 18) |
| 로그 순환 | 최대 10MB, 최대 10개 | [관리자료] | `size 9M`(9 MiB, 십진 10 MB·10 MiB 모두 만족)·활성 1 + 순환본 9 = 최대 10개. 절대 최대 크기 보장 아님 |
| cron | `agent-admin` 계정으로 매분 실행 | [관리자료] | |
| Ubuntu 버전 | 24.04 LTS (`ubuntu:noble`) | [설계] | 원문 지정 버전이 있으면 그 값을 따름 → 확인 필요 |
| Machine 이름 | `b4-lab` | [설계] | |

### 3.4 체크리스트

#### 0) 환경 준비
- [x] [설계] `orb create ubuntu:noble b4-lab`으로 Machine 생성 (2026-11-11)
- [x] `uname -m`(x86_64), `/etc/os-release`(24.04.5 LTS), `python3 --version`(3.12.3), PID 1(systemd), `sudo -n true`, `systemctl --version`(255) 확인 → [검증 기록](docs/orbstack-environment.md#9-기본-실행환경-사전검증-기록)
- [x] 제공 Agent 바이너리: ELF 64-bit x86-64, 동적 라이브러리 해석 확인, SHA256 기록(작업 17). Python 버전 요구는 없음(독립 실행 파일)

#### 1) 사용자 / 그룹
- [x] [관리자료] 사용자 `agent-admin`, `agent-dev`, `agent-test` 생성 (홈 `750`, 비밀번호 잠김, sudo 없음. 예외: `agent-admin`은 `ufw status` 한 명령만 sudo 허용 — 작업 19)
- [x] [관리자료] 그룹 `agent-common`(GID 1000), `agent-core`(GID 1001) 생성
- [x] 사용자별 그룹 소속 설정 — **공식 구성**(작업 16): `agent-common` = admin·dev·test, `agent-core` = admin·dev
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
- [x] `AGENT_KEY_PATH=/opt/agent-app/api_keys`(디렉터리), `api_keys/secret.key` 내용은 공식 실습 문자열 `agent_api_key_test` 한 줄(`root:agent-core 0640`; 실제 비밀키 아님). 제공 Agent 실행은 PENDING
- [x] 환경변수를 실제 Agent가 사용하는지 검증 — 작업 17: Agent가 `AGENT_KEY_PATH`를 디렉터리로 검증(과제 설명의 `t_secret.key` 파일 경로는 거부됨)
- [x] 변수 값·적용 위치: 파일 `/etc/default/agent-app`을 Agent 실행·`monitor.sh`가 명시 로드(작업 17·18). 로그인 셸에는 자동 적용되지 않음
- [x] 증빙: Agent·`monitor.sh` 실행 시 값 확인([본환경 회귀 출력](docs/evidence/task21-b4-lab-regression.txt) `## env`). 화면 캡처는 CAPTURE PENDING

#### 6) Agent(제공 Python 앱) 기동
- [x] 제공 앱을 **수정하지 않고** 그대로 배치 (`/opt/agent-app/bin/`, `root:agent-core 0750`, SHA256 일치)
- [x] 실행 사용자·명령: `agent-admin`이 `/etc/default/agent-app`을 명시 로드해 수동 실행([수행 내역서 §2.5](docs/b4-1-final-evidence.md)). 상주 방식(systemd 등)은 이번 범위 밖
- [x] [관리자료] Boot Sequence 5단계 모두 OK (작업 17)
- [x] [관리자료] `Agent READY` 출력 (작업 17)
- [x] [관리자료] `0.0.0.0:15034` LISTEN — `ss -tlnp | grep 15034`, 소유 PID = Agent 자식 프로세스 (작업 17·18)
- [x] 증빙: 기동 로그·`ss` 결과([회귀 출력](docs/evidence/task21-b4-lab-regression.txt) `## agent run`). 화면 캡처는 CAPTURE PENDING

#### 7) `monitor.sh` (Bash)
- [x] Bash로 작성, `bash -n` 문법 검사 PASS → [bin/monitor.sh](bin/monitor.sh), 상세 [docs/b4-1-monitor.md](docs/b4-1-monitor.md)
- [x] [관리자료] 점검: Agent 프로세스 — `AGENT_PROCESS_PATTERN=^/opt/agent-app/bin/agent-app-linux-x86`, 실제 Agent(부모·자식 PID) 판정 PASS(작업 18)
- [x] [관리자료] 점검: 포트(15034 LISTEN) — 미LISTEN·바인딩·소유 PID 일치/불일치/확인 불가 판정. 실제 Agent로 소유 PID 일치 확인(작업 18)
- [x] [관리자료] 점검: 방화벽 상태 — 구현. `agent-admin`이 `sudo -n /usr/sbin/ufw status`(최소 권한 sudoers)로 실제 상태 판정: 활성 OK / 비활성 WARNING(exit 0 유지) / 권한 거부 UNKNOWN (작업 19)
- [x] [관리자료] 점검: CPU / MEM / DISK 사용량 — 수집·계산 PASS, 경고 임계값 CPU>20% / MEM>10% / DISK>80%(공식, 경계 `>` 엄격)
- [x] [관리자료] 프로세스·포트 점검 실패 시 `exit 1` (설정·수집 오류는 exit 2, 방화벽 WARNING은 exit 0 유지)
- [x] [관리자료] 방화벽 비활성 시 `WARNING` 출력 — 실제 UFW 비활성 상태에서 검증 PASS(테스트 Machine, 작업 19; 본환경에서는 비활성화하지 않음)
- [x] 배치 경로·소유자·권한: `/opt/agent-app/bin/monitor.sh` `agent-dev:agent-core 0750`(공식, 작업 16; cron 계정 `agent-admin`은 `agent-core` 그룹 권한으로 실행). 출력 형식은 임시 형식
- [x] 증빙: 정상(exit 0, Agent 실행 중) / 프로세스 중지(exit 1) 실측(작업 18). 방화벽 비활성 WARNING도 실측(작업 19)

#### 8) 로그
- [x] [관리자료] `/var/log/agent-app/monitor.log`에 기록 — 스크립트가 직접 append(cron 리디렉션 비의존), `agent-admin:agent-core 0660`, 3회 누적·터미널과 동일 PASS ([상세](docs/b4-1-monitor.md#21-monitorlog-누적-기록-작업-11)). cron 환경 실측·Agent 정상 기록은 PENDING
- [x] [관리자료] 최대 10MB / 최대 10개로 순환 — logrotate `size 9M`(9 MiB, 십진 10 MB·10 MiB 모두 만족), 활성 1 + 순환본 9 = 최대 10개, 일 1회 검사라 엄격한 최대 크기 보장은 아님(작업 20: 서비스 순환·13회 연속·동시 실행 무손실 PASS, 타이머 2026-11-14 실행·성공 확인, 실제 순환은 로그 9 MiB 도달 시) ([상세](docs/b4-1-log-rotation.md)). 검사는 일 1회라 **엄격한 최대 크기 보장은 아님**. 실제 크기 도달 순환은 테스트 Machine에서 입증, 크기·개수의 원문 대조는 Owner 검수
- [x] `agent-admin`이 로그에 쓸 수 있는지 확인 — 실제 cron 세션에서도 확인(작업 13·18)
- [x] 로그 라인 형식 — 공식 `[YYYY-MM-DD HH:MM:SS] PID:… CPU:…% MEM:…% DISK_USED:…%`(작업 18). 이전 상세 로그는 같은 파일에 그대로 남아 두 형식이 공존
- [x] 증빙: `tail` 결과(확보: 3회 실행 후 로그, [상세](docs/b4-1-monitor.md#52-monitorlog-기록-테스트-작업-11-실측)), 순환 설정 내용(적용: `/etc/logrotate.d/agent-app`, [config/etc-logrotate.d-agent-app](config/etc-logrotate.d-agent-app))

#### 9) cron
- [x] [관리자료] `agent-admin` 계정의 crontab에 매분(`* * * * *`) `monitor.sh` 등록 ([cron 기록](docs/b4-1-cron.md))
- [x] cron 서비스 동작 확인 (`cron 3.0pl1-184ubuntu2`, enabled·active, `agent-admin` 세션 정상 개설)
- [x] 절대 경로 사용, 환경변수는 스크립트가 `/etc/default/agent-app`을 직접 로드(cron 환경에는 `AGENT_*` 없음을 관찰로 확인)
- [x] 증빙: `sudo crontab -u agent-admin -l`, 매분 로그 줄 수 증가(공식 형식 1줄/실행) — [수행 내역서 §2.11](docs/b4-1-final-evidence.md)

#### 10) 마무리
- [x] 수동 설정을 `scripts/bootstrap-orbstack.sh`로 재현 가능하게 정리 (작업 14, [복구 자동화](docs/b4-1-recovery.md))
- [x] 새 Machine(`b4-recovery-test`)에서 bootstrap 실행 → 재검증 PASS(`b4-lab`과 동일, 반복 실행 안전). Agent는 수동 배포·실행 검증(작업 17·18)
- [x] 제출 수행 내역서·증빙 목록 정리 → [b4-1-final-evidence.md](docs/b4-1-final-evidence.md) (공식 제출 원문은 미확인; 터미널 캡처 자체는 사용자가 찍어야 함, 목록은 §4)
- [x] B4-2에서 사용할 값(Machine 이름, 사용자, 포트, `monitor.sh` 경로) 기록 → [b4-2-environment-handoff.md](docs/b4-2-environment-handoff.md)

## 4. 교육장 Mac 초기화 후 복구 (요약)

**"상태의 원본은 이 GitHub 저장소"** 입니다. Mac 쪽에서는 sudo를 쓰지 않고, 필요한 권한 작업은 Machine 안에서만 수행합니다. 자세한 설명·검증 결과는 [docs/b4-1-recovery.md](docs/b4-1-recovery.md).

| | 초기화로 사라짐 | GitHub로 재현됨 |
|---|---|---|
| 내용 | 기존 Machine과 그 안의 데이터(`monitor.log`·순환본, 업로드 파일, 저장소에 없는 수동 변경), 사용자 비밀번호, Mac의 SSH 키쌍, push하지 않은 로컬 커밋 | OrbStack Machine 생성, SSH 20022·Root 차단, UFW, 사용자·그룹·소속, `/opt/agent-app` 권한·ACL, 환경변수 파일, `monitor.sh`, `monitor.log` 권한, logrotate, `agent-admin` cron |
| 복구 불가(저장소에 없음) | SSH 개인키·API 키·비밀번호, **제공 Agent 바이너리·ZIP**(수동 배포, 파일명·해시·방법만 기록) | |

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
