# B4-1 Agent 실행환경 준비 (작업 9)

> **작업 16 정정:** 그룹 소속(common = admin·dev·test, core = admin·dev), monitor.sh 소유권(agent-dev:agent-core 0750), 경고 임계값(20/10/80), `AGENT_KEY_PATH`(`/opt/agent-app/api_keys/t_secret.key`)는 공식 요구에 맞게 변경됐습니다. 이 문서의 해당 값은 당시 기록이며 현행 값은 [공식 정합성 수정](b4-1-official-alignment.md)을 따릅니다.

- 일시: 2026-11-13 / 기준 커밋 `86678af`
- 범위: 환경변수 파일 적용·검증, 제공 Agent 존재 확인. SSH·UFW·그룹 소속·기존 ACL 변경 없음. `monitor.sh`·cron·logrotate·bootstrap 미구현.
- 값의 구분: **[원문]** 공식 원문 확인(현재 없음) / **[Notion 요약]** 변수 이름 5개(원문 미대조) / **[승인된 실습 설계]** 사용자 승인값, 원문 미대조 / **[적용됨]** Ubuntu에 반영 / **[실측]** 테스트 결과.

## 1. 제공 Agent 원본: NOT FOUND

| 확인 위치 | 결과 |
|---|---|
| 저장소 (`git ls-files`) | 문서·README만 존재, Agent 파일 없음 |
| Mac `~/Downloads`, `~/Desktop`, `~/Documents`, `~/Codyssey_B4-2`(빈 디렉터리), 홈 하위 5단계 이름 검색(`agent_app*`, `agent.py` 등) | 없음 (ChatGPT/Claude `.dmg`, 스크린샷만 존재) |
| Machine `b4-lab` 전체(`find / -xdev`: `*agent*app*`, `agent*.py/.zip/.tar*`, `*.pyz`) | `/opt/agent-app`, `/var/log/agent-app`(작업 8에서 만든 디렉터리)만 검색됨 |
| Notion | Boot Sequence·`AGENT_KEY_PATH` 요건 상세 없음. B4-2 페이지에 "제공 agent-leak-app" 이름만 언급 |

임의의 Agent나 모의 서버는 만들지 않았습니다. 따라서 **Agent 실행(`Agent READY`, `0.0.0.0:15034` LISTEN 검증)은 보류(NOT RUN)** 입니다. 실행 안내·Python 버전·아키텍처·필수 라이브러리·실행 계정·Boot Sequence 조건은 모두 미확인입니다.

## 2. 환경변수 구성

설정 파일: `/etc/default/agent-app` — `root:root`, `0644`(`-rw-r--r--`), ACL 없음. 비밀값 없음. 작업 전 해당 파일은 존재하지 않았습니다(덮어쓴 것 없음).

| 변수 | 값 | 출처·확정 여부 | 상태 |
|---|---|---|---|
| `AGENT_HOME` | `/opt/agent-app` | 변수 이름: [Notion 요약] / 값: [승인된 실습 설계], 원문 확인 필요 | 적용 |
| `AGENT_PORT` | `15034` | [관리자료](README, UFW 허용 포트와 일치) / 변수 이름·값 원문 확인 필요 | 적용 |
| `AGENT_UPLOAD_DIR` | `/opt/agent-app/upload_files` | [승인된 실습 설계] | 적용 |
| `AGENT_LOG_DIR` | `/var/log/agent-app` | 경로: README·Notion 일치(원문 미대조) | 적용 |
| `AGENT_KEY_PATH` | *(빈 값)* | 파일/디렉터리 여부 미확인 | **PENDING** |

- `AGENT_KEY_PATH=`는 "정의했지만 비어 있음"입니다. 이 값은 api_keys 디렉터리 경로(`/opt/agent-app/api_keys`)일 수도, 그 아래 특정 키 파일일 수도 있어 **추측하지 않았습니다.** 제공 Agent가 요구하는 형태를 확인한 뒤 채웁니다(디렉터리 안에 파일을 만들 때도 실제 키는 임의 생성하지 않음).
- 파일 형식은 `KEY=VALUE`(따옴표·`export` 없음)로, bash `source`와 systemd `EnvironmentFile=` 양쪽에서 같은 결과를 냅니다.
- 로그인 셸 설정(`~/.bashrc`, `/etc/profile.d`)에는 **의존하지 않습니다.** cron과 systemd는 로그인 환경을 상속하지 않으므로, 사용하는 스크립트가 아래 방식으로 명시 로드해야 합니다.

```bash
set -a; . /etc/default/agent-app; set +a
```

저장소 예제: [config/etc-default-agent-app.example](../config/etc-default-agent-app.example) (비밀값 없음, 실제 파일과 동일한 내용).

## 3. 검증 결과 [실측]

방법: `sudo -u agent-admin env -i PATH=/usr/bin:/bin bash -c '…'`로 로그인 환경이 전혀 없는 새 프로세스에서 수행.

| # | 항목 | 결과 | 판정 |
|---|---|---|---|
| 1 | 설정 파일 로드(구문, 로드) | `bash -n` OK, 로드 후 `AGENT_*` 5개 정의 | PASS |
| 2 | `agent-admin` 새 프로세스의 값(`env -i` + 명시 로드) | 5개 값이 설정과 일치, `AGENT_KEY_PATH`는 정의됨·빈 값 | PASS |
| 3 | 로드하지 않은 환경 | `sudo -iu agent-admin` 로그인 셸, `env -i`, cron 유사 `sh -c` 모두 `AGENT_*` 0개 → 로그인 셸에 의존하지 않으며 **명시 로드가 필수**임을 확인 | PASS |
| 4 | 디렉터리 존재 | `AGENT_HOME`, `AGENT_UPLOAD_DIR`, `AGENT_LOG_DIR` 모두 존재, `AGENT_HOME` 통과 가능 | PASS |
| 5 | 값 ↔ 실제 디렉터리 일치, 쓰기 | 작업 8 구성(`root:root 755`, `agent-admin:agent-common 2770`, `root:agent-core 2770`)과 일치. `agent-admin`이 업로드·로그 디렉터리에 쓰기·읽기·삭제 성공(권한·ACL 유지) | PASS |
| 6 | `AGENT_PORT` 값 | 숫자 1~65535, UFW 허용 포트(15034)와 일치 | PASS |
| 7 | systemd `EnvironmentFile` 호환 | `systemd-run -P -p User=agent-admin -p EnvironmentFile=…`으로 5개 값 동일 확인 | PASS |
| 8 | 다른 계정의 파일 읽기 | `agent-dev`, `agent-test` 모두 읽기 가능(비밀 없는 0644이므로 의도됨) | PASS |
| 9 | 비밀값 없음 | 파일 내 비밀 형태 값 없음 | PASS |
| 10 | `AGENT_KEY_PATH` 값 확정 | 빈 값 | **PENDING** |
| 11 | 환경변수를 실제 Agent가 사용하는 테스트 | Agent 없음 | **PENDING (NOT RUN)** |
| 12 | Agent 기동(`Agent READY`, `0.0.0.0:15034` LISTEN), Boot Sequence 5단계 | Agent 없음, 15034는 현재 LISTEN 없음 | **PENDING (NOT RUN)** |

위 PASS는 "환경변수 파일이 올바르게 정의·로드되고 경로·권한과 일치한다"까지만 의미합니다. Agent가 이 값을 실제로 사용해 기동하는지는 검증되지 않았습니다.

### 회귀 [실측]

| 항목 | 결과 | 판정 |
|---|---|---|
| SSH | `port 20022`, `permitrootlogin no`, Mac → 20022 접속 성공, `ssh b4-lab@orb` 성공 | PASS |
| UFW | active, deny(in)/allow(out), 20022·15034 허용 4개 유지 | PASS |
| 그룹 소속 | admin ∈ common+core, dev ∈ common, test 미가입 (변경 없음) | PASS |
| 디렉터리 권한·ACL | 소유자·mode·`group:agent-core:rwx`/mask/other 유지 | PASS |
| 정리 | 테스트 파일 0개(3개 디렉터리 모두 비어 있음), `agent-*` 프로세스 0개 | PASS |

## 4. 초기화 후 재현 명령 (검증된 절차)

사용자·그룹(12장), 그룹 소속·디렉터리(권한 설계 11장) 적용 후:

```bash
sudo tee /etc/default/agent-app >/dev/null <<'EOT'
AGENT_HOME=/opt/agent-app
AGENT_PORT=15034
AGENT_UPLOAD_DIR=/opt/agent-app/upload_files
AGENT_LOG_DIR=/var/log/agent-app
AGENT_KEY_PATH=
EOT
sudo chown root:root /etc/default/agent-app
sudo chmod 0644 /etc/default/agent-app
bash -n /etc/default/agent-app

# 검증
sudo -u agent-admin env -i PATH=/usr/bin:/bin bash -c 'set -a; . /etc/default/agent-app; set +a; env | grep ^AGENT_ | sort'
```

(저장소의 예제 파일을 `sudo install -m 0644 -o root -g root config/etc-default-agent-app.example /etc/default/agent-app`로 설치해도 같습니다.)

## 5. 미완료·재확인 항목

1. **제공 Agent 확보**(최우선): 파일 경로·종류, Python 버전·아키텍처, 필수 라이브러리, 실행 명령·실행 계정, Boot Sequence 5단계 조건, 포트 바인딩 방식(`0.0.0.0:15034`).
2. `AGENT_KEY_PATH`가 파일인지 디렉터리인지, 값과 위치 확정. 값이 api_keys 하위 파일이면 접근 계정(현재 `agent-core` 소속인 `agent-admin`만)도 재확인.
3. Agent 실행 계정과 그 계정의 그룹 소속(현재 `agent-dev`는 core 비소속).
4. 5개 변수의 이름·값·경로를 공식 원문과 대조(현재 [Notion 요약]·[승인된 실습 설계]).
5. cron/`monitor.sh`에서 위 명시 로드 방식이 실제로 동작하는지는 해당 작업에서 실측.
6. 변수를 Agent에 전달하는 방식(systemd 서비스 `EnvironmentFile=` 또는 실행 스크립트의 `source`)은 Agent 확인 후 결정.
