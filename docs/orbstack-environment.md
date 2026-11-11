# OrbStack 실습 환경

B4-1 / B4-2 실습환경을 OrbStack Ubuntu Linux Machine으로 구성하는 이유와, 교육장 Mac 초기화 후 복구하는 방법을 정리합니다.

> 이 문서는 **환경 설계 문서**입니다. Machine `b4-lab`은 생성·사전검증까지 완료했고(9장), Mission Core 설정은 아직 적용하지 않았습니다.
> 명령 예시는 계획 단계의 참고용이며, 실제 적용 시 결과를 확인하고 이 문서를 갱신합니다.
> 공식 요구사항 값과 설계 선택 값의 구분은 [README 3.2](../README.md#32-값의-구분)를 따릅니다.

---

## 1. 제약 조건

| 제약 | 영향 |
| --- | --- |
| 교육장 Mac에서 host `sudo` 사용 불가 | macOS 자체에 서버 설정(사용자, 방화벽, sshd 등)을 적용할 수 없음 |
| 교육장 Mac 주기적 초기화 | 로컬 파일·OrbStack Machine이 사라질 수 있음 → 재현 가능한 스크립트와 문서가 필요 |
| B4-1 환경을 B4-2에서 재사용 | 일회성 환경이 아니라 "다시 만들 수 있는 동일한 환경"이어야 함 |
| AWS EC2는 기본환경으로 사용하지 않음 | 로컬 OrbStack에서 완결되도록 구성 |

## 2. OrbStack의 역할

OrbStack은 macOS에서 경량 Linux VM을 실행하는 도구이며, 두 가지 형태의 Linux 실행 환경을 제공합니다.

- **Docker Container** 실행 (Docker 엔진 대체)
- **Linux Machine** 실행 (Ubuntu 등 배포판 전체를 가진 경량 VM)

B4-1에서는 OrbStack을 **"host sudo 없이도 root 권한을 가진 Ubuntu 서버를 로컬에 띄우는 도구"** 로 사용합니다.
host(macOS)에는 아무 설정도 하지 않고, 모든 서버 설정은 Machine 내부에서 수행합니다.

## 3. Docker Container vs Linux Machine

| 항목 | Docker Container | OrbStack Linux Machine |
| --- | --- | --- |
| 목적 | 단일 애플리케이션 패키징·실행 | 완전한 Linux 시스템처럼 사용 |
| init / 서비스 관리 | 보통 PID 1이 애플리케이션, systemd 없음 | systemd 기반으로 서비스(`sshd`, `cron` 등) 관리 가능 |
| 상태 수명 | 컨테이너 재생성 시 변경사항 소실이 기본 | Machine을 지우기 전까지 상태 유지 |
| 사용자/그룹·권한 실습 | 가능은 하나 이미지 재빌드 시 초기화 | 일반 서버와 동일하게 실습 |
| SSH / 방화벽 / cron | 별도 구성 필요, 실제 서버 운영 방식과 차이 큼 | 실제 Ubuntu 서버와 유사한 방식으로 설정 |
| B4-1 적합성 | 낮음 | **높음 → 기본 실습환경으로 선택** |

정리하면, B4-1의 Mission Core(사용자/그룹, 권한, 환경변수, SSH, UFW, Agent 기동, cron, `monitor.sh`)는 **"장기 실행되는 서버의 운영 설정"** 이므로, 애플리케이션 단위인 Container보다 시스템 단위인 Linux Machine이 맞습니다.

> **확인 필요:** UFW(iptables/nftables) 등 커널 기능이 OrbStack Machine에서 기대대로 동작하는지는 실제 Machine 생성 후 검증하고 결과를 이 문서에 기록합니다.

## 4. Ubuntu 버전 고정

`orb create ubuntu`처럼 버전을 생략하면 OrbStack은 **그 시점의 최신 안정 버전**으로 Machine을 만듭니다(`orb create --help`에 명시됨). 교육장 Mac은 주기적으로 초기화되어 Machine을 여러 번 다시 만들게 되므로, 버전을 생략하면 재생성할 때마다 다른 Ubuntu가 설치될 수 있습니다.

버전을 고정해야 하는 이유:

- **재현성:** 초기화 전후, B4-1과 B4-2 사이에 같은 환경을 보장합니다.
- **Python 버전:** 제공 Python 앱은 수정하지 않고 실행만 하므로, 앱이 Ubuntu 기본 `python3` 버전에 맞아야 합니다. Ubuntu 버전이 바뀌면 `python3` 버전도 바뀝니다.
- **패키지·설정 차이:** openssh-server, ufw, cron의 기본 설정과 서비스 동작(예: sshd 소켓 활성화 여부)이 Ubuntu 버전마다 다를 수 있어, `bootstrap-orbstack.sh`의 결과가 달라질 수 있습니다.

적용 방식 (아직 실행하지 않음):

```bash
orb create ubuntu:noble b4-lab   # 24.04 LTS로 고정
```

| 항목 | 값 | 구분 |
| --- | --- | --- |
| 고정할 Ubuntu 버전 | **24.04 LTS (`ubuntu:noble`)** — 생성 결과 24.04.5 LTS | [설계] — 원문 지정 버전이 있으면 그 값을 따름 → **확인 필요** |
| Machine 기본 `python3` | 3.12.3 | 실측 (9장) |
| 제공 Python 앱의 Python 요구 버전 | _(미확인)_ | **확인 필요** |

> 주의: `ubuntu:noble`은 메이저 버전(24.04)만 고정합니다. 포인트 릴리스(24.04.x)와 패키지 버전은 재생성 시점에 따라 달라질 수 있으므로, 재생성 후 9장의 검증을 다시 수행해 차이를 기록합니다.

> 참고: 이 교육장 Mac의 host 아키텍처는 `x86_64`이며, OrbStack 2.0.5의 `orb create --help` 기준 지원 Machine 아키텍처는 `amd64`, `i386`입니다. 이것은 **host 정보**일 뿐이며, 제공 바이너리/앱의 architecture는 별도로 `file` 명령으로 확인합니다(추정하지 않음).

## 5. OrbStack 내부 SSH vs 미션 SSH

OrbStack에는 자체 SSH 접속 경로가 있습니다. 이것은 **미션에서 요구하는 SSH(20022)와 다른 경로**이므로 구분해야 합니다.

| 항목 | OrbStack 내부 SSH | 미션 SSH |
| --- | --- | --- |
| 접속 예 | `ssh <machine>@orb` / `orb -m <machine>` | `ssh -p 20022 <user>@<machine 주소>` |
| 서버 | OrbStack이 제공하는 SSH 프록시 (host `127.0.0.1:32222`, `~/.orbstack/ssh/config`) | Machine 내부 openssh-server (`sshd`) |
| 인증 키 | `~/.orbstack/ssh/id_ed25519` (OrbStack 자동 생성) | 미션 요구 방식에 따름 |
| `sshd_config` 영향 | 받지 않음 (확인 필요) | 받음 — `Port 20022` 등 |
| UFW 영향 | 받지 않음 (확인 필요) | 받음 — `20022/tcp` 허용 필요 |
| 용도 | 관리용 접근, 설정 실수 시 복구 경로 | **미션 요구사항 충족·증빙 대상** |

주의 사항:

- `ssh <machine>@orb`로 접속이 된다고 해서 **미션 SSH가 동작하는 것은 아닙니다.** 미션 증빙은 반드시 `-p 20022`로 Machine의 `sshd`에 접속한 결과로 남깁니다.
- 반대로, sshd 포트 변경이나 UFW 설정을 잘못해 미션 SSH가 막혀도 `orb -m <machine>`으로 Machine에 들어가 복구할 수 있습니다. (확인 필요)
- Machine 주소(`<machine>.orb.local` 또는 Machine IP)로 host에서 `20022`에 접속할 수 있는지, 그 경로에 UFW가 적용되는지는 **확인 필요**입니다.

## 6. Machine 기본 정보

| 항목 | 값 |
| --- | --- |
| Machine 이름 | `b4-lab` |
| 생성 명령 | `orb create ubuntu:noble b4-lab` (2026-11-11) |
| 배포판 / 버전 | Ubuntu 24.04.5 LTS (Noble Numbat) |
| Machine 아키텍처 (`uname -m`) | `x86_64` (`orb list` 표기 `amd64`) |
| 제공 바이너리/앱 architecture (`file`) | _(확인 전 — 추정하지 않음)_ |
| `python3 --version` | Python 3.12.3 |
| init (PID 1) | systemd 255 (255.4-1ubuntu8.18) |
| 기본 사용자 | macOS 사용자명과 동일한 이름, `sudo` 비밀번호 없이 사용 가능 |
| OrbStack 버전 | 2.0.5 (2026-11-11 `orb version` 기준) |

참고용 명령:

```bash
orb list                                       # Machine 목록
orb create ubuntu:<version> <machine-name>     # Machine 생성 (버전 고정)
orb -m <machine-name>                          # Machine 쉘 진입 (OrbStack 경로)
orb delete <machine-name>                      # Machine 삭제
```

## 7. 교육장 Mac 초기화 후 복구 흐름

원칙: **상태의 원본은 GitHub 저장소**입니다. Machine 내부에서만 수정하고 저장소에 반영하지 않은 설정은 초기화 시 사라진다고 간주합니다.

```
[Mac 초기화]
     │
     ▼
1. OrbStack 동작 확인 ── orb version / orb list
     │                    (OrbStack이 없으면 교육장 안내에 따라 재설치)
     ▼
2. 저장소 clone ─────── git clone https://github.com/hyun02063185-AX-beginner/Codyssey_B4-1.git
     │
     ▼
3. Machine 존재 확인 ── orb list
     │   ├─ 있음 → 4로 (필요 시 재검증만)
     │   └─ 없음 → orb create ubuntu:noble b4-lab
     ▼
4. bootstrap 실행 ───── scripts/bootstrap-orbstack.sh (작성 이후)
     │
     ▼
5. 재검증 ──────────── README의 Mission Core 체크리스트 기준으로 확인
     │                    (SSH는 반드시 -p 20022 경로로 확인)
     ▼
6. B4-2 진행
```

작업 습관:

- Machine 안에서 설정을 바꾸면 **같은 세션 안에** 스크립트/문서에 반영하고 commit·push 합니다.
- 비밀값(비밀번호, 개인키 등)은 저장소에 커밋하지 않습니다. 복구 시 다시 입력하는 방식으로 설계합니다.
- `bootstrap-orbstack.sh`는 여러 번 실행해도 같은 결과가 나오도록(idempotent) 작성합니다.

## 8. B4-1 → B4-2 재사용

- B4-2 저장소: https://github.com/hyun02063185-AX-beginner/Codyssey_B4-2
- B4-2는 B4-1에서 구성한 **Linux 환경과 `monitor.sh`** 가 그대로 있다는 전제로 진행합니다.
- 같은 Mac 세션 안이라면 기존 Machine을 그대로 사용합니다.
- Mac이 초기화된 경우 7장의 흐름으로 B4-1 종료 상태를 복구한 뒤 B4-2를 시작합니다.
- 따라서 B4-1의 완료 조건에는 "Mission Core 충족"뿐 아니라 **"고정한 Ubuntu 버전의 새 Machine에서 bootstrap으로 동일 상태 재현 가능"** 이 포함됩니다.

## 9. 기본 실행환경 사전검증 기록

- 일시: 2026-11-11 16:53 KST
- 대상: `b4-lab` (Ubuntu 24.04.5 LTS)
- 범위: Mission Core 착수 전, Ubuntu 기본 실행환경이 적합한지 **읽기 전용으로** 확인. SSH·UFW·사용자·그룹·Agent·`monitor.sh`·cron 설정은 변경하지 않음.

### 9.1 생성 전 상태

| 명령 | 실제 결과 |
| --- | --- |
| `orb version` | `Version: 2.0.5 (2000500)` |
| `orb list` | (출력 없음 — 기존 Machine 없음) |
| `orb create ubuntu:noble b4-lab` | exit 0 |
| `orb list` (생성 후) | `b4-lab  running  ubuntu  noble  amd64  649.0 MB  192.168.139.18` |

### 9.2 기본 환경 검증

| # | 명령 | 실제 결과 | 판정 | 판정 기준 |
| --- | --- | --- | --- | --- |
| 1 | `orb -m b4-lab uname -m` | `x86_64` | PASS | 아키텍처 확인 가능 |
| 2 | `orb -m b4-lab cat /etc/os-release` | `PRETTY_NAME="Ubuntu 24.04.5 LTS"`, `VERSION_ID="24.04"`, `VERSION_CODENAME=noble` | PASS | 고정한 버전(noble)과 일치 |
| 3 | `orb -m b4-lab python3 --version` | `Python 3.12.3` | PASS | python3 존재. 제공 앱 요구 버전과의 호환은 **확인 필요** |
| 4 | `orb -m b4-lab ps -p 1 -o comm=` | `systemd` | PASS | PID 1이 systemd → 서비스 관리 가능 |
| 5 | `orb -m b4-lab sudo -n true` | (출력 없음), exit 0 | PASS | 비밀번호 없이 sudo 가능 |
| 6 | `orb -m b4-lab systemctl --version` | `systemd 255 (255.4-1ubuntu8.18)` | PASS | systemctl 사용 가능 |

추가 확인 (읽기 전용):

| 명령 | 실제 결과 | 의미 |
| --- | --- | --- |
| `orb -m b4-lab whoami` | macOS 사용자명과 동일 | OrbStack 기본 사용자 |
| `orb -m b4-lab systemctl is-system-running` | `running` | systemd 정상 기동 |
| `dpkg-query -W openssh-server` | `no packages found` | **미설치** → SSH 작업 시 설치 필요 |
| `dpkg-query -W ufw` | `no packages found` | **미설치** → 방화벽 작업 시 설치 필요 |
| `dpkg-query -W cron` | `install ok installed 3.0pl1-184ubuntu2` | 설치됨 |
| `dpkg-query -W logrotate` | `install ok installed 3.21.0-2build1` | 설치됨 |
| `systemctl is-active ssh cron` | `inactive` / `active` | sshd 없음, cron 동작 중 |

### 9.3 결론과 남은 확인 항목

- 기본 실행환경 6개 항목 **모두 PASS**. Mission Core를 진행할 수 있는 Ubuntu + systemd + sudo 환경임을 확인했습니다.
- **Mission Core 구현 완료가 아닙니다.** 이번 단계는 환경 사전검증만 수행했습니다.
- 확인 필요:
  1. openssh-server, ufw 미설치 → 설치 시 apt 저장소 접근 가능 여부 확인
  2. OrbStack Machine에서 UFW(iptables/nftables)가 실제로 동작하는지
  3. Ubuntu 24.04의 `ssh.socket` 소켓 활성화가 포트 20022 설정에 미치는 영향
  4. 제공 Agent 앱의 Python 요구 버전과 3.12.3의 호환성
  5. 제공 Agent 앱/바이너리의 architecture (`file`로 확인, 추정 금지)

> 참고: 첫 실행 시 zsh 반복문에서 명령 문자열이 단어로 나뉘지 않아 6개 명령 모두 `command not found`(exit 127)가 났습니다. 이는 host 쪽 호출 방식의 실수였고, 같은 명령을 올바르게 다시 실행한 결과가 위 표입니다.
