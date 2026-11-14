# B4-1 Owner 화면 증빙 — S1·S2 (2026-11-14)

> 제출용 캡처의 **원본 화면을 변경하지 않고** 등록한 자료입니다. 촬영 당시 교육장 Mac 터미널에서 OrbStack Ubuntu Machine `b4-lab`의 설정을 조회했습니다. 스크린샷 자체에 SSH 개인키·비밀번호·Agent 비밀키 값은 표시되지 않습니다.
>
> **검수 구분:** 화면상의 설정·LISTEN 상태는 확인. 공식 `docs/b4-1-final-evidence.md` §4 체크리스트에 포함된 **Mac에서 직접 TCP 연결 성공/차단 시험은 이 캡처에 포함되지 않음**. 따라서 S1·S2 전체 제출 항목은 아직 최종 완료로 표시하지 않습니다.

## S1 — Ubuntu / SSH

![S1 Ubuntu 및 SSH 설정](S1-ubuntu-ssh-2026-11-14.png)

촬영 원본은 터미널 글자 정렬이 일부 밀렸지만, 필요한 값은 판독할 수 있습니다. 화면 가독성 개선이 필요하면 Mac에서 재촬영하고 새 버전을 별도로 검수합니다. 이 원본을 편집·합성하지 않습니다.

### 화면에 표시된 조회 명령과 결과

```bash
orb -m b4-lab cat /etc/os-release | head -2
B sshd -T | grep -E '^(port|permitrootlogin) '
B ss -tlnp | grep sshd
```

`B()` 함수는 Mac 셸에서 `B() { orb -m b4-lab sudo "$@"; }`로 정의했습니다.

확인 사항:
- Ubuntu `24.04.5 LTS`
- `port 20022`
- `permitrootlogin no`
- `sshd`가 `0.0.0.0:20022`와 `[::]:20022`에서 LISTEN
- 표시된 PID `287`은 촬영 시점의 예시이며 재실행 때 달라질 수 있음

**남은 검증:** Mac에서 실제 TCP 20022 접속 성공·SSH 배너 또는 접속 확인은 이 화면만으로 증명되지 않습니다. 기존 회귀 텍스트 기록과 필요 시 별도 캡처로 보완합니다.

## S2 — UFW 방화벽

![S2 UFW 규칙](S2-ufw-2026-11-14.png)

### 화면 조회 명령

```bash
B ufw status verbose | awk '{printf "%s\r\n", $0}'
```

`awk`는 출력 줄바꿈만 정렬하며 UFW 규칙을 바꾸지 않습니다.

확인 사항:
- `Status: active`
- `Default: deny (incoming), allow (outgoing), deny (routed)`
- TCP 20022 (`# SSH`)와 15034 (`# Agent`) 인바운드 ALLOW
- 동일 허용 규칙의 IPv6 `(v6)` 항목

**남은 검증:** Mac에서 20022는 접근 가능하고 22·15035는 차단되는지에 대한 실제 연결 테스트는 별도 수행/기록이 필요합니다. UFW 설정 화면만으로 외부 연결 시험을 완료했다고 판단하지 않습니다.

## 증빙 관리 기준

- 참조: [`docs/b4-1-final-evidence.md`](../../b4-1-final-evidence.md) §4 (S1·S2 제출 체크리스트)
- 범위: 두 화면의 **설정 조회 및 스크린샷 등록**. 네트워크 연결 테스트, 다른 S3~S10 화면 캡처 및 공식 제출 승인은 별도
- 형식: PNG 원본; 인위적 수정 없음
- 학습자료 2강(SSH·포트·UFW)은 학습 초안 단계이며 이 증빙 등록으로 자동 확정하지 않음
