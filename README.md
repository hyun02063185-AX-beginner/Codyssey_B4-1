# Codyssey B4-1 — Linux 서버 기본 환경 구성

코디세이 B4-1 미션 저장소입니다.
OrbStack Ubuntu **Linux Machine**을 실습 서버로 사용하며, 여기서 만든 Linux 환경과 `monitor.sh`는 이후 **B4-2에서 그대로 재사용**합니다.

- B4-2 저장소: https://github.com/hyun02063185-AX-beginner/Codyssey_B4-2

> 현재 상태: **저장소 문서만 구성된 단계**입니다.
> Ubuntu Machine 생성, 사용자/그룹, SSH, UFW, cron, `monitor.sh` 등 Mission Core는 아직 구현하지 않았습니다.

---

## 1. 실습 환경

| 항목 | 내용 |
| --- | --- |
| Host | 코디세이 교육장 Mac (macOS) |
| Host 제약 | macOS host에서 `sudo` 사용 불가 |
| Host 초기화 | 교육장 Mac은 주기적으로 초기화됨 → 로컬 상태는 언제든 사라질 수 있음 |
| 가상화 도구 | OrbStack (설치되어 있음) |
| **B4-1 기본 실습환경** | **OrbStack Ubuntu Linux Machine** |
| 사용하지 않는 것 | Docker Container(기본 실습환경 아님), AWS EC2(기본환경 아님) |

- host에서는 `sudo`가 안 되지만, OrbStack Linux Machine **내부**에서는 Linux 관리자 권한(`sudo`)을 사용할 수 있으므로 서버 설정 실습이 가능합니다.
- Docker Container 대신 Linux Machine을 쓰는 이유, Ubuntu 버전 고정, OrbStack 내부 SSH와 미션 SSH의 차이는 [docs/orbstack-environment.md](docs/orbstack-environment.md)에 정리되어 있습니다.

## 2. 저장소 구조

```
.
├── README.md                     # 미션 개요, 환경, Mission Core 체크리스트, 복구 흐름 요약
├── docs/
│   └── orbstack-environment.md   # OrbStack 역할, Container vs Machine, 버전 고정, SSH 구분, 복구 흐름 상세
└── scripts/
    └── README.md                 # scripts/ 디렉터리 용도, 향후 bootstrap-orbstack.sh 역할
```

향후 추가 예정(아직 없음):

- `scripts/bootstrap-orbstack.sh` — 교육장 Mac 초기화 후 OrbStack Ubuntu Machine을 같은 상태로 재구성하는 스크립트. 역할과 범위는 [scripts/README.md](scripts/README.md) 참고.
- `monitor.sh` — Mission Core 산출물. 저장소 내 위치는 작성 시 확정.

## 3. B4-1 Mission Core 체크리스트

### 3.1 작업 원칙

- **제공 Python 앱은 수정 대상이 아니라 실행 대상입니다.** 앱 코드는 고치지 않고, 앱이 요구하는 사용자·권한·환경변수·포트 조건을 Linux 환경 쪽에서 맞춥니다.
- **`monitor.sh`는 Bash로 작성합니다.** (shebang `#!/bin/bash` 또는 `#!/usr/bin/env bash`)
- 제공 바이너리/앱의 architecture·실행 조건은 추정하지 않고 실제 확인(`uname -m`, `file`, 실행 결과)한 값만 기록합니다.
- 모든 설정은 수동으로 먼저 수행·검증한 뒤 `scripts/bootstrap-orbstack.sh`로 옮깁니다.

### 3.2 값의 구분

체크리스트의 각 값은 아래 셋 중 하나로 표시합니다. **설계 선택 값을 공식 값처럼 적지 않습니다.**

| 표시 | 의미 |
| --- | --- |
| **[공식]** | B4-1 공식 요구사항에 명시된 값 |
| **[설계]** | 공식 요구사항에 없고, 이 저장소의 환경 설계상 선택한 값 |
| **[확인 필요]** | 공식 값이 아직 이 문서에 옮겨지지 않았거나, OrbStack 환경에서 그대로 동작하는지 검증되지 않은 항목 |

### 3.3 요구사항 요약표

| 영역 | 요구 값 | 구분 | 비고 |
| --- | --- | --- | --- |
| SSH 포트 | `20022` | [공식] | 기본 22 대신 사용 |
| 방화벽 허용 포트 | `20022/tcp`, `15034/tcp` | [공식] | |
| 방화벽 기본 정책 | 인바운드 deny / 아웃바운드 allow | [설계] | 공식 요구가 있으면 그 값을 따름 → 확인 필요 |
| 포트 15034의 용도 | _(공식 문서 값 기입)_ | [확인 필요] | Agent 앱 포트인지 공식 문서로 확인 |
| 사용자 계정 | _(공식 문서 값 기입)_ | [확인 필요] | |
| 그룹 | _(공식 문서 값 기입)_ | [확인 필요] | |
| 디렉터리·파일 권한 | _(공식 문서 값 기입)_ | [확인 필요] | 경로·소유자·그룹·모드 |
| 환경변수 | _(공식 문서 값 기입)_ | [확인 필요] | 이름·값·적용 범위(사용자/서비스) |
| Agent 기동 방식 | _(공식 문서 값 기입)_ | [확인 필요] | 실행 사용자·명령·상주 방식 |
| `monitor.sh` 점검 항목 | _(공식 문서 값 기입)_ | [확인 필요] | |
| 로그 경로·형식 | _(공식 문서 값 기입)_ | [확인 필요] | |
| cron 주기·실행 사용자 | _(공식 문서 값 기입)_ | [확인 필요] | |
| Ubuntu 버전 | _(미정)_ | [설계] / [확인 필요] | 공식 지정 버전이 있으면 그 값을 따름 |
| Machine 이름 | _(미정)_ | [설계] | |

### 3.4 체크리스트

#### 0) 환경 준비
- [ ] [설계] Ubuntu 버전을 명시해 OrbStack Ubuntu Linux Machine 생성 (버전 고정 이유: [docs](docs/orbstack-environment.md#4-ubuntu-버전-고정))
- [ ] `uname -m`, `cat /etc/os-release`, `python3 --version` 결과 기록
- [ ] 제공 바이너리/앱이 있다면 `file`로 실제 architecture 확인 후 기록 (추정 금지)

#### 1) 사용자 / 그룹
- [ ] [확인 필요] 공식 요구 사용자 계정 생성
- [ ] [확인 필요] 공식 요구 그룹 생성 및 사용자 소속
- [ ] 증빙: `id <user>`, `getent group <group>`

#### 2) 디렉터리 / 파일 권한
- [ ] [확인 필요] 공식 요구 경로 생성
- [ ] [확인 필요] 소유자·그룹·권한(mode) 설정
- [ ] 증빙: `ls -ld <경로>`, `stat <경로>`

#### 3) SSH
- [ ] SSH 서버(openssh-server) 설치·동작 확인
- [ ] [공식] `sshd_config`의 `Port`를 `20022`로 설정
- [ ] [확인 필요] 그 외 공식 요구 SSH 설정(root 로그인, 인증 방식 등) 반영
- [ ] 설정 문법 검사 `sudo sshd -t` 후 재시작
- [ ] 증빙: `ss -tlnp | grep 20022`, **Machine의 sshd로** `ssh -p 20022` 접속 성공
- [ ] [확인 필요] OrbStack 기본 SSH(`ssh <machine>@orb`)가 아닌 미션 sshd로 접속했음을 구분해 증빙 ([docs](docs/orbstack-environment.md#5-orbstack-내부-ssh-vs-미션-ssh))

#### 4) 방화벽 (UFW)
- [ ] UFW 설치
- [ ] [공식] `20022/tcp` 허용 — **활성화 전에 먼저 추가**(차단 방지)
- [ ] [공식] `15034/tcp` 허용
- [ ] [설계] 기본 정책: 인바운드 deny, 아웃바운드 allow (공식 요구 확인 필요)
- [ ] UFW 활성화
- [ ] 증빙: `sudo ufw status verbose`
- [ ] [확인 필요] OrbStack Machine에서 UFW(iptables/nftables)가 실제로 패킷을 차단·허용하는지 검증

#### 5) 환경변수
- [ ] [확인 필요] 공식 요구 환경변수 이름·값 확인
- [ ] [확인 필요] 적용 위치 결정 (로그인 셸 / Agent 실행 환경 / cron 환경) — **cron은 로그인 셸 환경변수를 상속하지 않음에 주의**
- [ ] 증빙: Agent·`monitor.sh` 실행 환경에서 실제 값 출력

#### 6) Agent(제공 Python 앱) 기동
- [ ] 제공 앱을 **수정하지 않고** 그대로 배치
- [ ] [확인 필요] 공식 요구 실행 사용자·명령으로 기동
- [ ] [확인 필요] 기동 유지 방식(포그라운드 / 백그라운드 / systemd 등) 공식 요구 확인
- [ ] [확인 필요] 15034 포트 리스닝 여부 확인: `ss -tlnp | grep 15034`
- [ ] 증빙: 프로세스(`ps`)·포트·응답 확인

#### 7) `monitor.sh` (Bash)
- [ ] Bash로 작성 (`bash -n monitor.sh` 문법 검사)
- [ ] [확인 필요] 공식 요구 점검 항목·출력 형식 구현
- [ ] [확인 필요] 공식 요구 경로·소유자·실행 권한 설정
- [ ] 수동 실행 결과 증빙

#### 8) 로그
- [ ] [확인 필요] 공식 요구 로그 경로·파일명 확인
- [ ] [확인 필요] 로그 파일 소유자·권한 설정 (cron 실행 사용자가 쓸 수 있어야 함)
- [ ] [확인 필요] 로그 형식(타임스탬프 등)·누적 방식(append) 확인
- [ ] 증빙: `tail` 결과

#### 9) cron
- [ ] [확인 필요] 공식 요구 주기·실행 사용자로 `monitor.sh` 등록
- [ ] cron 서비스 동작 확인: `systemctl status cron`
- [ ] 절대 경로 사용, 필요한 환경변수를 crontab 또는 스크립트에서 명시
- [ ] 증빙: `crontab -l`(해당 사용자), 주기에 맞춰 로그가 누적되는 결과

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
3. **고정한 Ubuntu 버전으로** OrbStack Ubuntu Machine 재생성
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
- B4-1에서 정한 값(Machine 이름, Ubuntu 버전, 사용자명, 포트, `monitor.sh` 경로 등)은 B4-2에서 바꾸지 않는 것을 원칙으로 하며, 변경 시 이 README에 기록합니다.
