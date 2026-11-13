# scripts/

B4-1 환경을 재현하기 위한 스크립트를 두는 디렉터리입니다.

## 현재 파일

| 파일 | 실행 위치 | 역할 |
|---|---|---|
| `bootstrap-orbstack.sh` | **Mac** (sudo 불필요) | Machine 생성(`create`), 읽기 전용 점검(`check`), 적용(`apply`), 상태 출력(`snapshot`), Mac 쪽 네트워크·SSH·cron 검증(`verify`), 전체(`all`). 기존 Machine 삭제·초기화 기능 없음 |
| `machine-setup.sh` | Machine 안, root | 단계별 `check`/`apply`/`snapshot`. 보통 `bootstrap-orbstack.sh`가 필요한 파일과 함께 전송해 실행 |
| `monitor-cron.sh` | Machine 안, root | `agent-admin` crontab의 `monitor.sh` 매분 작업 `install`/`pause`/`resume`/`remove`/`status` |

사용법·검증 결과·한계: [docs/b4-1-recovery.md](../docs/b4-1-recovery.md), cron 관리: [docs/b4-1-cron.md](../docs/b4-1-cron.md).

## 범위와 원칙

- 구체적인 값은 [README 3.3 요구사항 요약표](../README.md#33-요구사항-요약표)와 `config/` 파일이 기준이며, 공식 원문 대조 전 값은 [승인된 실습 설계]입니다.
- 여러 번 실행해도 결과가 같고(idempotent), 단계가 실패하면 그 단계에서 멈춥니다.
- 비밀정보·SSH 개인키·API 키는 생성·복사·저장하지 않습니다. 기존 로그·다른 crontab 항목은 삭제하지 않습니다.
- 제공 Python 앱(Agent)은 포함·수정·대체 구현하지 않으며 복구 대상에서 제외됩니다(PENDING).
