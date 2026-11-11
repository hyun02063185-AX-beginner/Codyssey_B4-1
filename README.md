# Codyssey B4-1 — Linux 서버 기본 환경 구성

코디세이 B4-1 미션 저장소입니다.
OrbStack Ubuntu **Linux Machine**을 실습 서버로 사용하며, 여기서 만든 Linux 환경은 이후 **B4-2에서 그대로 재사용**합니다.

> 현재 상태: **저장소 기본 문서만 구성된 단계**입니다.
> Ubuntu Machine 생성, 사용자/그룹, SSH, UFW, cron, `monitor.sh` 등 Mission Core는 아직 구현하지 않았습니다.

---

## 1. 실습 환경

| 항목 | 내용 |
| --- | --- |
| Host | 코디세이 교육장 Mac (macOS) |
| Host 제약 | macOS host에서 `sudo` 사용 불가 |
| Host 초기화 | 교육장 Mac은 주기적으로 초기화됨 → 로컬 상태는 언제든 사라질 수 있음 |
| 가상화 도구 | OrbStack (설치되어 있음) |
| **B4-1 기본 실습환경** | **OrbStack Ubuntu Linux Machine** |
| 사용하지 않는 것 | Docker Container(기본 실습환경 아님), AWS EC2(기본환경 아님) |

- host에서는 `sudo`가 안 되지만, OrbStack Linux Machine **내부**에서는 Linux 관리자 권한(`sudo`)을 사용할 수 있으므로 서버 설정 실습이 가능합니다.
- Docker Container 대신 Linux Machine을 쓰는 이유와 OrbStack의 역할은 [docs/orbstack-environment.md](docs/orbstack-environment.md)에 정리되어 있습니다.

## 2. 저장소 구조

```
.
├── README.md                     # 미션 개요, 환경, Mission Core 체크리스트, 복구 흐름 요약
├── docs/
│   └── orbstack-environment.md   # OrbStack 역할, Container vs Machine, 초기화 후 복구 흐름 상세
└── scripts/
    └── README.md                 # scripts/ 디렉터리 용도, 향후 bootstrap-orbstack.sh 역할
```

향후 추가 예정(아직 없음):

- `scripts/bootstrap-orbstack.sh` — 교육장 Mac 초기화 후 OrbStack Ubuntu Machine을 같은 상태로 재구성하는 스크립트. 역할과 범위는 [scripts/README.md](scripts/README.md) 참고.

## 3. B4-1 Mission Core 체크리스트

> 아래 항목은 미션 진행을 위한 **작업용 체크리스트 초안**입니다.
> 세부 값(사용자명, 그룹명, 포트 번호, 경로, 주기, 출력 형식 등)은 **공식 미션 문서와 대조하여 확정**한 뒤 이 표를 갱신합니다. 추정한 값을 미리 적지 않습니다.

### 0) 환경 준비
- [ ] OrbStack Ubuntu Linux Machine 생성 (이름·Ubuntu 버전 확정 후 기록)
- [ ] Machine 내부에서 `uname -m`, `cat /etc/os-release`로 아키텍처·배포판 확인 후 기록
- [ ] 제공 바이너리가 있다면 `file <바이너리>`로 실제 architecture 확인 후 기록 (추정 금지)

### 1) 사용자 / 그룹
- [ ] 미션에서 요구하는 사용자 계정 생성
- [ ] 미션에서 요구하는 그룹 생성 및 사용자 소속
- [ ] 필요한 디렉터리의 소유자·그룹·권한 설정
- [ ] `id`, `getent group`, `ls -l` 등으로 결과 증빙

### 2) SSH
- [ ] SSH 서버 설치/동작 확인
- [ ] 미션에서 요구하는 `sshd_config` 설정 적용 (포트, root 로그인, 인증 방식 등)
- [ ] 설정 반영 후 접속 테스트 및 증빙

### 3) 방화벽 (UFW)
- [ ] UFW 설치/활성화
- [ ] 미션에서 요구하는 포트만 허용 (SSH 포트 변경 시 차단되지 않도록 순서 주의)
- [ ] `ufw status verbose`로 증빙

### 4) 모니터링 스크립트 (`monitor.sh`)
- [ ] 미션에서 요구하는 점검 항목·출력 형식 확인
- [ ] 스크립트 작성 및 실행 권한·소유자 설정
- [ ] 수동 실행 결과 증빙

### 5) 주기 실행 (cron)
- [ ] 미션에서 요구하는 주기로 `monitor.sh` 등록
- [ ] 로그 출력 위치 확인 및 실제 실행 결과 증빙

### 6) 마무리
- [ ] 수동으로 수행한 설정을 `scripts/bootstrap-orbstack.sh`로 재현 가능하게 정리
- [ ] 새 Machine에서 bootstrap 실행 → 위 체크리스트 재검증
- [ ] 제출 요구사항(스크린샷, 출력 결과 등) 정리

## 4. 교육장 Mac 초기화 후 복구 흐름 (요약)

Mac이 초기화되면 OrbStack Machine과 그 안의 설정이 모두 사라질 수 있습니다.
따라서 **"상태의 원본은 이 GitHub 저장소"** 라는 원칙으로 작업합니다.

1. OrbStack 실행 확인 (`orb version`)
2. 이 저장소를 다시 clone
3. OrbStack Ubuntu Machine 재생성
4. `scripts/bootstrap-orbstack.sh` 실행 (작성 이후)
5. 체크리스트 기준으로 상태 재검증

상세 절차는 [docs/orbstack-environment.md](docs/orbstack-environment.md#5-교육장-mac-초기화-후-복구-흐름)를 참고합니다.

## 5. B4-1과 B4-2의 관계

| 구분 | B4-1 | B4-2 |
| --- | --- | --- |
| 역할 | Linux 서버 기본 환경 **구축** | B4-1 환경을 **재사용**하여 다음 미션 수행 |
| 산출물 | 설정된 Ubuntu Machine + 재현 스크립트 + 문서 | B4-1 산출물 위에서 진행 |
| 의존성 | 없음 | B4-1 결과(사용자/그룹, SSH, UFW, cron, `monitor.sh`)에 의존 |

- B4-2는 B4-1 환경이 **그대로 존재한다는 전제**로 진행되므로, B4-1 설정은 반드시 재현 가능해야 합니다.
- Mac 초기화로 Machine이 사라져도 `bootstrap-orbstack.sh`로 B4-1 종료 시점 상태를 복구할 수 있어야 B4-2를 이어갈 수 있습니다.
- B4-1에서 정한 값(Machine 이름, 사용자명, 포트 등)은 B4-2에서 바꾸지 않는 것을 원칙으로 하며, 변경 시 이 README에 기록합니다.
