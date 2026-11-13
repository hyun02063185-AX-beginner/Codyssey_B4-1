# OrbStack 실습 환경

B4-1 / B4-2 실습환경을 OrbStack Ubuntu Linux Machine으로 구성하는 이유와, 교육장 Mac 초기화 후 복구하는 방법을 정리합니다.

> 이 문서는 **환경 설계 문서**입니다. Machine `b4-lab`은 생성·사전검증(9장)과 SSH 20022 구성·검증(10장), UFW 구성·검증(11장), 사용자·그룹 생성(12장), 그룹 소속·디렉터리 권한/ACL 적용([권한 설계 11장](b4-1-permission-plan.md#11-실제-적용-및-검증-작업-8)), 환경변수 파일 적용([Agent 실행환경](b4-1-agent-runtime.md), `AGENT_KEY_PATH` PENDING)까지, `monitor.sh` 구현·1차 검증([monitor 기록](b4-1-monitor.md), Agent 관련 항목 PENDING), `monitor.log` 누적 기록(작업 11), 로그 순환 설정([로그 순환 기록](b4-1-log-rotation.md), 작업 12), cron 매분 실행([cron 기록](b4-1-cron.md), 작업 13), 복구 자동화([복구 자동화](b4-1-recovery.md), 작업 14)까지 진행했고, 그 외 Mission Core 설정(Agent 기동, 로그, cron)은 아직 적용하지 않았습니다.
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

적용 방식 (2026-11-11 실행 완료, 9장):

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

OrbStack에는 자체 SSH 접속 경로가 있습니다. 이것은 **미션에서 요구하는 SSH(20022)와 다른 경로**이므로 구분해야 합니다. (2026-11-11 실측, 상세는 [10장](#10-ssh-20022-구성-및-검증-기록))

| 항목 | OrbStack 관리 SSH | 미션 SSH (Ubuntu sshd) |
| --- | --- | --- |
| 접속 예 | `ssh b4-lab@orb` / `orb -m b4-lab` | `ssh -p 20022 <user>@b4-lab.orb.local` 또는 `@192.168.139.18` |
| 서버 | OrbStack 자체 SSH 서버 — 배너 `SSH-2.0-OrbStack` (host `127.0.0.1:32222`, `~/.orbstack/ssh/config`) | Machine 내부 openssh-server — 배너 `SSH-2.0-OpenSSH_9.6p1 Ubuntu-3ubuntu13.20` |
| 호스트키 (ED25519) | `SHA256:9vANHPcI25pqjcMgRCKMWJiwf4R6xAWdM6X7lIaqNx0` | `SHA256:bB06Z1oE97PdHnKfjoNofPahYxXLrt3PjpfZwTyHL78` (= `/etc/ssh/ssh_host_ed25519_key.pub`) |
| 인증 키 | `~/.orbstack/ssh/id_ed25519` (OrbStack 자동 생성) | Machine 사용자의 `~/.ssh/authorized_keys` |
| `sshd_config` 영향 | 받지 않음 — sshd 포트 변경·socket 비활성 후에도 접속 유지 확인 | 받음 — `Port 20022`, `PermitRootLogin no` |
| UFW 영향 | 받지 않음 — UFW 활성화 후에도 `orb -m`, `ssh b4-lab@orb` 유지 (11장) | 받음 — `20022/tcp` 허용 필요 |
| 용도 | 관리용 접근, 설정 실수 시 복구 경로 | **미션 요구사항 충족·증빙 대상** |

주의 사항:

- `ssh b4-lab@orb`로 접속이 된다고 해서 **미션 SSH가 동작하는 것은 아닙니다.** 미션 증빙은 반드시 `-p 20022`로 Machine의 `sshd`에 접속한 결과로 남깁니다.
- **`b4-lab.orb.local:22`는 Ubuntu sshd가 아닙니다.** 이 이름은 OrbStack 프록시 주소(`192.168.138.3`)로 해석되고, 22번에서는 OrbStack 관리 SSH가 응답합니다(호스트키가 32222와 동일). 따라서 "22번 미사용" 검증은 Machine 내부 `ss`와 Machine IP(`192.168.139.18:22` → Connection refused)로 판단합니다.
- 반면 `b4-lab.orb.local:20022`는 Ubuntu sshd로 전달됩니다(호스트키가 Machine 호스트키와 동일, `SSH_CONNECTION` 서버 주소 `192.168.139.18`).
- sshd 포트 변경 후에도 `orb -m b4-lab`, `ssh b4-lab@orb` 모두 유지됨을 확인했습니다. UFW 활성화 후에도 유지됨을 11장에서 확인했습니다.
- Machine IP(`192.168.139.18`)는 재시작 후에도 같았지만 고정 보장은 확인되지 않았으므로, 접속 주소는 `b4-lab.orb.local`을 우선 사용합니다.

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
| Machine IP | `192.168.139.18` (2026-11-11, 재시작 후 동일) |
| openssh-server | `1:9.6p1-3ubuntu13.20` — `ssh.service` 방식, TCP 20022 (10장) |
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
1. OrbStack 동작 확인 ── orb version / orb list   (없으면 교육장 안내에 따라 재설치)
     ▼
2. 저장소 clone ─────── git clone https://github.com/hyun02063185-AX-beginner/Codyssey_B4-1.git
     ▼
3. 복구 실행 (Mac에서 sudo 불필요)
     ├─ Machine 없음 → scripts/bootstrap-orbstack.sh all          (create + apply + verify)
     └─ Machine 있음 → scripts/bootstrap-orbstack.sh check        (지속 상태 변경 없는 점검)
                       scripts/bootstrap-orbstack.sh apply --allow-existing   (차이만 복구)
     ▼
4. 재검증 ──────────── scripts/bootstrap-orbstack.sh verify --wait-cron 240
     │                    (SSH는 반드시 -p 20022 경로, Machine IP 기준)
     ▼
5. B4-2 진행
```

- 구현·검증 결과, 단계별 동작, 오류·복구 절차, 사라지는 데이터와 재현되는 설정의 구분: **[docs/b4-1-recovery.md](b4-1-recovery.md)** (작업 14).
- 제공 Agent 원본은 저장소에 없으며 복구 대상이 아닙니다(PENDING). 확보 후 `AGENT_PROCESS_PATTERN`·`AGENT_KEY_PATH`를 정해 `config/`에 반영해야 재현됩니다.

작업 습관:

- Machine 안에서 설정을 바꾸면 **같은 세션 안에** 스크립트/문서에 반영하고 commit·push 합니다.
- 비밀값(비밀번호, 개인키 등)은 저장소에 커밋하지 않습니다. 복구 시 다시 입력/생성하는 방식입니다(스크립트가 만들지 않음).
- `bootstrap-orbstack.sh`는 여러 번 실행해도 같은 결과가 나오도록(idempotent) 작성되었고 이를 실측했습니다.

## 8. B4-1 → B4-2 재사용

- B4-2 저장소: https://github.com/hyun02063185-AX-beginner/Codyssey_B4-2
- B4-2는 B4-1에서 구성한 **Linux 환경과 `monitor.sh`** 가 그대로 있다는 전제로 진행합니다.
- 같은 Mac 세션 안이라면 기존 Machine을 그대로 사용합니다.
- Mac이 초기화된 경우 7장의 흐름으로 B4-1 종료 상태를 복구한 뒤 B4-2를 시작합니다.
- 따라서 B4-1의 완료 조건에는 "Mission Core 충족"뿐 아니라 **"고정한 Ubuntu 버전의 새 Machine에서 bootstrap으로 동일 상태 재현 가능"** 이 포함됩니다. (재현 검증 완료: [복구 자동화](b4-1-recovery.md), 제공 Agent 관련 항목은 PENDING)

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
- 확인 필요 (위 표는 사전검증 시점의 기록이며, 이후 해결된 항목은 표시함):
  1. openssh-server, ufw 미설치 → 설치 시 apt 저장소 접근 가능 여부 확인 — **openssh-server: 해결** (apt 설치 성공, 10장). ufw: **해결** (설치·구성, 11장)
  2. OrbStack Machine에서 UFW(iptables/nftables)가 실제로 동작하는지 — **해결** (실제 허용·차단 확인, 11.4)
  3. Ubuntu 24.04의 `ssh.socket` 소켓 활성화가 포트 20022 설정에 미치는 영향 — **해결** (socket 비활성, service 방식 채택, 10장)
  4. 제공 Agent 앱의 Python 요구 버전과 3.12.3의 호환성
  5. 제공 Agent 앱/바이너리의 architecture (`file`로 확인, 추정 금지)

> 참고: 첫 실행 시 zsh 반복문에서 명령 문자열이 단어로 나뉘지 않아 6개 명령 모두 `command not found`(exit 127)가 났습니다. 이는 host 쪽 호출 방식의 실수였고, 같은 명령을 올바르게 다시 실행한 결과가 위 표입니다.

## 10. SSH 20022 구성 및 검증 기록

- 일시: 2026-11-11 17:31~17:35 KST
- 대상: `b4-lab` (Ubuntu 24.04.5 LTS)
- 범위: openssh-server 설치, TCP 20022, Root 원격 로그인 차단. UFW·사용자·그룹·Agent·`monitor.sh`·cron은 변경하지 않음.

### 10.1 설치 직후 상태 (Ubuntu 24.04 기본값)

| 항목 | 실제 상태 |
| --- | --- |
| 패키지 | `openssh-server 1:9.6p1-3ubuntu13.20` |
| `ssh.socket` | enabled / active — `ListenStream=0.0.0.0:22`, `[::]:22` (systemd PID 1이 22를 LISTEN) |
| `ssh.service` | disabled / inactive (접속이 오면 socket이 기동하는 구조) |
| `/etc/ssh/sshd_config` | 12행에 `Include /etc/ssh/sshd_config.d/*.conf` — 기본값보다 **먼저** 읽힘 |
| `/etc/ssh/sshd_config.d/` | 비어 있음 |
| socket 포트 생성기 | `/usr/lib/systemd/system-generators/sshd-socket-generator` 존재 |

Ubuntu 24.04는 기본으로 **socket 활성화**를 씁니다. 이 방식에서는 실제 LISTEN 포트를 `ssh.socket`이 정하며, `sshd_config`의 `Port`는 생성기가 `daemon-reload` 시점에 socket 설정으로 옮겨야 반영됩니다. 포트가 두 곳(`sshd_config`, socket)에 걸쳐 관리되어 불일치 위험이 있습니다.

### 10.2 운영 방식 결정: socket 비활성 + `ssh.service` 상시 실행 [설계]

| 선택지 | 판단 |
| --- | --- |
| A. `ssh.socket` 비활성, `ssh.service` 활성 | **채택.** 포트를 `sshd_config` 한 곳에서만 관리. sshd가 상시 실행되어 `ss`·`ps`로 바로 확인 가능. `ExecStartPre=/usr/sbin/sshd -t`로 기동 전 문법 검사 |
| B. socket 유지, 생성기에 의존 | 미채택. `daemon-reload` 누락 시 22 유지·20022 미반영 위험 |

### 10.3 적용한 설정

`/etc/ssh/sshd_config.d/10-b4-mission.conf` (root:root, 0644):

```
# B4-1 Mission: SSH
# Ubuntu sshd_config는 첫 번째로 지정된 값이 우선하며, Include가 파일 상단에 있으므로 이 조각의 값이 적용된다.
Port 20022
PermitRootLogin no
```

- 원본 `/etc/ssh/sshd_config`는 수정하지 않았습니다(패키지 업그레이드 충돌 방지).
- `PasswordAuthentication`은 기본값(`yes`) 그대로이며 이번 작업에서 바꾸지 않았습니다.

### 10.4 적용 절차

```bash
# Machine 내부 (orb -m b4-lab)
sudo apt-get update && sudo apt-get install -y openssh-server
sudo tee /etc/ssh/sshd_config.d/10-b4-mission.conf    # 10.3 내용
sudo install -d -m 0755 /run/sshd                     # sshd -t 단독 실행용 (서비스 기동 시엔 자동 생성)
sudo sshd -t                                          # 문법 검사
sudo sshd -T | grep -E '^(port|permitrootlogin) '     # 실효값 확인
sudo systemctl disable --now ssh.socket
sudo systemctl enable --now ssh.service
```

- 처음 `sshd -t` 실행 시 `Missing privilege separation directory: /run/sshd`로 실패했습니다. `/run/sshd`는 `ssh.service`의 `RuntimeDirectory=sshd`가 기동 시 만드는 디렉터리라, 서비스 기동 전 수동 검사할 때만 필요합니다. 생성 후 `syntax OK`.
- 전환 중에도 OrbStack 관리 경로(`orb -m`)는 유지되었습니다.

### 10.5 검증 결과

Mac에서의 접속은 이 작업 전용 키 `~/.ssh/b4-lab_ed25519`(Mac 로컬, **저장소에 저장하지 않음**)를 사용했고, 공개키만 Machine 기본 사용자의 `~/.ssh/authorized_keys`에 등록했습니다. known_hosts는 `~/.ssh/b4-lab_known_hosts`로 분리했습니다.

| # | 검증 항목 | 명령 | 실제 결과 | 판정 |
| --- | --- | --- | --- | --- |
| 1 | 문법 검사 | `sudo sshd -t` | `syntax OK` (exit 0) | PASS |
| 2 | 실효 설정 | `sudo sshd -T` | `port 20022`, `listenaddress 0.0.0.0:20022`, `listenaddress [::]:20022`, `permitrootlogin no` | PASS |
| 3 | 유닛 상태 | `systemctl is-enabled/is-active` | `ssh.service enabled/active`, `ssh.socket disabled/inactive` | PASS |
| 4 | 20022 LISTEN | `sudo ss -tlnp` | `0.0.0.0:20022`, `[::]:20022` — `sshd` | PASS |
| 5 | Ubuntu sshd TCP 22 미사용 (내부) | `sudo ss -tlnp "sport = :22"` | 0건 | PASS |
| 6 | Ubuntu sshd TCP 22 미사용 (Mac → Machine IP) | `ssh -p 22 …@192.168.139.18`, `nc -z 192.168.139.18 22` | `Connection refused`, nc exit 1 | PASS |
| 7 | Mac → sshd 접속 (IP) | `ssh -p 20022 hyun…@192.168.139.18` | 로그인 성공, `hostname=b4-lab`, 부모 프로세스 `sshd`, 로그 `Accepted publickey` | PASS |
| 8 | Mac → sshd 접속 (이름) | `ssh -p 20022 hyun…@b4-lab.orb.local` | 로그인 성공, 호스트키 = Machine 호스트키, 배너 `OpenSSH_9.6p1 Ubuntu` | PASS |
| 9 | Root 차단 (키 미등록) | `ssh -p 20022 root@192.168.139.18` | `Permission denied (publickey,password)` | 참고 (인증 실패와 구분 불가) |
| 10 | **Root 차단 (유효 키 임시 등록)** | root `authorized_keys`에 같은 공개키 임시 등록 후 접속 | `Permission denied`, sshd 로그 `ROOT LOGIN REFUSED FROM 192.168.139.3` | **PASS — 설정에 의한 차단** |
| 11 | 대조군 | 같은 키로 일반 사용자 접속 | 로그인 성공 | PASS (키 자체는 유효) |
| 12 | 임시 키 제거 | `sudo ls -la /root/.ssh` | `authorized_keys` 없음 | PASS |
| 13 | OrbStack 관리 경로 | `orb -m b4-lab`, `ssh b4-lab@orb` | 둘 다 성공 | PASS |
| 14 | 재시작 후 유지 | `orb restart b4-lab` 후 3·4·7·13 재확인 | 동일 결과 | PASS |

Root 판정 근거: 10번에서 **같은 키가 일반 사용자로는 성공(11번)** 하고 root로는 거부되었으며, sshd가 인증 실패가 아닌 `ROOT LOGIN REFUSED`를 기록했습니다. 따라서 단순 인증 실패가 아니라 `PermitRootLogin no`에 의한 차단입니다.

참고 (PASS/FAIL 대상 아님): `b4-lab.orb.local:22`는 연결이 되지만 응답 주체는 **OrbStack 관리 SSH**입니다(배너 `SSH-2.0-OrbStack`, 호스트키 = `127.0.0.1:32222`). Ubuntu sshd의 22번 사용이 아닙니다. (5장 참고)

### 10.6 제약사항 및 다음 작업 주의

- **UFW 작업 시:** 활성화 전에 `20022/tcp`를 먼저 허용합니다. (작업 5에서 적용·검증 완료: UFW 활성화 후에도 `orb -m` 관리 경로 유지.)
- **UFW 검증 시:** "22 차단" 같은 확인을 `b4-lab.orb.local:22`로 하면 OrbStack 관리 SSH가 응답하므로 오판합니다. Machine IP 또는 Machine 내부 `ss`로 판단합니다.
- **미션 사용자 SSH:** `agent-*` 사용자의 접속 방식(키/비밀번호)은 아직 정하지 않았습니다(비밀번호 잠금·키 없음 = 접속 불가). 현재 접속 검증은 OrbStack 기본 사용자로 했습니다.
- **`PasswordAuthentication`:** 기본값 `yes`입니다. 공식 요구가 있는지 **확인 필요**.
- **Mac 초기화 시:** `~/.ssh/b4-lab_ed25519`와 `~/.ssh/b4-lab_known_hosts`도 사라집니다. 키를 다시 만들고 공개키를 다시 등록해야 하며, Machine을 재생성하면 호스트키도 바뀝니다.
- **bootstrap 반영:** 10.4 절차 전체는 `scripts/machine-setup.sh`의 `ssh` 단계에 반영됨(작업 14, 재시작 전 사전검증은 작업 14-1).

## 11. UFW 방화벽 구성 및 검증 기록

- 일시: 2026-11-13 / 기준 커밋 `3bd9564`
- 범위: ufw 설치·정책 적용만. SSH 설정, 사용자·그룹, 권한, Agent, `monitor.sh`, cron은 변경하지 않음.
- 정책은 `[관리자료]`/`[설계]` 기준이며 공식 원문 대조는 완료되지 않았습니다.

### 11.1 사전 점검

- Machine `running`, IP `192.168.139.18`, `orb -m b4-lab` 정상, sshd `0.0.0.0:20022`·`[::]:20022` LISTEN.
- Mac → `-p 20022` 접속 성공 (전용 키 `~/.ssh/b4-lab_ed25519`).
- ufw 미설치였고 기존 iptables 규칙 없음(`INPUT/FORWARD/OUTPUT ACCEPT`) → 초기화할 것도, 영향받을 것도 없었음.

### 11.2 적용 절차 (재설치 시 재현용, bootstrap 반영 대상)

```bash
sudo apt-get update && sudo apt-get install -y ufw   # ufw 0.36.2 (iptables 백엔드)
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 20022/tcp comment 'SSH'               # 반드시 활성화 전에
sudo ufw allow 15034/tcp comment 'Agent'
sudo ufw show added                                  # 확인
sudo ufw --force enable
sudo ufw status verbose
```

`/etc/default/ufw`의 `IPV6=yes`(기본값)라서 v4·v6 규칙이 모두 생성됩니다. 활성화 시점에 기존 SSH 세션·`orb` 경로는 끊기지 않았습니다.

적용 결과 (`ufw status verbose`):

```
Status: active
Logging: on (low)
Default: deny (incoming), allow (outgoing), deny (routed)

20022/tcp        ALLOW IN  Anywhere        # SSH
15034/tcp        ALLOW IN  Anywhere        # Agent
20022/tcp (v6)   ALLOW IN  Anywhere (v6)   # SSH
15034/tcp (v6)   ALLOW IN  Anywhere (v6)   # Agent
```

### 11.3 검증 방법

Machine 내부에 임시 TCP 서버(`nc -l`, `0.0.0.0:15034`·`0.0.0.0:15035`)를 띄우고 Mac에서 **Machine IP `192.168.139.18`로 직접** 접속했습니다. macOS `nc -w`는 연결 타임아웃을 제한하지 못해 8초 `alarm`으로 끊었으며, 이때 종료는 "무응답(DROP)"을 뜻합니다. 테스트 서버는 검증 후 종료했다고 기록했으나 **실제로는 남아 있었고**(작업 5-1에서 발견), 5-1에서 종료·`ss`로 LISTEN 0건 확인했습니다. 남은 서버가 있었어도 15035 차단 판정(활성화 전 성공/후 무응답)에는 영향이 없었습니다.

### 11.4 검증 결과

| # | 검증 | 결과 | 판정 |
|---|---|---|---|
| 1 | UFW 실행 상태 | `active`, deny(in)/allow(out), 허용 4개 규칙(v4+v6), iptables `ufw-user-input`/`ufw6-user-input`에 ACCEPT 반영 | PASS |
| 2a | Mac → Machine SSH 20022 (UFW 후) | 로그인 성공, `hostname=b4-lab`, `SSH_CONNECTION … 192.168.139.18 20022` | PASS |
| 2b | `orb -m b4-lab`, `ssh b4-lab@orb` | 둘 다 성공 | PASS |
| 2c | `ssh.service` 설정 유지 | `sshd -T`: `port 20022`, `permitrootlogin no`, 서비스 active | PASS |
| 3 | 15034 허용 (IPv4, Machine IP / `b4-lab.orb.local`) | 연결 성공 (활성화 전·후 모두) | PASS |
| 3v6 | 15034 허용 (IPv6, Machine 주소) | `Connection refused` — 방화벽을 통과해 호스트가 RST 응답(테스트 서버가 IPv4만 바인딩). 15035는 무응답과 대조 | PASS (규칙 통과 확인, 서버 응답은 해당 없음) |
| 4 | 15035 차단 | 활성화 **전** Machine IP·`orb.local` 모두 연결 성공(서버 LISTEN 확인) → 활성화 **후** Machine IP(IPv4)·IPv6 모두 무응답(타임아웃), 서버는 계속 LISTEN | PASS |
| 4b | TCP 22 (Machine IP) | 이전 `Connection refused` → UFW 후 무응답(DROP). 22는 원래 미사용이며 차단 방식만 달라짐 | 참고 |
| 5 | OrbStack SSH vs Ubuntu SSH 구분 | 판정은 Machine IP·Machine 내부 `ss` 기준으로만 수행. `b4-lab.orb.local:22` 응답은 판정에서 제외 | PASS |
| 6 | 재부팅 후 UFW 자동 복원 | (작업 5 시점 미실시 → 11.7에서 PASS로 갱신) 당시 기록: 활성화 직후 `ufw.service`가 `inactive (dead)`, `ConditionResult=no`로 보였음(원인은 11.7에서 규명). 수동 `systemctl start ufw`는 정상 동작. `ENABLED=yes`이므로 복원될 가능성은 있으나 검증하지 않음 | INCONCLUSIVE |
| 7 | UFW 차단 로그(`UFW BLOCK`) | `/var/log/ufw.log`·dmesg에 없음 (Machine 로그 구성 영향 추정). 차단 판정은 로그가 아닌 접속 결과 비교에 근거 | INCONCLUSIVE |

FAIL 항목 없음.

### 11.5 OrbStack 네트워크 제약

- `b4-lab.orb.local`은 OrbStack 프록시 주소로 해석되며 22번은 OrbStack 관리 SSH가 응답합니다(5장). 이 주소의 22 응답은 UFW 판정 근거가 아닙니다.
- 이번 검증에서 Mac → Machine IP(`192.168.139.18`) 경로는 UFW 규칙에 따라 실제로 허용·차단되어 패킷 필터링이 동작함을 확인했습니다.
- `orb -m`, `ssh b4-lab@orb`는 UFW 활성화 후에도 정상이므로 UFW 오설정 시 복구 경로로 사용할 수 있습니다(필요 시 `sudo ufw disable`).
- 차단은 REJECT가 아닌 DROP이라 클라이언트 입장에서 "타임아웃"으로 보입니다.

### 11.6 남은 문제 및 다음 작업 주의

- Machine 재시작 후 UFW 자동 복원은 11.7에서 PASS. Mac 재부팅·OrbStack 앱 재시작 후는 미검증이므로 `sudo ufw status`로 확인합니다.
- 15034 허용 규칙은 이미 존재합니다(Agent는 아직 없음). 실제 Agent 리슨 주소/프로토콜은 Agent 작업에서 확인합니다.
- Mac IP(`192.168.139.3`)는 허용 규칙에 한정하지 않았습니다(요구사항이 포트 단위).
- **bootstrap 반영:** 11.2 절차는 `scripts/machine-setup.sh`의 `ufw` 단계에 반영됨(작업 14). Mac 재부팅 후 상태 확인은 미검증.

### 11.7 재시작 후 복원 검증 (작업 5-1)

- 일시: 2026-11-13 / 기준 커밋 `f7e6ab3`

**원인 분석 (`inactive (dead)` / `ConditionResult=no`)**

- `ufw.service`에는 `Condition*` 항목이 없고, 유일한 drop-in(`/run/systemd/system/service.d/zzz-lxc-service.conf`)도 보안 샌드박스 옵션(`ProtectSystem=no` 등)만 완화합니다. 즉 unit이 조건으로 막힌 것이 아닙니다.
- `ufw enable`은 규칙을 커널에 적용하고 `ENABLED=yes`를 기록할 뿐 `ufw.service`를 시작하지 않습니다. 작업 5에서는 한 번도 start 시도가 없었기에 systemd는 `inactive`, 조건 평가 전 기본값 `ConditionResult=no`를 표시한 것으로 **판단**됩니다. 근거: 수동 start 후 `ConditionResult=yes`, `ConditionTimestamp` 기록. 다만 당시 상태 변화를 직접 포착한 것은 아니므로 이 설명은 재시작 결과와 정합한 해석이며, 독립 증명은 아닙니다.
- unit은 `enabled`(multi-user.target)이고 `ENABLED=yes`였습니다.

**재시작 전 상태**: ufw active, 규칙 4개 유지, `ufw.service` active(exited, 수동 start 14:22:52). 작업 트리 clean, 실행 중 작업 없음. (테스트용 `nc` 2개가 남아 있어 종료)

**절차**: `orb restart b4-lab` (PID 1 시작 시각 14:27:44로 실제 재시작 확인. `uptime -s`는 VM 부팅 시각을 보여주므로 증거로 부적합).

**재시작 후 결과** (수동 start 없이)

| # | 항목 | 결과 | 판정 |
|---|---|---|---|
| 1 | Machine 실행 | `running` | PASS |
| 2 | UFW 활성·규칙 | `ufw status verbose` active, deny(in)/allow(out), 허용 4개 유지. iptables `INPUT` 정책 DROP, `ufw-user-input` ACCEPT 20022/15034 | PASS |
| 2b | `ufw.service` | 부팅 시 자동 시작: `Starting` 14:27:45 → `Finished` 14:27:46, `ConditionResult=yes`, `active (exited)` | PASS |
| 3 | SSH 20022 (Mac → IP) | 로그인 성공, `SSH_CONNECTION … 192.168.139.18 20022`, `port 20022`, `permitrootlogin no` | PASS |
| 4 | OrbStack 관리 SSH | `ssh b4-lab@orb`, `orb -m` 성공 | PASS |
| 5 | 15034 허용 | 서버 LISTEN 중 연결 성공 (IPv4). IPv6는 `refused`(방화벽 통과, 서버가 v4만 바인딩) | PASS |
| 6 | 15035 차단 | 서버 LISTEN 중 IPv4·IPv6 모두 무응답(DROP). LISTEN 상태이므로 "서비스 부재"가 아닌 UFW 차단 | PASS |
| 7 | 부팅 로그 | `journalctl -b -u ufw` 정상 시작 기록 확인. `UFW BLOCK` 커널 로그는 여전히 0건(로그 미기록) | INCONCLUSIVE (로그 한정, 차단 자체는 6번으로 확인) |

임시 서버(`nc`)는 종료했고 LISTEN 0건 확인. 변경된 설정 없음(수정 불필요).

**검증 범위**: OrbStack `orb restart b4-lab`까지입니다. Mac 재부팅이나 OrbStack 앱 재시작 후의 동작은 확인하지 않았습니다. 재시작 후에도 `sudo ufw status` 확인 습관은 유지하세요.

## 12. 사용자·그룹 구성 및 검증 기록

- 일시: 2026-11-13 / 기준 커밋 `f8cb725`
- 범위: 사용자·그룹 **생성만**. 디렉터리 권한/ACL, Agent, 환경변수, `monitor.sh`, cron, SSH·UFW 변경 없음.

### 12.1 요구사항 확인 상태

| 항목 | 상태 | 비고 |
|---|---|---|
| 사용자 `agent-admin`, `agent-dev`, `agent-test` | 확정 `[관리자료]` | README 3.3 |
| 그룹 `agent-common`, `agent-core` | 확정 `[관리자료]` | README 3.3 |
| 사용자별 그룹 소속 | **미확정** | 공식 원문을 저장소·Mac에서 찾지 못했고 README에도 미기입. 추측 지정 금지 원칙에 따라 **미적용** |
| UID/GID 값, 로그인 셸, 비밀번호/SSH 방식 | **미확정** | 아래 값은 Ubuntu 기본값(설계 선택)이며 공식 값이 아님 |

사전 상태: `agent-*` 사용자·그룹 모두 없음(기존 사용자는 OrbStack 기본 사용자 `hyun020631854123` 하나).

### 12.2 적용 절차 (재현용, bootstrap 반영 대상)

```bash
sudo groupadd agent-common
sudo groupadd agent-core
for u in agent-admin agent-dev agent-test; do
  sudo useradd -m -s /bin/bash -c "B4-1 mission account" "$u"
  sudo passwd -l "$u"          # 비밀번호 로그인 불가(잠금). 비밀번호는 설정하지 않음
done
# ※ 그룹 소속(usermod -aG)은 원문 확인 후 별도 작업에서 적용
```

설계 선택(공식 요구 아님): 기본 개인 그룹(`USERGROUPS_ENAB yes`), 홈 `/home/<user>`(`/etc/skel` 복사), 셸 `/bin/bash`, 비밀번호 잠금, sudo 미부여. 재설치 시 UID/GID는 생성 순서에 따라 결정됩니다. 비밀번호·키는 저장소에 기록하지 않았습니다.

### 12.3 실제 결과

```
uid=1000(agent-admin) gid=1002(agent-admin) groups=1002(agent-admin)
uid=1001(agent-dev)   gid=1003(agent-dev)   groups=1003(agent-dev)
uid=1002(agent-test)  gid=1004(agent-test)  groups=1004(agent-test)
agent-common:x:1000:
agent-core:x:1001:
```

- `/etc/passwd`: 홈 `/home/agent-*`, 셸 `/bin/bash`.
- 홈 디렉터리: `agent-*:agent-*` `750`(`drwxr-x---`), `.bashrc/.profile/.bash_logout` 존재.
- 비밀번호 상태 `passwd -S`: 세 계정 모두 `L`(잠김).
- UID/GID 번호가 일치하지 않는 것(예: agent-admin UID 1000 / GID 1002)은 그룹 2개를 먼저 만들어 GID 1000, 1001이 소진됐기 때문이며 기능상 문제 없음.

### 12.4 검증 결과

| # | 항목 | 결과 | 판정 |
|---|---|---|---|
| 1 | 사용자 3개 생성 (`id`) | 위 출력 | PASS |
| 2 | 그룹 2개 생성 (`getent group`) | 위 출력 | PASS |
| 3 | 홈 디렉터리·기본 권한 | 750, 소유자 일치 | PASS |
| 4 | 불필요한 sudo 없음 | `sudo -l -U`: 3계정 모두 `not allowed`, `sudo` 그룹 미소속, sudoers에 agent 항목 없음 | PASS |
| 5 | 기존 사용자 유지 | `hyun020631854123` UID/GID/그룹(sudo 포함)·홈 변경 없음 | PASS |
| 6 | SSH 유지 | `port 20022`, `permitrootlogin no`, ssh active, Mac → 20022 접속 성공, `ssh b4-lab@orb` 성공 | PASS |
| 7 | UFW 유지 | active, deny(in)/allow(out), 20022·15034 규칙 4개 동일 | PASS |
| 8 | 사용자별 그룹 소속 | 미적용(원문 미확인) | 해당 없음 (미확정) |
| 9 | `agent-*` 계정 SSH 접속 | 미실시. 비밀번호 잠금·authorized_keys 없음 → 접속 불가 상태 | 미검증 |

### 12.5 남은 문제 및 다음 작업 주의

- **(작업 8 갱신)** 그룹 소속은 `[승인된 실습 설계]`로 적용됨([권한 설계 11장](b4-1-permission-plan.md#11-실제-적용-및-검증-작업-8)). 공식 원문 대조는 여전히 필요. 당시 기록: 사용자↔그룹 소속(예: cron 실행 사용자 `agent-admin`이 `agent-core`에 속해야 로그에 쓸 수 있는지 등)은 원문을 확인한 뒤 `usermod -aG`로 추가하고 `id`·`getent`로 재검증합니다.
- `agent-*` 계정의 SSH 접속 방식은 미정(10.6)이며 현재 접속할 수 없습니다. 필요하면 키 방식을 결정 후 구성합니다.
- 셸·UID/GID에 공식 요구가 있으면 그에 맞춰 재조정이 필요할 수 있습니다(기존 계정 변경이므로 그때 영향 분석).
