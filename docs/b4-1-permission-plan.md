# B4-1 디렉터리 권한·ACL 설계 (작업 7)

- 작성: 2026-11-13 / 기준 커밋 `d9b3da2`
- **상태: 설계 초안. 아직 아무것도 적용하지 않았습니다**(디렉터리 생성, `usermod`, `chown`, `chmod`, `setfacl` 모두 미실행). 검수 후 다음 작업에서 적용합니다.
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
| `getfacl`/`setfacl` | **미설치**. `acl` 패키지가 apt 후보(2.3.2-1build1.1)로 존재 → 적용 단계에서 `apt install acl` 필요 |
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

| 사용자 | `agent-common` | `agent-core` | 제안 근거 |
|---|---|---|---|
| `agent-admin` | 제안: 소속 | **필수에 가까움** | cron이 `/var/log/agent-app`에 써야 함 → `agent-core` 소속이 아니면 로그 기록 불가(요구가 "core만 R/W"이므로). 이 점은 요구사항에서 논리적으로 도출됨 |
| `agent-dev` | 확인 필요 | 확인 필요 | 원문 없음 |
| `agent-test` | 확인 필요 | 확인 필요 | 원문 없음. 접근 차단 테스트용(비소속)으로 쓰는 안이 가능 |

미확정인 질문(검수 시 답이 필요):
1. 각 사용자의 그룹 소속은?
2. Agent는 어느 계정으로 실행하는가? (그 계정이 `upload_files`·`api_keys`·로그에 접근해야 함)
3. 두 그룹에 모두 속하는 사용자가 있는가?

## 5. 디렉터리별 접근 정책

경로·소유자·mode는 `[설계]` 제안이며 확정이 아닙니다. 단 `/var/log/agent-app`은 확정 경로입니다.

| 디렉터리 | 경로(제안) | 소유자:그룹(제안) | mode(제안) | ACL(제안) | 접근 허용 |
|---|---|---|---|---|---|
| Agent 홈 | `AGENT_HOME=/opt/agent-app` (확인 필요) | `root:root` | `755` | — | 전체 읽기/탐색(실행 파일 배치 용) |
| 업로드 | `/opt/agent-app/upload_files` (확인 필요) | `agent-admin:agent-common` | `2770` (setgid) | `d:g:agent-common:rwx`, `g:agent-common:rwx`, `o::---` | `agent-common` R/W, 타 사용자 불가 |
| 키 | `/opt/agent-app/api_keys` (확인 필요) | `agent-admin:agent-core` | `2770` (setgid) | `d:g:agent-core:rwx`, `g:agent-core:rwx`, `o::---`, 파일 기본 `660` | `agent-core`만 R/W |
| 로그 | `/var/log/agent-app` (확정 경로) | `root:agent-core` 또는 `agent-admin:agent-core` | `2770` (setgid) | `d:g:agent-core:rwx`, `g:agent-core:rwx`, `o::---` | `agent-core`만 R/W |

설계 메모:
- **setgid(`2xxx`)**: 새 파일이 디렉터리 그룹을 상속하도록 하여 그룹 공유 유지.
- **default ACL(`d:`)**: 새 파일·디렉터리에 그룹 rwx가 자동 적용. umask 022 환경에서도 그룹 쓰기가 막히지 않게 함. mask가 `rwx`로 유지되는지 `getfacl`로 확인 필요.
- **`o::---`(타 사용자 차단)**: "그룹 외 접근 불가" 확인 항목(README 체크리스트)에 대응.
- **개인 홈 하위에 두지 않는 이유**: 홈은 `750`이라 다른 그룹 멤버가 상위 디렉터리를 통과(`x`)하지 못함. `/opt` 하위는 상위 통과 문제가 없음. 다만 AGENT_HOME 위치가 원문에 지정돼 있으면 그 값을 따라야 함 → 확인 필요.
- **`chmod`와 ACL의 관계**: ACL이 있으면 `ls`의 그룹 비트는 mask를 표시. `chmod g=...`가 mask를 바꿀 수 있어 chmod 후 ACL 재확인 필요.
- **ACL을 쓸지 chmod만 쓸지**: 그룹 하나에만 R/W를 주는 요구라면 소유 그룹 + `2770`만으로도 충족 가능. ACL은 "권한/ACL 구성"이라는 요구 표현과 default 상속 때문에 사용하는 안. 원문이 ACL을 명시하는지 확인 필요.

## 6. 연관성

- **cron/`monitor.sh`**: `agent-admin`이 매분 `/var/log/agent-app/monitor.log`에 append. 필요 조건: `agent-admin` ∈ `agent-core`, 디렉터리 `x`+`w`. 로그 파일 생성 시 mode가 그룹 쓰기를 유지해야 함(setgid + default ACL 필요).
- **로그 순환(10MB/10개)**: 순환 시 새 파일·압축 파일이 같은 그룹/권한을 유지해야 함. logrotate 사용 시 `create` 지시자의 mode/owner/group, 또는 `monitor.sh` 자체 순환 여부는 확인 필요.
- **Agent 실행**: Agent가 `AGENT_KEY_PATH`(api_keys)를 읽고 `AGENT_UPLOAD_DIR`에 쓰고 `AGENT_LOG_DIR`에 기록한다면 실행 계정이 `agent-common`과 `agent-core` 모두에 속해야 할 수 있음 → 실행 계정·Agent 요구사항 확인 후 결정.
- **환경변수**: cron은 로그인 셸 환경을 상속하지 않으므로 `monitor.sh`가 쓰는 경로는 스크립트/crontab에서 명시해야 함(별도 작업).
- **SSH**: `agent-*`는 현재 접속 불가(비밀번호 잠금, 키 없음). 접근 테스트는 `sudo -u`로 수행하는 안(§7).

## 7. 적용 후 테스트 계획

실행 방법은 `sudo -u <user> ...`(기존 sudo 사용자). 기대값은 **소속이 확정된 뒤** 채웁니다. 아래는 제안안(§4: admin ∈ common+core, dev/test는 미정) 기준 틀입니다.

| # | 대상 | 동작 | 기대 | 확인 포인트 |
|---|---|---|---|---|
| 1 | `agent-common` 멤버 | `upload_files`에 파일 생성/읽기/수정 | 성공 | 새 파일 그룹이 `agent-common`(setgid) |
| 2 | `agent-core` 멤버 | `api_keys`에서 생성/읽기 | 성공 | 새 파일 mode `660` 수준 |
| 3 | `agent-core` 멤버 | `/var/log/agent-app`에 append | 성공 | 생성 파일 그룹 `agent-core` |
| 4 | 비소속 사용자 | `upload_files`, `api_keys`, 로그 디렉터리 `ls`/읽기/쓰기 | 모두 `Permission denied` | `other` 차단(`o::---`) |
| 5 | `agent-common` 전용 멤버 | `api_keys`, 로그 접근 | 거부 | "core만" 요구 검증 |
| 6 | `agent-core` 전용 멤버 | `upload_files` 접근 | 소속에 따라 결정 | 확인 필요 |
| 7 | 파일 생성 후 | `getfacl`, `ls -ld`, `stat` | ACL·mask·owner 설계와 일치 | mask가 `rwx`인지 |
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
8. `acl` 패키지 설치 허용 (적용 작업에서 `apt install acl`)

## 9. 재현 명령 초안 (**미실행·미검증, 값은 확인 후 확정**)

```bash
# 0) ACL 도구
sudo apt-get install -y acl

# 1) 그룹 소속 (확정 후에만 실행) — 예시 자리표시
# sudo usermod -aG agent-common,agent-core agent-admin   # <확인 필요>
# sudo usermod -aG <그룹> agent-dev agent-test            # <확인 필요>

# 2) 디렉터리 (경로는 확인 필요)
sudo install -d -o root -g root -m 0755 /opt/agent-app
sudo install -d -o agent-admin -g agent-common -m 2770 /opt/agent-app/upload_files
sudo install -d -o agent-admin -g agent-core   -m 2770 /opt/agent-app/api_keys
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
