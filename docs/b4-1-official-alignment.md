# B4-1 공식 요구사항 정합성 수정 (작업 16)

기준 SHA `07f343c`. 테스트 Machine `b4-recovery-test`에서 먼저 검증한 뒤 `b4-lab`에 적용했습니다. SSH·UFW·로그·cron 기능은 변경하지 않았습니다.

> **작업 17 정정:** 제공 Agent 실행 결과, `AGENT_KEY_PATH`는 **디렉터리** `/opt/agent-app/api_keys`여야 하고 그 안의 파일명은 `secret.key`입니다(`t_secret.key` 아님). 아래 키 관련 값은 이에 맞게 고쳤습니다. 근거: [Agent 실행 기록](b4-1-agent-runtime.md#작업-17-제공-agent-실행-및-boot-sequence-검증).

## 변경 사항

| 항목 | 이전 | 공식(현행) |
|---|---|---|
| `agent-common` | admin, dev | admin, dev, test |
| `agent-core` | admin | admin, dev |
| `monitor.sh` 소유권 | `root:agent-admin 0750` | `agent-dev:agent-core 0750` (cron은 `agent-admin`, 그룹 권한으로 실행) |
| 경고 임계값 | 80 / 80 / 80 | CPU > 20, MEM > 10, DISK_USED > 80 (엄격한 `>`) |
| `AGENT_KEY_PATH` | 빈 값 | `/opt/agent-app/api_keys` (**작업 17 정정**: 작업 16의 `…/t_secret.key`는 제공 Agent가 거부함) |
| 키 파일 | 없음 | 내용 `agent_api_key_test` 한 줄(공식 실습 문자열, 실제 비밀키 아님), `root:agent-core 0640` |

키 파일은 `agent-core`(admin·dev)만 읽을 수 있고 `agent-test`는 api_keys 디렉터리 단계에서 거부됩니다. `AGENT_HOME=/opt/agent-app`은 유지했습니다. sudo 권한은 추가하지 않았고 기존 사용자·데이터는 삭제하지 않았습니다.

## 복구 스크립트

- `machine-setup.sh`: 그룹 구성·monitor.sh 소유권 수정, `keyfile` 단계 추가. 기존 `/etc/default/agent-app`은 덮어쓰지 않고 `AGENT_KEY_PATH` 한 줄만 교체(없으면 추가, 변경 시에만 백업). 비밀정보 키워드 검사에서 `AGENT_KEY_PATH` 줄(경로 `t_secret.key`)만 제외하고 나머지 줄은 그대로 검사합니다. 키 파일 내용이 다르면 덮어쓰지 않고 실패합니다.
- `bootstrap-orbstack.sh`: 전송 파일 목록이 동일해 코드 변경 없음(`machine-setup.sh`가 새 단계를 수행).
- 반복 실행: 2회차 `apply`는 `unchanged=13 changed=0`.

## 검증 결과 (b4-recovery-test와 b4-lab 동일)

| 계정 | upload_files | api_keys | /var/log/agent-app |
|---|---|---|---|
| agent-admin | R/W | R/W | R/W |
| agent-dev | R/W | R/W | R/W |
| agent-test | R/W | 거부 | 거부 |

- sudo: 세 계정 모두 `not allowed to run sudo`.
- monitor.sh: `agent-dev:agent-core 750`. `agent-admin`이 실행 가능(그룹 권한), `agent-test`는 `Permission denied`.
- 키 파일: `root:agent-core 640`, 1줄, `agent-admin`·`agent-dev` 읽기 성공, `agent-test` 거부.
- 임계값 경계(고정 입력): CPU 20.0% → OK, 20.1% → WARNING / MEM 10.0% → OK, 10.1% → WARNING / DISK 임계값=현재값 → OK, 임계값=현재값−0.1 → WARNING. 기본값 출력은 `threshold 20%/10%/80%`.
- 회귀: cron 매분 실행·`trigger=cron` 기록 계속, `monitor.log` `agent-admin:agent-core 660` 유지, 누적 로그 삭제·초기화 없음(b4-lab 2000줄 이상에서 계속 증가).
- 비교는 소수 첫째 자리로 반올림한 값 기준입니다(예: 실제 10.04%는 10.0%로 보여 경고 없음).

## 제외(이후 작업)

제공 Agent 실행, 공식 `monitor.log` 포맷, UFW 상태 조회 권한, 로그 순환 기준 보완, 보너스 과제.
