# scripts/

B4-1 환경을 재현하기 위한 스크립트를 두는 디렉터리입니다.

## 현재 파일

- `monitor-cron.sh` — `agent-admin` crontab의 `monitor.sh` 매분 작업 관리(`install`/`pause`/`resume`/`remove`/`status`, Machine 안에서 root로 실행). 설명·검증: [docs/b4-1-cron.md](../docs/b4-1-cron.md). **bootstrap 스크립트는 아님**(아래 예정 파일은 아직 미작성).

## 예정 파일: `bootstrap-orbstack.sh` (아직 작성하지 않음)

### 위치
`scripts/bootstrap-orbstack.sh`

### 역할
교육장 Mac 초기화 등으로 OrbStack Ubuntu Machine이 사라졌을 때, **B4-1 종료 시점과 동일한 Linux 환경을 다시 만드는 것**.

### 예정 범위
- Mission Core를 **수동으로 먼저 수행·검증한 뒤**, 그 절차를 옮겨 담습니다. (스크립트가 미션을 대신 풀어주는 용도가 아님)
- Machine 내부 설정: 사용자/그룹, 권한, 환경변수, SSH(20022), UFW(20022/15034), Agent 기동, `monitor.sh`(Bash) 배치, 로그, cron 등록
- 제공 Python 앱은 **수정하지 않고** 배치·실행만 함
- 여러 번 실행해도 결과가 같도록 idempotent하게 작성
- 실행 전 사전 점검: 대상 Machine 존재 여부, **고정한 Ubuntu 버전과 일치하는지**, `uname -m` 출력 기록
- 구체적인 값은 [README 3.3 요구사항 요약표](../README.md#33-요구사항-요약표)를 단일 기준으로 사용

### 범위 밖
- macOS host 설정 (host `sudo` 사용 불가)
- 비밀번호·개인키 등 비밀값 저장
- 제공 바이너리 architecture 추정 — 실제 `file` 결과로 확인한 값만 사용

### 실행 위치 (작성 시 확정)
- host에서 `orb` 명령으로 Machine에 명령을 전달하는 방식, 또는
- Machine 내부에서 저장소 경로의 스크립트를 직접 실행하는 방식
중 하나로 정하고, 이 문서에 기록합니다.
