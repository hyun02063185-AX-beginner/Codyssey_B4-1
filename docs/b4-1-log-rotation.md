# B4-1 monitor.log 순환 (작업 12)

- 일시: 2026-11-13 / 기준 커밋 `7ebb50f`
- 범위: `monitor.log` 순환 설정·검증·적용. `agent-admin` 매분 cron 등록, Agent, bootstrap, SSH·UFW·사용자·그룹 변경은 하지 않음. `monitor.sh`는 수정하지 않음(이번 작업의 코드 변경 없음).
- 값의 구분: **[승인된 실습 설계]** 크기·보존 수·소유자(공식 원문 미확인) / **[적용됨]** Ubuntu 반영 / **[실측]** 테스트 결과.

## 1. 선택한 방식: logrotate, rename + create

| 비교 | rename + create (**채택**) | copytruncate (미채택) |
|---|---|---|
| 동작 | 활성 파일을 `.1`로 rename → 새 활성 파일 생성 | 활성 파일을 `.1`로 복사 → 원본을 truncate |
| `monitor.sh`(fd 9)와의 관계 | `monitor.sh`는 **실행마다** `monitor.log`를 append로 열고 한 번 실행(약 2초) 동안 fd 9를 유지. rename 이후에도 실행 중인 인스턴스는 같은 inode(= `.1`)에 계속 기록하므로 **한 번의 실행이 통째로 `.1`에** 남고, 다음 실행부터 새 활성 파일 사용. 순환 신호(`postrotate`)·재오픈 불필요 | 복사~truncate 사이에 쓰인 줄이 유실될 수 있고(재현이 어려운 이론적 구간), 실행 중이던 인스턴스의 출력이 **두 파일로 분할**됨 |
| [실측] | 실행 중 순환: 10줄 전체가 `.1`, 새 활성 로그 0바이트, 손실·분할 없음 | 같은 시나리오: 6줄은 `.1`, 4줄은 활성 로그로 **분할** |

선택 근거: 로그 쓰기 프로세스가 짧게 살고 매번 파일을 다시 열기 때문에 rename 방식의 약점(프로세스가 옛 fd를 오래 쥐는 문제)이 없습니다. 열려 있던 fd가 `.1`을 가리킨 채 남아 있는 것은 순환 전에 시작된 실행 하나가 끝날 때까지이며 무해합니다.

**미검증 위험(이론):** logrotate가 rename한 직후~새 파일을 `create`하기 직전에 `monitor.sh`가 시작되면 그 파일을 스크립트가 먼저 만들 수 있고(소유 `agent-admin`, 그룹 상속, mode 660 — 호환되는 파일) logrotate는 "파일 존재"로 해당 회차의 `create`가 오류가 날 수 있습니다. 로그 데이터는 잃지 않지만 실제로 재현·검증하지는 않았습니다.

## 2. 설정 파일 (적용됨)

- 저장소: [config/etc-logrotate.d-agent-app](../config/etc-logrotate.d-agent-app) → Ubuntu: `/etc/logrotate.d/agent-app` (`root:root`, `0644`, 작업 전 없었음)

```
/var/log/agent-app/monitor.log {
    su agent-admin agent-core
    size 10M
    rotate 9
    create 0660 agent-admin agent-core
    missingok
    notifempty
    nocompress
}
```

| 옵션 | 의미·이유 |
|---|---|
| `size 10M` | 활성 로그가 **10 MiB(10485760 B) 이상**이면 순환. [실측] 10485759 B는 순환 안 함, 10485760 B부터 순환(logrotate 3.21은 `>=`). 작업 지시의 "초과"가 아닌 "이상"임에 주의. 시간 기준(daily 등)은 쓰지 않음 |
| `rotate 9` | 순환본 최대 9개 → 활성 1 + `monitor.log.1`~`.9` = **최대 10개 파일**. 가장 오래된 `.9`는 다음 순환 때 삭제 |
| `create 0660 agent-admin agent-core` | 새 활성 파일의 mode·소유자·그룹. 기존 활성 로그와 동일 |
| `su agent-admin agent-core` | 로그 디렉터리(`root:agent-core 2770`)가 root가 아닌 그룹에 쓰기 가능해서 `su` 없이는 logrotate가 거부함([실측] `parent directory has insecure permissions`로 순환 거부). `su`를 지정하면 순환이 `agent-admin:agent-core` 권한으로 수행됨([실측] 디버그 출력 `switching euid from 0 to 1000 and egid from 0 to 1001`) |
| `missingok`, `notifempty` | 파일이 없거나 비어 있으면 건너뜀 |
| `nocompress` | 압축하지 않음(최대 약 100 MiB). 압축·`dateext`는 필요 시 추가(공식 요구 없음) |

## 3. 검증 결과 [실측]

방법: 실제 로그는 건드리지 않고 `/tmp`의 독립 디렉터리에서 **실제 로그 디렉터리와 같은 권한**(`root:agent-core 2770` + `g:agent-core:rwx`/mask/other `---` access·default ACL)과 **같은 옵션**(경로만 치환한 설정)으로 `logrotate -s <임시 state>`를 실행. 대용량 데이터는 sparse 파일(`truncate`)과 마커 줄(`GEN-NN`)로 만들었고, 실제 텍스트 데이터 보존은 12.5 MB 텍스트로 별도 검증. 테스트 후 임시 디렉터리 삭제, **실제 `monitor.log`의 inode·sha256은 테스트 전후 동일**. 총 **37건 PASS / 0 FAIL**.

| # | 항목 | 결과 | 판정 |
|---|---|---|---|
| 1 | 설정 구문(`logrotate -d`) | error 없음, `10485760 bytes (9 rotations)` | PASS |
| 2 | 10 MiB 미만(10485759 B, 1000 B) | 순환 안 함, 소유·mode 불변 | PASS |
| 3 | 정확히 10485760 B | 순환됨(`>=`) | PASS |
| 4 | 초과(10485761 B) | `.1` 생성, 새 활성 로그 크기 0, `0660 agent-admin:agent-core` | PASS |
| 5 | 순환 전후 데이터 | `.1`의 inode·sha256이 순환 전 활성 로그와 동일(sparse), 12.5 MB 텍스트도 sha256 동일 | PASS |
| 6 | 순환본·새 로그 권한 | 모두 `660 agent-admin:agent-core`, 새 파일은 디렉터리 default ACL로 `group:agent-core:rwx`(실효 `rw-`), mask `rw-`, `other::---` | PASS |
| 7 | 순환 후 기록 | `monitor.sh`(`agent-admin`)가 새 활성 로그에 10줄 기록, 직접 append도 가능 | PASS |
| 8 | 접근 차단 유지 | `agent-dev`·`agent-test`: 활성 로그·순환본 읽기, 쓰기, 디렉터리 목록 모두 거부(순환본 존재 확인 후) | PASS |
| 9 | 반복 순환 12회 | 최대 보존 파일 10개, 최종 `monitor.log` + `.1`~`.9`(`.10` 없음), `.1`=최신(GEN-12), `.9`=GEN-04, 가장 오래된 GEN-01~03만 정책에 따라 삭제 | PASS |
| 10 | `monitor.sh` 실행 중 순환 | 실행 정상 종료(exit 1), 10줄 전체가 `.1`, 새 활성 로그에는 없음, 다음 실행은 새 로그에 기록 | PASS |
| 11 | 대조: copytruncate | 한 번의 실행이 `.1`(6줄)과 활성 로그(4줄)로 분할 | 참고 |
| 12 | 대조: `su` 제거 | `insecure permissions`로 순환 거부 → `su` 필요 | 참고 |

**하네스 오류와 정정:** 첫 실행에서 9건이 실패했습니다. 대부분은 root가 아닌 셸에서 `sudo wc -l < 파일`·`$D/*` 글롭을 써서 읽기가 막힌 하네스 오류(스크립트·설정과 무관)였지만, **하나는 실제 사실 오류**였습니다. 저는 "10 MiB 초과(`>`)에서 순환"이라고 설정 주석에 적었으나 logrotate 3.21은 **`>=`** 입니다. 주석과 문서를 정정했고 경계 테스트를 10485759 B(미순환)/10485760 B(순환)로 바꿔 재실행했습니다.

## 4. 실제 적용 [적용됨]

| 항목 | 결과 |
|---|---|
| 설정 파일 | `/etc/logrotate.d/agent-app` `root:root 0644`, 저장소 파일과 동일(`cmp`) |
| 구문·해석 | `logrotate -d`: 오류 없음. 전역 설정(`/etc/logrotate.conf`, `include /etc/logrotate.d`) 디버그 실행에서도 이 로그가 대상에 포함되고 오류 0건 |
| 실제 로그 | **강제 순환·초기화·대용량 추가 없음.** 비강제 실행(`logrotate -v /etc/logrotate.d/agent-app`): `log does not need rotating`, 실제 `monitor.log`의 inode·sha256 불변 |
| 순환 후 기록 | 적용 후 `agent-admin`으로 `monitor.sh` 1회 실행 → 실제 로그에 10줄 추가(터미널과 동일), `660 agent-admin:agent-core` 유지, `agent-dev`·`agent-test` 거부 |
| state | `/var/lib/logrotate/status`에 `monitor.log` 항목 생성(비강제 실행의 부수 효과) |

실제 로그에는 지금까지의 검증 실행 5회분(50줄)이 있습니다. 삭제·초기화하지 않았습니다.

### 자동 순환이 동작하는 범위 / 아직 아닌 범위

| 구분 | 내용 |
|---|---|
| 실행 주체·주기 | systemd `logrotate.timer`(`OnCalendar=daily`, `AccuracySec=1h`, `Persistent=true`, 활성·enabled) → `logrotate.service` → `logrotate /etc/logrotate.conf`(root) → 이 설정은 `su`로 `agent-admin:agent-core` 권한으로 수행. 다음 실행 예정 2026-11-14 00:00 KST (최대 약 1시간 지연). `/etc/cron.daily/logrotate`는 systemd가 있으면 즉시 종료(중복 실행 없음) |
| **동작함(실측)** | 설정 구문, 전역 설정에 포함, 크기 판정, 순환·권한·보존 수, `su` 하에서의 순환(임시 환경) |
| **미검증(PENDING)** | **실제 타이머가 발동해 이 설정이 실행되는 것**(`logrotate.timer`가 다음에 실행될 때 확인 필요. 이번에는 `logrotate.service`를 수동 시작하지 않았음: 전역 설정이 다른 시스템 로그도 순환시키기 때문), 실제 로그 디렉터리에서의 실제 순환(10 MiB에 도달한 적 없음) |
| **엄격한 최대 크기 아님** | 크기는 **logrotate가 실행될 때만** 검사됩니다. 일 1회이므로 그 사이 10 MiB를 넘을 수 있습니다. 매분 실행 시 로그 증가량은 약 1.1 KB/회 × 1440회 ≈ 1.6 MB/일(**추정**, cron 미등록 상태라 실측 아님)이라 하루 검사 간격의 초과분은 대략 이 정도이며, 10 MiB 도달에는 약 6일, 10개 보존은 약 2개월치로 추산됩니다. 더 촘촘한 검사(예: cron에서 주기적으로 `logrotate`)는 cron 작업에서 결정 |
| 이번 범위 밖 | `agent-admin` 매분 cron 등록 및 cron 환경에서의 최종 검증 |

## 5. 보안·권한 요약

- 설정 파일은 root 소유 0644(logrotate는 비root 소유·쓰기 가능 설정 파일을 거부). 비밀정보 없음.
- 순환은 root가 아니라 `agent-admin:agent-core` 권한으로 수행되어, 그룹 쓰기 가능 디렉터리에서 root 권한으로 파일 작업을 하는 위험을 피함(logrotate의 insecure parent 검사가 요구하는 구성).
- 비허용 계정(`agent-dev`, `agent-test`)의 접근 차단은 순환 후에도 유지(§3-8).
- `agent-admin`은 sudo 권한이 없으며 이번 작업에서도 추가하지 않음.

## 6. Mac 초기화 후 재현

전제: 사용자·그룹·권한(권한 설계 11장), `monitor.sh` 및 로그 파일(monitor 기록 §2.1·§6)이 구성되어 있음.

```bash
# 설정 설치 (없을 때만; 덮어쓰지 않음)
orb -m b4-lab sudo test ! -e /etc/logrotate.d/agent-app && \
orb -m b4-lab sudo install -o root -g root -m 0644 /dev/stdin /etc/logrotate.d/agent-app < config/etc-logrotate.d-agent-app

# 검증 (변경 없음)
orb -m b4-lab sudo cat /etc/logrotate.d/agent-app | cmp - config/etc-logrotate.d-agent-app && echo IDENTICAL
orb -m b4-lab sudo logrotate -d /etc/logrotate.d/agent-app          # 디버그: 오류 없어야 함
orb -m b4-lab sudo logrotate -v /etc/logrotate.d/agent-app          # 비강제: 10 MiB 미만이면 "does not need rotating"
orb -m b4-lab systemctl is-active logrotate.timer
```

(위 명령은 Mac 터미널에서 실행합니다. Machine 내부 셸에서 직접 실행한다면 `orb -m b4-lab` 접두사를 빼고 저장소 파일 경로를 맞춥니다.)

## 7. 남은 문제·다음 작업 주의

1. `agent-admin` 매분 cron 등록 후, cron 환경에서의 기록과 소속 반영을 확인하고 **실제 타이머 발동 시 이 설정이 실행되는지**(다음 `logrotate.timer` 실행 후 `/var/lib/logrotate/status`와 `journalctl -u logrotate`) 확인.
2. 더 촘촘한 크기 검사가 필요한지 결정(일 1회 검사의 초과 허용 여부, 공식 원문의 "최대 10MB" 해석).
3. 크기·보존 수·소유자·압축 여부를 공식 원문과 대조(현재 [승인된 실습 설계]).
4. rename 직후 `create` 사이 경합(§1)은 미검증.
5. 순환본 `mv` 시 mode 승계와 `create` 옵션은 확인됨. Agent 확보 후 Agent 로그가 같은 디렉터리에 생기면 별도 순환 설정이 필요할 수 있음.
