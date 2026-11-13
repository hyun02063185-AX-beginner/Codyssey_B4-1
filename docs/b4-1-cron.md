# B4-1 cron 매분 자동 실행 (작업 13)

- 일시: 2026-11-13 / 기준 커밋 `171658b`
- 범위: `agent-admin` crontab에 `monitor.sh` 매분 등록, 실제 예약 실행·로그 누적 검증. Agent 대체 구현, SSH·UFW·ACL·소속 변경, 새 sudo 권한, bootstrap은 하지 않음.
- 값의 구분: **[승인된 실습 설계]** / **[적용됨]** / **[실측]**. 주기(`* * * * *`)·실행 계정(`agent-admin`)은 README `[관리자료]`, 나머지 형식은 설계 결정(공식 원문 미확인).

## 1. 적용된 crontab [적용됨]

`agent-admin`의 crontab(root가 아님). 기존에는 crontab이 없었습니다(`no crontab for agent-admin`).

```
# BEGIN B4-1 monitor (managed by scripts/monitor-cron.sh; do not edit inside)
* * * * * MONITOR_TRIGGER=cron /opt/agent-app/bin/monitor.sh >/dev/null 2>&1
# END B4-1 monitor
```

| 요소 | 이유 |
|---|---|
| `* * * * *` | 매분 |
| `/opt/agent-app/bin/monitor.sh` | 절대 경로. 로그인 셸·`.bashrc`에 의존하지 않고, 스크립트가 `/etc/default/agent-app`을 직접 로드 |
| `MONITOR_TRIGGER=cron` | 로그의 START 줄에 `trigger=cron`으로 남아 **수동 실행(`trigger=manual`)과 구별**됨 |
| `>/dev/null 2>&1` | 결과는 스크립트가 `monitor.log`에 직접 기록하므로 cron 출력은 버림. 출력이 없으므로 cron 메일이 생기지 않음(이 Machine에는 MTA도 없음, `/var/mail` 비어 있음) |

저장소: [scripts/monitor-cron.sh](../scripts/monitor-cron.sh)(등록·중지·재개·제거 관리), [config/crontab-agent-admin.example](../config/crontab-agent-admin.example)(내용 예시).

### 관리 스크립트 동작 (Machine 안에서 root로 실행) [실측]

관리 블록(BEGIN/END 사이)만 교체하므로 **기존 항목은 보존**되고 `install`을 몇 번 반복해도 **중복 등록되지 않습니다.** 먼저 다른 계정(`agent-test`)의 임시 crontab으로 검증한 뒤 실제 계정에 적용했습니다(임시 crontab은 제거).

| 검증 | 결과 |
|---|---|
| `install` ×3 | 관리 블록 1개, 작업 줄 1개 |
| 기존 항목(`0 0 1 1 * /bin/true # keep-me`) | install·pause·resume·remove 후에도 보존 |
| `pause` / `resume` / `remove` | 작업 줄 주석 처리(`#PAUSED# `) / 복구 / 관리 블록만 제거 |
| 일반 사용자 실행 | `run as root (sudo)`, exit 2 |

**스크립트 버그와 수정:** 첫 검증에서 `status`가 `pause` 후에도 `state=ACTIVE`로 표시했습니다(크론탭 내용은 올바르게 주석 처리됐으나 `grep -F` 부분 일치가 `#PAUSED# …` 줄 안의 작업 문자열에 매칭됨). 줄 전체 일치(`grep -x`)로 고쳐 `PAUSED` 표시를 확인했습니다.

## 2. cron 서비스 상태 [실측]

`cron 3.0pl1-184ubuntu2`, `systemctl is-enabled cron` = enabled, `is-active` = active. `/etc/cron.allow`·`cron.deny` 없음(제한 없음). `agent-admin`은 비밀번호가 잠겨 있지만(`!`) cron 세션이 정상 열림(`pam_unix(cron:session): session opened for user agent-admin(uid=1000)`). 다른 계정(root, 기본 사용자, `agent-dev`, `agent-test`)의 crontab은 없음.

## 3. 자동 실행 검증 [실측]

등록 직전 기준값: 로그 50줄 / 5685 B / 마지막 기록 2026-11-13 16:55:35(이후 5회의 검증 실행분, 모두 수동). 등록 시각 17:02:55.

| # | 항목 | 결과 | 판정 |
|---|---|---|---|
| 1 | 매분 `agent-admin`으로 실행 | journal: `CRON[…]: (agent-admin) CMD (MONITOR_TRIGGER=cron /opt/agent-app/bin/monitor.sh >/dev/null 2>&1)` 매분 `:01`초, 세션 사용자 `agent-admin(uid=1000)` | PASS |
| 2 | 실행 횟수 | 17:03:01부터 **연속 매분 실행**. 검증 시점(17:08:50)까지 6회, **빠진 분 0**. 등록 직후 5회째까지 대기해 확인 후에도 계속 누적 | PASS (3회 이상) |
| 3 | 실제 `monitor.log` 추가 | 50줄 → 120줄(cron 6회 × 10줄 + 수동 1회 × 10줄). 모든 실행이 정확히 10줄 | PASS |
| 4 | START·SUMMARY·시각 구분 | 각 실행이 `START`(예: `17:04:01`) ~ `SUMMARY`(`17:04:03`)로 구분되고 실행 시간은 약 1~2초 | PASS |
| 5 | 수동 / cron 구별 | START 줄 `trigger=cron`(6회) vs `trigger=manual`(검증용 수동 1회, 17:07:30). 등록 이전의 5회 수동 실행은 `trigger` 필드 도입 이전이라 필드가 없음 | PASS |
| 6 | 그룹 소속 반영 | cron 프로세스의 `id`: `groups=agent-admin,agent-common,agent-core`. START 줄 `groups=` 필드도 동일. 또한 로그 디렉터리(`root:agent-core 2770`)는 비소유자에게 `agent-core` 그룹이 있어야 접근되므로 쓰기 성공 자체가 반영의 증거 | PASS |
| 7 | 환경변수 로드 | 임시 관찰 항목으로 cron 환경을 덤프(§3.1). `AGENT_*` 변수 없음 → 스크립트가 `/etc/default/agent-app`을 직접 로드. 매 실행의 `CONFIG AGENT_HOME=/opt/agent-app AGENT_PORT=15034 …` 줄이 이를 증명 | PASS |
| 8 | 장애 감지 기록 | 매 실행 `[PENDING] PROCESS …AGENT_PROCESS_PATTERN unset`, `[FAIL] PORT tcp/15034 not LISTEN`, `[UNKNOWN] FIREWALL …`(`agent-admin`은 sudo 없음) | PASS |
| 9 | 종료 코드 1의 해석 | 모든 SUMMARY가 `result=UNHEALTHY exit=1`(§4) | PASS |
| 10 | 기존 로그 보존 | 앞 5685 bytes가 등록 전과 바이트 단위 동일(sha256 `eb6da03736e4`) | PASS |
| 11 | 중복·잔여 | 관리 블록 1개, 작업 줄 1개, 임시 항목 제거 확인, `monitor.sh` 프로세스 0개(수 초만 실행), 임시 파일 삭제 | PASS |
| 12 | 메일 | cron 출력 없음, `/var/mail` 비어 있음, MTA 없음 | PASS |
| 13 | 회귀 | 아래 §5 | PASS |

로그 증가: 실행 1회 = 10줄 ≈ 1.1 KB(120줄 = 14038 B에서 환산). 매분 실행이면 약 1.6 MB/일(**추정**, 실측은 위 6분치). `0660 agent-admin:agent-core` 및 ACL은 cron 기록 중에도 유지됨.

### 3.1 cron 환경 관찰 (임시 항목, 관찰 후 제거)

관리 블록과 별도로 `* * * * * (id; env) > /tmp/b4-cron-env.txt` 임시 항목을 잠시 두고 cron 실행 환경을 확인한 뒤 즉시 제거했습니다.

```
uid=1000(agent-admin) gid=1002(agent-admin) groups=1002(agent-admin),1000(agent-common),1001(agent-core)
HOME=/home/agent-admin   LOGNAME=agent-admin   SHELL=/bin/sh   PWD=/home/agent-admin   LANG=en_US.UTF-8
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin
```

(`/tmp`의 sticky 비트 때문에 기본 사용자는 `agent-admin` 소유 임시 파일을 지우지 못해 `sudo rm`으로 정리했습니다.) `monitor.sh`는 자체적으로 `PATH`를 고정하므로 cron의 `PATH`에 의존하지 않습니다.

## 4. 장애 감지와 실행 오류의 구분

| 상태 | 의미 | 확인 방법 |
|---|---|---|
| **cron이 정상 실행 + 스크립트 `exit 1`** (현재) | cron은 매분 스크립트를 실행했고, 스크립트가 Agent 부재·포트 미LISTEN을 **정상적으로 검출**한 것 | `monitor.log`의 `START`/`SUMMARY result=UNHEALTHY exit=1`, journal의 `CRON … CMD` |
| **스크립트 `exit 2`** | 모니터링 자체 오류(설정·수집·로그 쓰기 오류) | `SUMMARY result=MONITOR_ERROR`, `[ERROR]` 줄 |
| **cron 미실행** | 서비스·crontab·권한 문제 | `monitor.log`에 새 START가 없음, journal에 `CRON … CMD` 없음, `systemctl status cron` |

중요한 관찰: **cron은 작업의 종료 코드를 기록하지도 오류로 취급하지도 않습니다**(journal에서 exit/status/failed 관련 줄 0건). `exit 1`은 `monitor.log`의 SUMMARY로만 확인할 수 있고, cron 입장에서는 "실행 성공"입니다. 이번 검증에서 cron 실행 실패, 로그 쓰기 실패(`ERROR LOG`)는 없었습니다.

**알려진 감시 공백(미해결):** 출력을 `/dev/null`로 버리므로 **로그를 쓸 수 없는 상황**(디스크 가득, 권한 문제)에서는 `ERROR LOG` 메시지(stdout 전용)가 어디에도 남지 않고, 그저 로그에 새 줄이 생기지 않는 것으로만 드러납니다. 로그 신선도(마지막 기록 시각)를 점검하거나, 스크립트가 로그 실패 시 `logger`로 syslog에 남기게 하는 보완을 다음 작업으로 남깁니다(이번에는 구현하지 않음).

## 5. 로그 순환·회귀 확인 [실측]

| 항목 | 결과 | 판정 |
|---|---|---|
| `/etc/logrotate.d/agent-app` | 저장소 파일과 동일(`cmp`), `logrotate -d`: 오류 없음, `does not need rotating` | PASS |
| `logrotate.timer` | enabled·active, 다음 실행 2026-11-14 00:00 KST(이번 작업에서 수동 실행·강제 순환 없음, 다른 시스템 로그 영향 없음) | PASS |
| cron 기록 중 로그 파일 | `660 agent-admin:agent-core`, `group::rw-`, `other::---` 유지 | PASS |
| **타이머가 실제로 이 설정을 실행** | 아직 발동 전(`journalctl -u logrotate`에 17:00 이후 항목 없음, state 파일의 마지막 갱신 기록은 비강제 확인 시점) → 다음 00:00 이후 `journalctl -u logrotate`·`/var/lib/logrotate/status`로 확인해야 함 | **PENDING** |
| 실제 로그의 10 MiB 도달·순환 | 현재 약 14 KB | **PENDING** |
| monitor 회귀 | 작업 10-1 스위트 42 PASS / 0 FAIL. 작업 10 스위트 40/3은 이전과 동일한 3건(하네스 패턴 오기 1 + 판정 강화에 따른 의도된 변경 2) | PASS |
| 환경 회귀 | SSH 20022 접속·`ssh b4-lab@orb`, `permitrootlogin no`, UFW active·허용 규칙 4개, 그룹 소속, 디렉터리 소유·mode·ACL(`group:agent-core:rwx`, default 포함), `agent-*` sudo 없음, `upload_files`·`api_keys` 비어 있음 | PASS |

## 6. 중지·재개·제거 (Mac 터미널에서)

```bash
cd Codyssey_B4-1
orb -m b4-lab sudo bash -s -- status  < scripts/monitor-cron.sh   # 상태: ACTIVE / PAUSED / NOT_INSTALLED
orb -m b4-lab sudo bash -s -- pause   < scripts/monitor-cron.sh   # 일시 중지(작업 줄을 주석 처리, 기록은 유지)
orb -m b4-lab sudo bash -s -- resume  < scripts/monitor-cron.sh   # 재개
orb -m b4-lab sudo bash -s -- remove  < scripts/monitor-cron.sh   # 관리 블록 제거(기존 다른 항목은 보존)
```

중지해도 `monitor.log`는 삭제되지 않습니다. 직접 확인: `orb -m b4-lab sudo crontab -u agent-admin -l`.

## 7. 교육장 Mac 초기화 후 재구성

전제(순서): 사용자·그룹(12장) → 소속·디렉터리·ACL(권한 설계 11장) → `/etc/default/agent-app`(Agent 실행환경 4장) → `monitor.sh` 배포 및 로그 파일(monitor 기록 §6) → logrotate 설정(로그 순환 기록 §6).

```bash
cd Codyssey_B4-1
orb -m b4-lab sudo bash -s -- install < scripts/monitor-cron.sh   # 재실행해도 중복 등록되지 않음
orb -m b4-lab sudo crontab -u agent-admin -l                      # 확인
# 1~2분 후 확인
orb -m b4-lab sudo tail -n 12 /var/log/agent-app/monitor.log      # START ... trigger=cron ... SUMMARY
orb -m b4-lab sudo journalctl -u cron --since "-5min" --no-pager | grep agent-admin
```

## 8. 남은 문제·다음 작업 주의

1. **타이머 발동 확인(PENDING):** 2026-11-14 00:00 KST 이후 `journalctl -u logrotate`, `/var/lib/logrotate/status`. 10 MiB 도달 순환은 약 6일 후로 추산(추정).
2. cron이 종료 코드를 남기지 않으므로 **로그 신선도 점검** 또는 로그 쓰기 실패의 syslog 기록 도입 검토(§4).
3. Agent 확보 후: `AGENT_PROCESS_PATTERN` 설정, 정상(exit 0) 기록을 cron 환경에서 실측, Agent 실행 계정과 PID 가시성 관계(`agent-admin`이 아니면 `PENDING`).
4. `agent-admin` sudo가 없어 UFW 상태는 계속 `UNKNOWN`(권한 부여 여부 결정 필요).
5. 임계값·로그 포맷·종료 코드·주기를 공식 원문과 대조(현재 임시 설계).
6. 매분 로그가 누적되므로 모니터링·순환 정책이 의도대로 도는지 주기적으로 확인.
