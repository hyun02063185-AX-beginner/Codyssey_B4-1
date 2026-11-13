# B4-1 환경 복구 자동화 (작업 14)

- 일시: 2026-11-13 / 기준 커밋 `cb051d8` (작업 14-1: SSH 복구 사전검증 강화 — §3.1·§4.1 신설, §3 `ssh` 행·§5 갱신, 기준 `78d9ffb`)
- 구성: [scripts/bootstrap-orbstack.sh](../scripts/bootstrap-orbstack.sh)(Mac에서 실행) → [scripts/machine-setup.sh](../scripts/machine-setup.sh)(Machine 안에서 root로 실행) + 저장소의 설정 파일([bin/monitor.sh](../bin/monitor.sh), [config/](../config/), [scripts/monitor-cron.sh](../scripts/monitor-cron.sh))
- **Mac에서는 sudo를 쓰지 않습니다.** 권한이 필요한 작업은 모두 `orb -m <machine> sudo …`로 Machine 안에서만 수행합니다.
- 값의 구분: **[승인된 실습 설계]** 설정값 전반(공식 원문 미대조) / **[실측]** 이 문서의 테스트 결과 / **PENDING** 제공 Agent 필요.

## 1. 무엇이 복구되고 무엇이 사라지는가

| 구분 | 내용 |
|---|---|
| **GitHub로 재현되는 설정** | ① Ubuntu 24.04 Machine 생성 ② SSH 20022 + Root 차단 ③ UFW(deny in/allow out, 20022·15034/tcp) ④ 사용자 3·그룹 2·소속 ⑤ `/opt/agent-app` 구조·ACL ⑥ `/etc/default/agent-app` ⑦ `monitor.sh` 배포 ⑧ `monitor.log` 파일·권한 ⑨ logrotate 설정 ⑩ `agent-admin` 매분 cron |
| **교육장 Mac 초기화로 사라지고 GitHub로 복구되지 않는 것** | 기존 Machine과 그 안의 **모든 데이터**: `monitor.log`와 순환본(과거 기록), `upload_files`·`api_keys`의 파일, 저장소에 없는 `/etc/default/agent-app` 변경(예: 나중에 추가할 `AGENT_PROCESS_PATTERN`·`AGENT_KEY_PATH`), 직접 만든 crontab 항목, 사용자 비밀번호. Mac의 SSH 키쌍(`~/.ssh/b4-lab_ed25519`)과 known_hosts, **push하지 않은 로컬 커밋** |
| **애초에 저장소에 넣지 않는 것** | SSH 개인키·API 키·비밀번호(스크립트가 생성·복사·저장하지 않음), 제공 Agent 원본(미확보, **PENDING**) |

## 2. 절차 A — 처음 쓰는(초기화된) Mac에서 새 Machine 구성

전제: OrbStack 설치. Mac 쪽 sudo 불필요.

```bash
git clone https://github.com/hyun02063185-AX-beginner/Codyssey_B4-1.git
cd Codyssey_B4-1
scripts/bootstrap-orbstack.sh create     # orb create ubuntu:noble b4-lab (이미 있으면 건드리지 않음)
scripts/bootstrap-orbstack.sh check      # (선택) 지속 상태를 바꾸지 않는 차이 확인(§3.1) — 새 Machine에서는 차이가 많은 것이 정상
scripts/bootstrap-orbstack.sh apply      # 설치. 소요 약 40초(패키지 다운로드 포함). 실패하면 해당 단계에서 멈춤
scripts/bootstrap-orbstack.sh verify --wait-cron 240    # 상태 확인 + Mac 쪽 네트워크 검증 + 예약 실행 확인
# 한 번에: scripts/bootstrap-orbstack.sh all
```

다른 이름의 Machine: `--machine NAME`(기본 `b4-lab`).

SSH 실제 로그인 시험(선택): 키는 사용자가 직접 만든 것을 씁니다(스크립트는 키를 만들지 않음).

```bash
ssh-keygen -t ed25519 -f ~/.ssh/b4-lab_ed25519 -C b4-lab         # 이미 있으면 생략
scripts/bootstrap-orbstack.sh verify --ssh-pubkey ~/.ssh/b4-lab_ed25519.pub
```
공개키만 Machine 기본 사용자의 `authorized_keys`에 추가하고 개인키는 Mac에 남습니다.

## 3. 절차 B — 이미 구성된 Machine에서 점검·복구

```bash
scripts/bootstrap-orbstack.sh check                       # 지속 상태 변경 없음(§3.1): 단계별 OK / DIFF, 종료 코드 0(일치) / 1(차이)
scripts/bootstrap-orbstack.sh check --no-run              # 위와 같되 monitor.sh를 실행하지 않음(임시 디렉터리·프로세스 생략)
scripts/bootstrap-orbstack.sh apply                       # 이미 B4-1 데이터가 있으면 [STOP]으로 거부(보호)
scripts/bootstrap-orbstack.sh apply --allow-existing      # 차이가 있는 단계만 복구
scripts/bootstrap-orbstack.sh snapshot                    # 정규화된 상태 출력(두 Machine을 diff로 비교)
```

`apply`는 단계마다 먼저 **check**를 하고, 차이가 있는 단계에서만 변경한 뒤 **다시 check**로 확인합니다(`CHG` → `OK applied and verified`). 실패하면 그 단계에서 멈추고 이후 단계는 실행하지 않습니다.

| 단계 | 하는 일 (이미 맞으면 아무것도 하지 않음) |
|---|---|
| `preflight` | Ubuntu 24.04·systemd·저장소 파일 확인 (고칠 수 없는 항목이면 실패) |
| `packages` | `openssh-server ufw acl cron logrotate iproute2 procps` 중 없는 것만 설치 |
| `ssh` | `/etc/ssh/sshd_config.d/10-b4-mission.conf`(Port 20022, PermitRootLogin no) 설치. **서비스를 건드리기 전에** ① 기존 조각 백업 ② 새 조각 원자적 설치 ③ `sshd -t` ④ `sshd -T` 실효 설정 검사(Port가 정확히 20022 하나, `PermitRootLogin no`)를 모두 통과해야 하며, 하나라도 실패하면 조각을 원래대로 복원하고 **서비스를 재시작하지 않은 채** 실패 처리(§3.1). 통과한 뒤에만 `ssh.socket` 비활성·`ssh.service` 활성·재시작, 재시작·LISTEN 확인 실패 시 이전 상태로 롤백. 다른 SSH 설정 파일은 절대 수정·삭제하지 않음. OrbStack 관리 SSH(`orb -m`)와는 별개라 영향 없음 |
| `ufw` | deny incoming / allow outgoing, **20022/tcp 허용을 먼저** 추가(없으면 활성화 거부) → 15034/tcp → `ufw --force enable`, `ufw.service` enabled. 허용 포트 집합이 정확히 {20022, 15034}인지 확인(**다른 규칙은 보고만, 삭제하지 않음**) |
| `accounts` | 그룹 먼저(GID 1000·1001), 사용자 3명(`useradd -m -s /bin/bash`, **생성할 때만** 비밀번호 잠금), `usermod -aG`로 소속 추가(기존 소속 보존). sudo 권한은 부여하지 않으며, 있으면 차이로 보고 |
| `dirs` | `/opt/agent-app`(root:root 755), `upload_files`(agent-admin:agent-common 2770), `api_keys`·`/var/log/agent-app`(root:agent-core 2770) + access·default ACL |
| `envfile` | `/etc/default/agent-app`이 **없을 때만** 생성(root:root 0644). 있으면 **덮어쓰지 않고 현재 값을 보존**하며 `AGENT_KEY_PATH`만 공식 경로로 교체(없으면 추가, 변경 시에만 `/var/backups/b4-bootstrap`에 백업). 다른 키가 다르면 실패 |
| `keyfile` | `/opt/agent-app/api_keys/t_secret.key`를 없을 때만 생성(공식 실습 문자열 `agent_api_key_test` 한 줄, `root:agent-core 0640`). 내용이 다르면 덮어쓰지 않고 실패 |
| `monitor` | `bin/monitor.sh`를 `/opt/agent-app/bin/monitor.sh`(agent-dev:agent-core 0750)로 배포 |
| `logfile` | `monitor.log`가 없을 때만 생성(agent-admin:agent-core 0660). 있으면 소유자·mode만 맞추고 **내용은 절대 수정·삭제하지 않음** |
| `logrotate` | `/etc/logrotate.d/agent-app` 설치, `logrotate -d` 오류 없음, `logrotate.timer` 활성 |
| `cron` | `cron` 서비스 활성 + `monitor-cron.sh install`(관리 블록만 교체, **다른 crontab 항목 보존**, 중복 없음) |
| `verify` | `agent-admin`으로 `monitor.sh`를 **임시 로그**로 1회 실행(실제 `monitor.log` 무변경). exit 0 또는 1은 정상 동작(현재 Agent 부재의 exit 1은 **예상된 장애 감지**), exit 2는 실패 |
| `agent` | **PENDING** 안내만 출력(Agent를 설치·모의하지 않음) |

한계: 일시 중지(`pause`)한 cron은 `apply`가 다시 켭니다. `ssh`·`ufw` 단계에서 충돌하는 다른 설정은 자동으로 지우지 않고 실패로 보고합니다(`ssh`는 서비스를 건드리기 전에 중단).

### 3.1 `ssh` 단계의 사전검증·복원 (작업 14-1)

```
현재 상태 기록(조각, ssh.service/ssh.socket 상태, MainPID)
 → 기존 조각 백업(/var/backups/b4-bootstrap/10-b4-mission.conf.<시각>.bak, mode·mtime 보존)
 → 새 조각 설치(임시 이름 .new → 원자적 mv. '*.conf'가 아니므로 완료 전에는 sshd가 읽지 않음)
 → sshd -t                          실패 ─┐
 → sshd -T 실효 설정 검사 (재시작 전) 실패 ─┼→ 조각 복원(없었으면 삭제) → 서비스 재시작 없이 FAIL, 이후 단계 미실행
 → [여기서부터 서비스 변경] ssh.socket 비활성, ssh.service enable → restart
 → 재시작 실패 또는 20022 미LISTEN ─→ 롤백: 조각 복원, ssh.socket/ssh.service를 이전 상태로 되돌림, 오류 보고(journal 원인 발췌)
 → 성공: 백업은 내용이 달랐던 경우에만 보관
```

- **실효 설정 검사**: `sshd -T`는 메인 설정과 `sshd_config.d/*.conf` 전체를 sshd가 읽는 방식 그대로 평가합니다. `Port`는 **덮어쓰지 않고 누적**되므로 `Port 22` 조각이 있으면 실효 포트가 `20022 22`가 되어 거부됩니다. `PermitRootLogin`은 먼저 읽힌 파일이 우선하므로 `00-*.conf`의 `yes`가 이기며 이것도 거부됩니다. 거부 메시지에는 `Port`/`PermitRootLogin`을 설정한 파일 목록이 나옵니다(수정하지 않음).
- **충돌 파일은 자동으로 지우거나 고치지 않습니다.** 사람이 확인해 제거한 뒤 `apply`를 다시 실행합니다.
- **한계**: 새 조각이 잠시(수 ms) 디스크에 존재하는 구간이 있으나, 실행 중인 sshd는 기동 시 읽은 설정을 쓰므로 영향이 없습니다(§4.1에서 PID·시작 시각 불변으로 확인). 재시작 롤백은 실패 원인이 "새 설정에 한정"될 때 서비스를 되살립니다. 원인이 환경 전체(예: 서비스 파일 손상)이면 롤백 후에도 서비스가 내려가 있을 수 있어, 이 경우 `ERROR … use orb -m <machine> to repair`를 출력합니다(`orb -m` 경로는 sshd와 무관하게 유지). 이 최후 경로(롤백 후에도 복구 불가)는 시험하지 못했습니다.

### 3.2 `check`가 하는 일: "지속 상태 변경 없음"과 "파일을 전혀 쓰지 않음"은 다릅니다

| 구분 | 설명 |
|---|---|
| **지속 시스템 설정을 바꾸지 않는 검사** (`check`, `verify`의 점검부) | 설정 파일·서비스·계정·그룹·UFW·crontab·로그 내용을 변경하지 않습니다. 단, **일시적 부수 효과**가 있습니다: ① 저장소 파일 복사본을 Machine의 `/tmp/b4-src.XXXXXX`로 전송(종료 시 삭제) ② 기본 동작으로 `verify` 단계가 `/tmp/b4-verify.XXXXXX`를 만들고 **`agent-admin`으로 `monitor.sh`를 1회 실행**(시스템 상태를 읽는 `ss`·`df`·`/proc` 조회와 프로세스 생성, 결과는 **임시 로그**에만 기록하며 실제 `monitor.log`는 건드리지 않음, 종료 시 삭제) ③ `runuser`·`sudo -l -U`·systemd·PAM이 **journal/auth 로그 항목**을 남길 수 있음(감사 기록이지 설정 변경이 아님) |
| **`check --no-run`** | ②를 생략합니다(`verify` 단계는 `[SKIP]`으로 표시, 임시 디렉터리·`monitor.sh` 프로세스 없음). ①의 전송용 임시 복사본과 ③은 남습니다 |
| **`snapshot`** | 스크립트를 파일로 만들지 않고 표준입력으로 실행하므로 임시 파일이 없습니다. 로그인·`sudo -l` 등에 의한 journal/auth 항목은 남을 수 있습니다 |
| **디스크에 전혀 쓰지 않는 검사** | **제공하지 않습니다.** 검사에 필요한 저장소 파일을 Machine에 전달해야 하고 journal 항목을 완전히 피할 수 없기 때문입니다(`--no-run`이 가장 가깝습니다) |
| `apply` | 변경을 수행합니다(위 각 단계) |

## 4. 새 Machine 재구축 검증 [실측]

기존 `b4-lab`은 **삭제·초기화하지 않고** 지속 상태를 바꾸지 않는 `check`/`snapshot`만 실행했습니다. 별도 Machine `b4-recovery-test`(ubuntu:noble, 24.04.5, x86_64)를 새로 만들어 검증했습니다(Machine 생성 약 21초, 설치 약 42초).

| # | 항목 | 결과 | 판정 |
|---|---|---|---|
| 1 | 설치 전 상태 | `check`: ok 1 / diff 11 — sshd·ufw·acl 없음, 사용자·디렉터리·파일 없음 | 기준선 |
| 2 | GitHub(저장소) 파일만으로 최초 설치 | `apply`: unchanged 2 / changed 10 / **failed 0**(소요 ≈ 42초) | PASS |
| 3 | 반복 실행 | 데이터가 있는 Machine에 `--allow-existing` 없이 → `[STOP]`(보호). 2회차 `apply --allow-existing`: **12단계 모두 변경 없음**. 전후 지문(파일 mtime·inode·sha256, UFW 규칙, crontab, UID/GID, ACL, ssh·cron 서비스 시작 시각) **완전 동일**, 관리 블록 1개 | PASS |
| 4 | `b4-lab`과의 동일성 | `snapshot` 109줄을 비교: 차이는 **호스트 이름이 들어간 sudo 안내 문구 3줄뿐**. UID/GID, 그룹 소속, 디렉터리 소유·mode·ACL, 파일 해시·권한, sshd 실효값, UFW, crontab, 패키지 버전 모두 동일. 아래 5~6 오류 시험을 모두 마친 뒤 다시 비교해도 동일 | PASS |
| 5 | SSH | 새 Machine IP:20022가 `SSH-2.0-OpenSSH_9.6p1 Ubuntu-3ubuntu13.20`로 응답(OrbStack SSH 아님), IP:22 접근 불가, **Mac에서 실제 로그인 성공**(`ssh -p 20022`, 개인키는 Mac에만 존재), `orb -m` 관리 경로 정상 | PASS |
| 6 | Root 차단 | `sshd -T` 실효값 `permitrootlogin no`. 테스트용으로 root에 **공개키**를 잠시 허가한 뒤 root 로그인 시도 → 거부, sshd 로그 `ROOT LOGIN REFUSED`(PermitRootLogin에 의한 차단이며 단순 인증 실패가 아님), 임시 키 제거. 일반 사용자는 같은 키로 로그인 성공 | PASS |
| 7 | UFW 실제 동작 | Mac에서 새 Machine IP로: 15034 → `refused`(방화벽 통과, 서버 없음), 15035 → `timeout`(UFW가 차단), 22 → 접근 불가. 가짜 서버를 만들지 않음 | PASS |
| 8 | 사용자·그룹·ACL | `check` 12단계 OK. agent-test 비소속, sudo 없음 | PASS |
| 9 | 환경변수·monitor | `monitor.sh`가 `agent-admin`으로 실행, `groups=agent-admin,agent-common,agent-core`, `exit=1` + `PENDING PROCESS`·`FAIL PORT`(예상된 장애 감지) | PASS |
| 10 | cron 실제 예약 실행 | `trigger=cron`의 `START`~`SUMMARY`가 매분 기록, 대기 중 새 예약 실행 3회 확인(+journal에 `(agent-admin) CMD`) | PASS |
| 11 | 로그·logrotate | `monitor.log` `agent-admin:agent-core 660`, `/etc/logrotate.d/agent-app` 동일, `logrotate -d` 오류 없음, `logrotate.timer` 활성 | PASS |

### 오류 상황과 복구 [실측, `b4-recovery-test`에서 주입]

| 상황 | 동작 | 판정 |
|---|---|---|
| 충돌하는 sshd 조각(`00-conflict.conf`: `PermitRootLogin yes`, 먼저 읽혀 우선 적용됨) | `ssh` 단계 **FAIL**("실효값이 여전히 다름"), 이후 단계 미실행, exit 1. 조각 제거 후 `apply` → 정상 | PASS |
| 잘못된 sshd 지시어(`sshd -t` 실패) | 설치한 조각을 되돌리고 **FAIL**, 이후 단계 미실행. 그 뒤에도 `ssh.service` active·20022 LISTEN·`orb -m` 정상(실행 중인 sshd 무영향) | PASS |
| `/etc/default/agent-app` 값 충돌(`AGENT_PORT=9999`) + `monitor.sh` 변조 | `envfile` 단계 **FAIL**(덮어쓰지 않음, 값 9999 그대로), 이후 `monitor` 단계는 **실행되지 않음**(변조 그대로). 값을 되돌리고 `apply` → `monitor` 복구 | PASS |
| 드리프트(cron 블록 삭제, logrotate 설정 삭제, `agent-dev`를 `agent-common`에서 제거, `api_keys` mode 2777, `monitor.log` mode 666) | `check`가 5개 단계의 DIFF 보고(exit 1), `apply`가 5개 단계 복구, 재`check` 12 OK. **로그 앞 20줄 해시 동일(보존)**, **직접 넣은 다른 crontab 항목 보존**, 관리 블록 1개 | PASS |
| 불허 그룹 멤버(`agent-test`를 `agent-core`에 추가) | `accounts` 단계 **FAIL**("수동으로 제거"), **자동 삭제하지 않음**(멤버 그대로). 수동 `gpasswd -d` 후 `apply` 정상 | PASS |

### 4.1 SSH 사전검증 강화 시험 [실측, `b4-recovery-test`, 작업 14-1]

`b4-lab`에서는 위험한 SSH 충돌 실험을 하지 않았고, 지속 상태를 바꾸지 않는 `check --no-run`만 실행했습니다(이전과 동일하게 11단계 OK, `ssh.service` 시작 시각 14:27:46 그대로, `/etc/ssh/sshd_config.d/`에 `10-b4-mission.conf`만 존재, 백업 디렉터리 없음). 중지돼 있던 `b4-recovery-test`를 `orb start`로 시작해 사용했습니다(재시작 후에도 `check` 11단계 OK).

실패 시나리오마다 **적용 전후의 `ssh.service` MainPID·시작 시각(`ActiveEnterTimestampMonotonic`)·조각의 sha256·mtime·mode·owner**를 비교했고, 적용 전에 Mac에서 열어 둔 SSH 세션(`sleep 후 SESSION_ALIVE`)이 실패한 apply 이후에도 유지되는지, 새 로그인과 `orb -m`이 되는지 확인했습니다.

| # | 시나리오 | 결과 | 판정 |
|---|---|---|---|
| T1 | **정상 설정 적용**(조각을 지운 뒤 `apply`) | `apply` exit 0, 서비스 재시작(PID 변경), 실효값 `port 20022`·`permitrootlogin no`, 조각이 저장소 파일과 동일, Mac에서 20022 로그인 성공 | PASS |
| T1b | **기존의 다른 조각**(`Port 2222`) 교체 | 교체 전 `/var/backups/b4-bootstrap/….bak`에 백업(내용 `Port 2222\|PermitRootLogin no`), 교체·재시작 성공, 내용이 달랐으므로 백업 보관 | PASS |
| T2 | **`00-conflict.conf`: `PermitRootLogin yes`** (먼저 읽혀 우선) | `REJECTED before any restart … effective PermitRootLogin = 'yes'`, exit 1, 이후 단계 미실행. **`ssh.service` PID 2183·시작 시각 불변**, 조각 sha·mtime 동일, **충돌 파일 미수정**, 기존 세션 유지(SESSION_ALIVE), 새 로그인·`orb -m` 정상 | PASS |
| T3 | **`00-port.conf`: `Port 22`** | 실효 포트 `[20022 22]` → `REJECTED before any restart`, 위와 동일한 불변·유지 확인(22번이 열릴 뻔한 상황 차단) | PASS |
| T4 | **잘못된 지시어**(`BadDirective`) | `sshd -t` 단계에서 `REJECTED before any restart`, 위와 동일한 불변·유지 확인 | PASS |
| T5 | **변경된 기존 조각 + 충돌** (`Port 2222` 조각의 mtime을 2026-01-02로 지정) | 실패 후 **조각이 sha·mtime(2026-01-02 03:04:05)·mode·owner까지 바이트 단위로 복원**, 서비스 불변, 남은 백업 없음 | PASS |
| T6 | **재시작 실패**(`sshd -t`·`sshd -T`는 통과, 20022를 무관한 프로세스가 점유; 이전 상태는 `Port 2222`) | `ssh.service restart FAILED; journal: sshd: error: Bind to port 20022 on :: failed: Address already in use … Cannot bind any address`(원인 표시), 롤백 실행 → 조각 복원(sha·mtime 동일)·**`ssh.service`가 이전 포트 2222로 다시 active**, 점유 프로세스 미접촉, exit 1, 이후 단계 미실행, `orb -m` 정상. 점유 해제 후 일반 `apply` 성공 → 20022로 복귀, 로그인 성공 | PASS |
| T7 | 회귀 | `apply` 12단계 변경 없음(반복 실행 안전), `check` 12 OK, `verify`(IP:20022 OpenSSH 배너·22 불가·15034 refused·15035 timeout·실제 로그인·cron 예약 실행 3회) OK, `b4-lab`과 스냅샷 동일(호스트 이름 정규화) | PASS |

(`PermitRootLogin yes`로 **재시작이 일어나던** 작업 14의 동작은 사라졌습니다. 이제 T2·T3·T4 모두 재시작 이전에 거부됩니다.)

**PENDING:** 롤백 후에도 `ssh.service`를 되살리지 못하는 최후 경로(서비스 파일 자체 손상 등), 새 조각이 디스크에 존재하는 극히 짧은 구간 중 새 SSH 접속이 설정을 다시 읽는지 여부(sshd는 연결마다 설정을 다시 읽지 않는다는 문서·동작에 근거하나 경합을 직접 재현하지는 않음), `b4-lab`에서의 실제 충돌 시험(금지 사항).

**하네스 오류 2건(스크립트 결함 아님):** ① 첫 T6 출력의 "점유 프로세스" 표시용 `grep` 패턴 오기(`\|`) ② 정리 명령의 `pkill -f b4-holder.py`가 자신의 `bash -c` 명령행에도 매칭돼 뒤따르던 `rm`이 실행되지 않아 임시 파일이 남았고, 직접 삭제했습니다. 이 시험 중 시험용 20022 점유 프로세스는 모두 종료·확인했습니다.

## 5. 검증 중 발견한 문제와 수정

- **오탐 1건(내 검사의 결함):** 첫 `b4-lab` `check`가 `envfile`을 DIFF로 보고했습니다. 환경변수 파일 **주석**의 "no secrets" 문구가 비밀 패턴(`secret`)에 걸린 것이라, 주석을 제외하고 값만 검사하도록 고쳤습니다(이후 `b4-lab` `check`: 12단계 모두 OK).
- **스크립트 결함 2건:** ① cron 대기 루프가 `grep -c … || echo 0`로 "0"을 두 번 출력해 산술 오류 ② root 거부를 "허가되지 않은 키로 시도 → `ROOT LOGIN REFUSED` 로그"로 판정하던 잘못된 가정(sshd는 root에게 허가된 키일 때만 그 로그를 남김). 각각 고쳤고, 후자는 Mac 쪽 검증을 "시도 거부 + 실효값 확인"으로 낮추고 위 6번처럼 공개키를 잠시 허가한 수동 시험으로 `ROOT LOGIN REFUSED`를 별도 증명했습니다.
- **측정 표기:** 첫 설치의 프로세스 종료 코드는 셸 `time` 파이프 때문에 출력되지 않았습니다. 결과는 요약줄(`failed=0`)과 이어진 2회차 `apply`·`check`로 확인했습니다.
- **작업 14에서 발견된 위험(작업 14-1에서 수정):** 충돌하는 `00-*.conf`가 있으면 `ssh` 단계가 재시작까지 한 뒤에야 실효값 불일치로 FAIL했습니다(잠시 Root 허용 설정으로 재시작). 이제 **재시작 이전에** `sshd -T` 실효 설정으로 거부합니다(§3.1, §4.1).

## 6. 아직 복구·검증하지 못하는 것 (PENDING / 의존성)

| 항목 | 이유 |
|---|---|
| **제공 Agent** (설치, 실행 계정, Boot Sequence 5단계, `Agent READY`, `0.0.0.0:15034` LISTEN) | 원본 미확보. 복구 대상에서 제외(`agent` 단계는 PENDING 출력만). 확보 후 `AGENT_PROCESS_PATTERN`·`AGENT_KEY_PATH`를 정하고 정상(exit 0) 경로를 cron 환경에서 실측해야 함 |
| 공식 미션 원문 대조 | 모든 값이 `[승인된 실습 설계]`/`[관리자료]`. 원문과 다르면 `config/`·스크립트를 수정하고 재검증 |
| `logrotate.timer`의 실제 발동, 10 MiB 도달 순환 | 시간 의존(다음 00:00 KST 이후). 이 작업에서는 확인하지 않음 |
| 새 Machine에서의 장기 동작 | 약 5분의 cron 관찰만 수행 |
| 패키지 버전 | 재구축 시점의 Ubuntu 저장소 버전을 설치함(이번에는 `b4-lab`과 동일했으나 고정하지는 않음) |
| `agent-*` 계정 SSH 접속 | 미구성(비밀번호 잠금, 키 없음) — 복구 대상 아님 |

## 7. 검증용 Machine 정리

`b4-recovery-test`는 검증 후 **중지**만 했고 삭제하지 않았습니다(사용자가 결과를 확인할 수 있도록). 불필요하면 `orb delete b4-recovery-test`로 지웁니다(이 Machine에만 해당, `b4-lab`은 영향 없음). 다시 쓰려면 `orb start b4-recovery-test`.
