# B4-1 디렉터리 권한·ACL 설계 (작업 7)

- 작성: 2026-11-13 / 기준 커밋 `d9b3da2`
- **상태: 설계 초안 + ACL 동작 실습 검증(7-1, §10).** 실제 Agent 디렉터리 생성, `usermod`, 실제 경로 `chown`/`chmod`/`setfacl`은 아직 하지 않았습니다. 7-1에서 `acl` 패키지만 설치했고 `/tmp` 임시 실습 디렉터리는 정리했습니다. 검수 후 다음 작업에서 적용합니다.
- 출처 표기: `[관리자료]` 저장소 README 기준 / `[Notion]` Notion B4-1 페이지(unverified, 공식 원문과 1:1 대조 **아님**) / `[설계]` 이 문서의 제안 / `확인 필요`.

## 1. 요구사항 정리

| 항목 | 내용 | 출처 | 상태 |
|---|---|---|---|
| `upload_files` | `agent-common` R/W | [관리자료] [Notion] | 그룹·권한 종류만 확정 |
| `api_keys` | `agent-core` **만** R/W | [관리자료] [Notion: "agent-core만"] | "만"(타 그룹 차단) 표현은 Notion 요약에만 있음. 원문 대조 필요 |
| `/var/log/agent-app` | `agent-core` **만** R/W | [관리자료] [Notion] | 경로는 확정값으로 취급 가능(README·Notion 일치), 원문 대조 필요 |
| 로그 파일 | `/var/log/agent-app/monitor.log`, 최대 10MB × 10개 | [Notion] | 순환 방식 확인 필요 |
| cron 실행 계정 | `agent-admin`, 매분 | [관리자료] [Notion] | 확정 |
| Agent 실행 | "일반 계정"으로 실행 (어느 계정인지 미기재) | [Notion] | **확인 필요** |
| 환경변수 | `AGENT_HOME`, `AGENT_PORT`, `AGENT_UPLOAD_DIR`, `AGENT_KEY_PATH`, `AGENT_LOG_DIR` | [Notion] | 값·위치 확인 필요 |
| `monitor.sh` 위치 | `$AGENT_HOME/bin/monitor.sh`, 소유자/그룹/권한 정책을 맞출 것 | [Notion] | 정책 값 확인 필요 |
| **사용자 ↔ 그룹 소속** | — | — | **확인 필요** (원문 미확인) |
| `upload_files`·`api_keys` 절대경로 | — | — | **확인 필요** |
| 소유자, 숫자 mode, ACL 세부 | — | — | **확인 필요** |

공식 원문·제공 Agent 파일은 저장소와 Mac(홈 하위 3단계)에서 찾지 못했습니다. 따라서 위 "확인 필요" 값은 확정하지 않았습니다.

## 2. 현재 상태 (읽기 전용 조사, 2026-11-13)

| 항목 | 결과 |
|---|---|
| Git | main = `origin/main`, 작업 트리 clean |
| 사용자 | `agent-admin`(uid 1000), `agent-dev`(1001), `agent-test`(1002). 각자 개인 그룹(gid 1002/1003/1004)에만 소속 |
| 그룹 | `agent-common`(gid 1000), `agent-core`(gid 1001) — **멤버 0명** |
| 대상 디렉터리 | `/var/log/agent-app`, `upload_files`, `api_keys`, `/opt/agent*`, `/srv/agent*` 모두 **없음** |
| Agent 파일 | Machine·Mac 모두 없음 (`ssh-agent` 등 무관 파일만 검색됨) |
| 파일시스템 | `/` = btrfs, 커널 `CONFIG_BTRFS_FS_POSIX_ACL=y`, `noacl` 마운트 옵션 없음 → POSIX ACL 사용 가능 |
| `getfacl`/`setfacl` | 조사 시점(작업 7)에는 미설치 → **7-1에서 `acl 2.3.2-1build1.1` 설치 완료** |
| 기본값 | `UMASK 022`, `HOME_MODE 0750`, `/var/log`은 `root:syslog 775` |
| sudo | 기존 사용자만 sudo 가능, `agent-*`는 불가 |
| SSH / UFW | `port 20022`, `permitrootlogin no`, ssh active / UFW active, 허용 20022·15034 (변경 없음) |

## 3. 그룹·사용자 역할

그룹 목적(요구사항에서 도출):

| 그룹 | 목적 |
|---|---|
| `agent-common` | 업로드 파일 영역(`upload_files`) 공동 접근 |
| `agent-core` | 민감 영역(`api_keys`)과 Agent 로그(`/var/log/agent-app`) 접근 |

사용자 역할은 원문에 없습니다. 이름과 요구사항에서 **추정**한 것이며 확정값이 아닙니다.

| 사용자 | 역할 (추정) | 근거 |
|---|---|---|
| `agent-admin` | 운영/관제. cron으로 `monitor.sh` 실행, 로그 기록 | cron 계정 = `agent-admin` (확정) |
| `agent-dev` | 개발 | 이름 기반 추정 |
| `agent-test` | 테스트·접근 제한 검증 | 이름 기반 추정 |

## 4. 사용자 × 그룹 소속 — 검수용 제안안

**현재 값은 모두 "없음"(적용 전)이며, 아래는 확정이 아닌 제안입니다.** 소속은 사용자가 결정/확인해야 합니다.

> **정정(7-1):** 작업 7 초안은 "`agent-admin`의 `agent-core` 가입이 필수에 가깝다"고 썼으나 **과한 표현**이었습니다. cron 계정이 로그를 쓰려면 "쓰기 권한"이 필요한 것이지 "그룹 가입"이 필요한 것이 아닙니다. 권한은 소유자·그룹 소속·개별(named user) ACL 세 경로로 부여할 수 있고(§10 실측), 어느 쪽이 맞는지는 원문의 의도("core만")에 달려 있습니다. 아래는 대안 비교입니다.

### 4.1 cron 계정(`agent-admin`)의 로그 쓰기 확보 방법 비교

| 방법 | 구성 | `agent-admin`의 `/var/log/agent-app` | `agent-admin`의 `api_keys` | 장점 | 단점/주의 |
|---|---|---|---|---|---|
| **X. 그룹 소속** | `agent-admin` ∈ `agent-core` | R/W (그룹) | **R/W** (같은 그룹이므로) | 단순, `ls`로 한눈에 파악 | 키 접근까지 함께 부여됨. 키 접근이 의도가 아니라면 과권한 |
| **Y. 소유권** | 로그 디렉터리를 `agent-admin:agent-core 2770`으로 | R/W (소유자, 비멤버여도 가능 — §10 A) | 불가(키 디렉터리는 비멤버 차단) | 키 접근은 분리, 추가 도구 불필요 | 로그 디렉터리 "owner"가 core 외 계정 → "core만"을 엄격히 해석하면 예외가 생김. 소유자는 chmod로 권한을 바꿀 수 있음 |
| **Z. 개별 ACL** | `root:agent-core 2770` + `u:agent-admin:rwx`(로그 디렉터리에만) | R/W (개별 ACL, 비멤버여도 가능 — §10 B) | 불가 | 최소 범위로 명시, 감사 가능(`getfacl`) | `ls -l`에 `+`만 표시되어 놓치기 쉬움. mask 주의(§10 C). "core만"과 문자 그대로는 충돌 |

### 4.2 `api_keys`에 실제 접근 가능한 계정 (제안안별)

root는 항상 접근 가능하며 아래 표에서는 제외합니다. "소속"은 제안이며 확정이 아닙니다.

| 제안안 | `agent-core` 멤버 | 그 외 접근 가능 | 접근 불가 |
|---|---|---|---|
| **P1:** admin ∈ core + common (방법 X) | `agent-admin` (+ core에 넣기로 한 다른 계정) | 없음(`api_keys` owner = root 가정) | `agent-dev`/`agent-test` (core 비멤버일 때) |
| **P2:** admin ∉ core, 로그만 방법 Y/Z | core에 넣기로 한 계정(미정, Agent 실행 계정 등) | 로그 디렉터리의 owner/ACL 사용자(**api_keys에는 해당 없음**), `api_keys` owner가 root이면 추가 없음 | `agent-admin`(키 접근 불가), 나머지 |
| **P3:** Agent 실행 계정만 core | Agent 실행 계정(미정) | — | admin·나머지. cron 로그 쓰기는 방법 Y/Z로 해결 |

핵심: 키에 대한 접근 범위는 **api_keys 디렉터리의 owner, `agent-core` 멤버, 개별 ACL** 의 합집합이며, 로그 쓰기를 위해 `agent-core` 소속을 주면 키 접근이 함께 따라옵니다(방법 X). 키를 분리하려면 방법 Y/Z가 필요합니다.

### 4.3 사용자 × 그룹 소속 (제안 틀, 모두 확인 필요)

| 사용자 | `agent-common` | `agent-core` | 비고 |
|---|---|---|---|
| `agent-admin` | 확인 필요 | 확인 필요 (§4.1 X 또는 Y/Z) | cron 계정. 로그 쓰기 방법은 §4.1에서 결정 |
| `agent-dev` | 확인 필요 | 확인 필요 | 원문 없음 |
| `agent-test` | 확인 필요 | 확인 필요 | 비소속으로 두면 차단 테스트 대상으로 활용 가능 |

미확정인 질문(검수 시 답이 필요):
1. 각 사용자의 그룹 소속은?
2. Agent는 어느 계정으로 실행하는가? (그 계정이 `upload_files`·`api_keys`·로그에 접근해야 함)
3. cron 계정의 로그 쓰기는 X/Y/Z 중 무엇으로? (`agent-admin`이 키에 접근해도 되는가?)

## 5. 디렉터리별 접근 정책

경로·소유자·mode는 `[설계]` 제안이며 확정이 아닙니다. 단 `/var/log/agent-app`은 확정 경로입니다.

| 디렉터리 | 경로(제안) | 소유자:그룹(제안) | mode(제안) | ACL(제안) | 접근 허용 |
|---|---|---|---|---|---|
| Agent 홈 | `AGENT_HOME=/opt/agent-app` (확인 필요) | `root:root` | `755` | — | 전체 읽기/탐색(실행 파일 배치 용) |
| 업로드 | `/opt/agent-app/upload_files` (확인 필요) | `agent-admin:agent-common` | `2770` (setgid) | `d:g:agent-common:rwx`, `g:agent-common:rwx`, `o::---` | `agent-common` R/W, 타 사용자 불가 |
| 키 | `/opt/agent-app/api_keys` (확인 필요) | `root:agent-core` (owner를 일반 계정으로 두면 그 계정도 키에 접근하므로 §4.2 참고) | `2770` (setgid) | `d:g:agent-core:rwx`, `g:agent-core:rwx`, `o::---`, 파일 기본 `660` | `agent-core`만 R/W |
| 로그 | `/var/log/agent-app` (확정 경로) | `root:agent-core` 또는 `agent-admin:agent-core` | `2770` (setgid) | `d:g:agent-core:rwx`, `g:agent-core:rwx`, `o::---` | `agent-core`만 R/W |

설계 메모:
- **setgid(`2xxx`)**: 새 파일이 디렉터리 그룹을 상속하도록 하여 그룹 공유 유지.
- **default ACL(`d:`)**: 실측(§10 E): default ACL이 있는 디렉터리에서는 **umask가 적용되지 않고** 요청 mode(touch/`echo >`는 0666)가 default ACL과 교차되어 새 파일이 `rw-rw----`가 됨(umask 022·077 모두 동일). 새 디렉터리는 `rwxrws---`. 단 새 **파일**의 mask는 `rw-`이므로 named 엔트리의 effective도 `rw-`(실행 비트 없음).
- **`o::---`(타 사용자 차단)**: "그룹 외 접근 불가" 확인 항목(README 체크리스트)에 대응.
- **개인 홈 하위에 두지 않는 이유**: 홈은 `750`이라 다른 그룹 멤버가 상위 디렉터리를 통과(`x`)하지 못함. `/opt` 하위는 상위 통과 문제가 없음. 다만 AGENT_HOME 위치가 원문에 지정돼 있으면 그 값을 따라야 함 → 확인 필요.
- **`chmod`와 ACL의 관계**: 실측(§10 C): ACL이 있으면 `ls`의 그룹 비트는 mask를 표시하고, `chmod g-w`가 mask를 `r-x`로 낮춰 **named user·group 엔트리의 쓰기까지 모두 막음**(`#effective:r-x`). `chmod g+w`로 복구하면 다시 허용됨. 따라서 chmod 후에는 반드시 `getfacl`로 effective 권한을 재확인.
- **상위 디렉터리 통과(`x`)**: 실측(§10 F): 안쪽 디렉터리의 owner라도 상위 디렉터리가 `x`를 주지 않으면 접근 불가. 부모에 `g:agent-dev:--x`를 주면 해당 그룹만 통과.
- **`mv`/`cp` 주의**: 실측(§10 G): `mv`는 원본 파일의 mode를 유지하므로 default ACL 디렉터리로 옮겨도 default ACL이 적용되지 않음(원본 644 그대로). 로그 순환 시 `mv`·rename으로 만든 파일은 mode를 직접 확인/보정해야 함.
- **ACL을 쓸지 chmod만 쓸지**: 그룹 하나에만 R/W를 주는 요구라면 소유 그룹 + `2770`만으로도 충족 가능. ACL은 "권한/ACL 구성"이라는 요구 표현과 default 상속 때문에 사용하는 안. 원문이 ACL을 명시하는지 확인 필요.

## 6. 연관성

- **cron/`monitor.sh`**: `agent-admin`이 매분 `/var/log/agent-app/monitor.log`에 append. 필요 조건: 로그 디렉터리에 대한 `x`+`w` 권한을 **소유자·그룹 소속·개별 ACL 중 하나로** 확보(§4.1; 그룹 가입은 필수가 아님). 로그 파일 생성 시 mode가 그룹 쓰기를 유지해야 함(setgid + default ACL 필요).
- **로그 순환(10MB/10개)**: 순환 시 새 파일·압축 파일이 같은 그룹/권한을 유지해야 함. logrotate 사용 시 `create` 지시자의 mode/owner/group, 또는 `monitor.sh` 자체 순환 여부는 확인 필요.
- **Agent 실행**: Agent가 `AGENT_KEY_PATH`(api_keys)를 읽고 `AGENT_UPLOAD_DIR`에 쓰고 `AGENT_LOG_DIR`에 기록한다면 실행 계정이 `agent-common`과 `agent-core` 모두에 속해야 할 수 있음 → 실행 계정·Agent 요구사항 확인 후 결정.
- **환경변수**: cron은 로그인 셸 환경을 상속하지 않으므로 `monitor.sh`가 쓰는 경로는 스크립트/crontab에서 명시해야 함(별도 작업).
- **SSH**: `agent-*`는 현재 접속 불가(비밀번호 잠금, 키 없음). 접근 테스트는 `sudo -u`로 수행하는 안(§7).

## 7. 적용 후 테스트 계획

실행 방법은 `sudo -u <user> ...`(기존 sudo 사용자). 기대값은 **소속이 확정된 뒤** 채웁니다. 아래는 틀이며, §4.1의 X/Y/Z 선택에 따라 admin의 기대값이 달라집니다. 메커니즘 자체는 §10에서 임시 디렉터리로 실측 검증했습니다.

| # | 대상 | 동작 | 기대 | 확인 포인트 |
|---|---|---|---|---|
| 1 | `agent-common` 멤버 | `upload_files`에 파일 생성/읽기/수정 | 성공 | 새 파일 그룹이 `agent-common`(setgid) |
| 2 | `agent-core` 멤버 | `api_keys`에서 생성/읽기 | 성공 | 새 파일 mode `660` 수준 |
| 3 | `agent-core` 멤버 | `/var/log/agent-app`에 append | 성공 | 생성 파일 그룹 `agent-core` |
| 4 | 비소속 사용자 | `upload_files`, `api_keys`, 로그 디렉터리 `ls`/읽기/쓰기 | 모두 `Permission denied` | `other` 차단(`o::---`) |
| 5 | `agent-common` 전용 멤버 | `api_keys`, 로그 접근 | 거부 | "core만" 요구 검증 |
| 6 | `agent-core` 전용 멤버 | `upload_files` 접근 | 소속에 따라 결정 | 확인 필요 |
| 7 | 파일 생성 후 | `getfacl`, `ls -ld`, `stat` | ACL·mask·owner 설계와 일치 | 디렉터리 mask `rwx`, 파일 mask `rw-` (§10 E) |
| 8 | 상속 | 새 하위 파일/디렉터리 | default ACL 상속 | |
| 9 | cron 실사용 | `agent-admin`으로 로그 append 후 다음 분 재확인 | 성공 | cron 작업에서 최종 검증 |
| 10 | 회귀 | SSH 20022, UFW 규칙, 기존 사용자 | 변경 없음 | |

거부 테스트는 "원래 접근할 수 없는 이유"(경로 없음, 상위 `x` 없음)와 구분해야 하므로, 허용 계정으로 같은 경로가 접근됨을 먼저 확인합니다.

## 8. 적용 전 추가 확인 필요 항목

1. 사용자별 `agent-common`/`agent-core` 소속 (§4 제안안 검수)
2. Agent 실행 계정과 그 계정의 필요 접근권
3. `upload_files`, `api_keys`의 절대경로, `AGENT_HOME` 위치
4. 각 디렉터리의 소유자·숫자 mode·ACL 지정 여부, ACL 필수 여부
5. `monitor.sh`·`bin` 디렉터리의 소유자/그룹/권한 정책
6. 로그 순환 방식(logrotate vs 스크립트), 로그 파일 mode
7. 공식 원문과 위 Notion 요약의 대조 (특히 "agent-core만")
8. ~~`acl` 패키지 설치~~ → 7-1에서 설치 완료
9. cron 계정의 로그 쓰기 방식 선택(§4.1 X/Y/Z)과 `agent-admin`의 키 접근 허용 여부
10. 파일을 **명시적 mode**(예: 0644)로 만드는 프로그램이 default ACL 디렉터리에서 어떻게 보이는지는 미실측(§10은 touch/`echo >`의 0666 요청만 검증)

## 9. 재현 명령 초안 (**미실행·미검증, 값은 확인 후 확정**)

```bash
# 0) ACL 도구 (7-1에서 설치됨, 재설치 시 필요)
sudo apt-get install -y acl

# 1) 그룹 소속 (확정 후에만 실행) — 예시 자리표시
# sudo usermod -aG agent-common,agent-core agent-admin   # <확인 필요>
# sudo usermod -aG <그룹> agent-dev agent-test            # <확인 필요>

# 2) 디렉터리 (경로는 확인 필요)
sudo install -d -o root -g root -m 0755 /opt/agent-app
sudo install -d -o agent-admin -g agent-common -m 2770 /opt/agent-app/upload_files
sudo install -d -o root        -g agent-core   -m 2770 /opt/agent-app/api_keys
sudo install -d -o root        -g agent-core   -m 2770 /var/log/agent-app

# 3) ACL
sudo setfacl -m  g:agent-common:rwx,o::--- /opt/agent-app/upload_files
sudo setfacl -dm g:agent-common:rwx,o::--- /opt/agent-app/upload_files
sudo setfacl -m  g:agent-core:rwx,o::---   /opt/agent-app/api_keys /var/log/agent-app
sudo setfacl -dm g:agent-core:rwx,o::---   /opt/agent-app/api_keys /var/log/agent-app

# 4) 확인
getfacl /opt/agent-app/upload_files /opt/agent-app/api_keys /var/log/agent-app
ls -ld /opt/agent-app/* /var/log/agent-app
id agent-admin agent-dev agent-test
```

`bootstrap-orbstack.sh`에는 검수·적용·검증이 끝난 뒤에만 반영합니다.

## 10. ACL 실습 검증 결과 (작업 7-1)

- 일시: 2026-11-13 / 기준 커밋 `8037742`
- 방법: Machine 내부 `/tmp/b4-acl-lab`(root 소유 임시 디렉터리)에서 `agent-*` 계정으로 `sudo -u`를 통해 실행. **그룹 소속은 변경하지 않음.** `agent-common`/`agent-core`는 멤버가 없어 이 그룹 자체로는 멤버 테스트가 불가능하므로, 기존 소속만 사용해 `agent-dev`의 개인 그룹(`agent-dev`)을 "그룹" 역할의 **대역**으로 썼습니다. 메커니즘(소유자·그룹·named user ACL·mask·setgid·default ACL) 검증이며, 실제 `agent-core`/`agent-common` 정책의 최종 검증이 아닙니다.
- 역할 대역: `agent-admin` = 소유자 / 개별 ACL 대상(그룹 비멤버), `agent-dev` = 그룹 멤버, `agent-test` = 비허용(other).
- 판정은 허용 대상이 먼저 성공함을 확인한 뒤 거부를 확인하는 구조라 "경로 없음"으로 인한 오판은 없음.
- 정리: 실습 종료 후 `/tmp/b4-acl-lab` 삭제 및 부재 확인. 그룹 소속·SSH·UFW 변경 없음(재확인).

| # | 시나리오 | 결과 | 판정 |
|---|---|---|---|
| A | 디렉터리 `agent-admin:agent-dev 2770` | 소유자 `agent-admin`(그룹 비멤버) 쓰기 성공, 그룹 멤버 `agent-dev` 읽기/쓰기 성공, `agent-test` ls·쓰기 거부 | PASS |
| B | `root:agent-dev 2770` + `u:agent-admin:rwx` | ACL 전: `agent-admin` 거부 → ACL 후 쓰기·읽기 성공. 그룹 멤버 유지, `agent-test` 거부 유지 | PASS |
| C | `chmod g-w`(mask 영향) | `mask::r-x`가 되어 `user:agent-admin`(rwx 설정)·`group::` 모두 `#effective:r-x`. `agent-admin`·`agent-dev` 쓰기 거부, 읽기 성공. `chmod g+w` 후 쓰기 복구 | PASS |
| D | setgid 유무 | 2770(setgid): 새 파일·하위 디렉터리 그룹 = `agent-dev`(디렉터리는 `s` 비트 상속). 0770(setgid 없음): 새 파일 그룹 = 작성자 개인 그룹 `agent-admin` | PASS |
| E1 | default ACL 없음, umask 022 | 새 파일 `-rw-r--r--` → 그룹 멤버 쓰기 거부 | PASS |
| E2 | default ACL(`g:agent-dev:rwx,o::---`) | 새 파일 `-rw-rw----`(group·named `#effective:rw-`, mask `rw-`, other `---`), 새 디렉터리 `drwxrws---`. 그룹 멤버 쓰기 성공, `agent-test` 읽기 거부 | PASS |
| E3 | default ACL + umask 077 | 새 파일 여전히 `-rw-rw----`, 그룹 쓰기 성공 → default ACL 디렉터리에서는 umask가 적용되지 않음 | PASS |
| E4 | `echo >` 로 생성 | `-rw-rw----` (touch와 동일) | PASS |
| F | 상위 디렉터리 `750 root:root` 아래 안쪽 `agent-admin:agent-dev 2770` | owner 거부 → 부모에 `g:agent-dev:--x` 추가 후 그룹 멤버 성공, `agent-test` 거부 유지 | PASS |
| G | `cp`/`mv` | `cp`는 원본 mode ∩ umask(660→`rw-r-----`), `mv`는 원본 mode(644) 유지, default ACL 미적용 | 참고(관찰) |

FAIL 항목 없음. 설계에 반영한 결론:
1. 로그 쓰기 권한은 그룹 가입 없이도 소유자·개별 ACL로 부여할 수 있음(§4.1).
2. 키 디렉터리 접근 범위는 owner ∪ core 멤버 ∪ 개별 ACL(§4.2).
3. setgid는 새 파일의 그룹 상속에 필요(없으면 작성자 개인 그룹이 됨).
4. default ACL은 umask를 우회해 그룹 쓰기를 유지하지만 파일의 mask는 `rw-`.
5. chmod는 mask를 통해 named 엔트리의 effective 권한을 줄이므로 변경 후 `getfacl` 재확인.
6. 로그 순환(`mv`)은 mode를 승계하므로 순환 방식에 따라 mode 보정이 필요.

미검증: 실제 `agent-core`/`agent-common` 멤버 기준 동작(소속 미확정), 명시적 mode로 파일을 만드는 프로그램의 동작, logrotate 연동, cron 환경에서의 실제 쓰기.

### 적용 단계에 필요한 최소 결정 사항

1. 사용자별 그룹 소속(공식 원문 또는 사용자 결정).
2. cron 계정의 로그 쓰기 방식 X/Y/Z, 및 `agent-admin`의 키 접근 허용 여부.
3. Agent 실행 계정.
4. `upload_files`/`api_keys` 절대경로와 `AGENT_HOME`.
