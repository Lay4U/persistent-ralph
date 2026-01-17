# Persistent Ralph

**완전 자율 Ralph Loop - Auto-compact 이후에도 절대 멈추지 않는 시스템**

[ralph-claude-code](https://github.com/frankbria/ralph-claude-code)의 모든 핵심 기능을 Claude Code 플러그인으로 통합했습니다.

## 핵심 기능

| 문제 | 해결책 |
|------|--------|
| Auto-compact 후 멈춤 | `PreCompact` hook으로 상태 저장, `SessionStart`로 자동 재개 |
| 세션 종료 시 멈춤 | `Stop` hook에서 `decision: block`으로 종료 차단 |
| 새 세션에서 수동 재개 필요 | `SessionStart` hook에서 강력한 컨텍스트 자동 주입 |
| 컨텍스트 손실 | `experiments.md`에 진행 상황 영구 저장 |

## 고급 기능 (ralph-claude-code 통합)

### Circuit Breaker (회로 차단기)
무한 루프와 스태그네이션 방지:
- **CLOSED**: 정상 동작
- **HALF_OPEN**: 모니터링 모드 (진행 없음 2회)
- **OPEN**: 실행 중지 (진행 없음 5회)

### Response Analyzer (응답 분석기)
Claude 출력 분석:
- `RALPH_STATUS` 블록 파싱
- 완료 신호 감지
- Dual-condition EXIT_SIGNAL gate

### Rate Limiter (속도 제한)
API 사용량 관리:
- 시간당 100회 API 호출 제한
- 5시간 API 제한 감지
- 자동 리셋 및 재개

### Session Manager (세션 관리)
세션 수명 관리:
- 24시간 세션 만료
- 세션 히스토리 추적
- 자동 세션 연장

### Status Generator (상태 생성)
외부 모니터링 지원:
- `status.json` 실시간 생성
- 진행 상황 추적

## 설치

### 1. 플러그인 디렉토리 복사

```bash
# Windows
mkdir -p ~/.claude/plugins/local/persistent-ralph
cp -r . ~/.claude/plugins/local/persistent-ralph/
```

### 2. 프로젝트에서 활성화

프로젝트 루트에 `.claude/settings.local.json` 생성:

```json
{
  "plugins": [
    "local:persistent-ralph"
  ]
}
```

### 3. 필수 요구사항

- **Git Bash** 설치 필요 (`C:\Program Files\Git\bin\bash.exe`)
- **jq** 설치 필요 (JSON 처리) - `choco install jq` 또는 Git Bash에 포함

## 사용법

### 프로젝트 설정

```bash
/ralph-loop:setup
```

템플릿 파일과 디렉토리 구조 생성:
- `PROMPT.md` - 개발 지침
- `@fix_plan.md` - 우선순위 작업 목록
- `@AGENT.md` - 빌드/테스트 지침
- `specs/` - 프로젝트 명세

### PRD 가져오기

```bash
/ralph-loop:import <path-to-prd>
```

PRD를 Ralph specs 형식으로 변환.

### Ralph Loop 시작

```bash
# 완료 조건과 함께
/ralph-loop "새로운 기능 구현" --completion-promise "DONE" --max-iterations 100

# 무제한 (취소할 때까지)
/ralph-loop "실험 계속"
```

### 상태 확인

```bash
cat status.json
```

### 취소

```bash
/cancel-ralph
```

## RALPH_STATUS 블록

Claude가 각 루프 끝에 보고해야 하는 상태:

```
---RALPH_STATUS---
STATUS: IN_PROGRESS | COMPLETE | BLOCKED
TASKS_COMPLETED_THIS_LOOP: <number>
FILES_MODIFIED: <number>
TESTS_STATUS: PASSING | FAILING | NOT_RUN
WORK_TYPE: IMPLEMENTATION | TESTING | DOCUMENTATION | REFACTORING
EXIT_SIGNAL: false | true
RECOMMENDATION: <다음 단계 요약>
---END_RALPH_STATUS---
```

### EXIT_SIGNAL = true 조건
1. @fix_plan.md의 모든 항목 완료
2. 모든 테스트 통과
3. 에러 없음
4. specs/ 요구사항 모두 구현

## 아키텍처

```
┌─────────────────────────────────────────────────────────────────┐
│                    PERSISTENT RALPH SYSTEM                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐    │
│  │  Stop Hook   │────▶│  Block Exit  │────▶│  Continue    │    │
│  │              │     │  + Rate Limit│     │  Loop        │    │
│  │              │     │  + Session   │     │              │    │
│  └──────────────┘     └──────────────┘     └──────────────┘    │
│         │                                                        │
│         │ (if completion promise or circuit breaker open)        │
│         ▼                                                        │
│  ┌──────────────┐                                               │
│  │  Allow Exit  │                                               │
│  │  Clean up    │                                               │
│  └──────────────┘                                               │
│                                                                  │
├─────────────────────────────────────────────────────────────────┤
│                     SAFETY FEATURES                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Circuit Breaker ──▶ Response Analyzer ──▶ Rate Limiter        │
│         │                    │                    │              │
│         ▼                    ▼                    ▼              │
│  스태그 감지         완료 신호 감지       속도 제한 적용        │
│  (5회 무진행)       (RALPH_STATUS)      (100회/시간)           │
│         │                    │                    │              │
│         ▼                    ▼                    ▼              │
│     루프 중지            루프 종료          일시 정지            │
│                                                                  │
├─────────────────────────────────────────────────────────────────┤
│                    SESSION MANAGEMENT                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Session Manager ──▶ Status Generator ──▶ status.json           │
│         │                    │                                   │
│         ▼                    ▼                                   │
│  24시간 만료           실시간 모니터링                           │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## 파일 구조

```
persistent-ralph/
├── .claude-plugin/
│   └── plugin.json          # 플러그인 메타데이터
├── hooks/
│   ├── hooks.json           # Hook 정의
│   ├── lib/                 # 라이브러리
│   │   ├── utils.sh         # 공통 유틸리티
│   │   ├── circuit-breaker.sh
│   │   ├── response-analyzer.sh
│   │   ├── rate-limiter.sh
│   │   ├── session-manager.sh
│   │   └── status-generator.sh
│   ├── stop-hook.sh
│   ├── pre-compact.sh
│   ├── auto-resume.sh
│   ├── prompt-replace.sh
│   └── run-*.cmd            # Windows 래퍼
├── templates/
│   ├── PROMPT.md
│   ├── fix_plan.md
│   └── AGENT.md
├── commands/
│   ├── help.md
│   ├── setup.md
│   └── import.md
└── README.md
```

## 상태 파일

| 파일 | 설명 |
|------|------|
| `.claude/ralph-loop.local.md` | 루프 상태 (iteration, promise 등) |
| `.claude/circuit-breaker.json` | Circuit Breaker 상태 |
| `.claude/response-analysis.json` | 응답 분석 결과 |
| `.claude/call-count.json` | API 호출 카운트 |
| `.claude/ralph-session.json` | 세션 정보 |
| `status.json` | 모니터링용 상태 |
| `experiments.md` | 진행 상황 로그 |

## 환경 변수

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `RALPH_MAX_CALLS_PER_HOUR` | 100 | 시간당 최대 API 호출 |
| `RALPH_API_LIMIT_HOURS` | 5 | API 제한 해제 대기 시간 |
| `RALPH_SESSION_EXPIRY_HOURS` | 24 | 세션 만료 시간 |

## 랄프의 법칙

```
1. 사용자 개입 없이 목표 달성까지 멈추지 않는다
2. 실패는 학습의 기회다 - 기록하고 다음 시도에 반영
3. 안 되는 것에 집착하지 말고 과감히 버린다
4. 완벽한 첫 시도보다 반복적 개선이 낫다
5. "불가능"이라는 결론은 없다 - 항상 다음 방법이 있다
```

## 트러블슈팅

### 루프가 재개되지 않음
1. `.claude/ralph-loop.local.md` 파일 확인
2. `active: true` 확인

### Circuit Breaker OPEN
1. experiments.md 확인
2. git log로 진행 상황 확인
3. 문제 해결 후 `/ralph-loop "continue"` 실행

### Rate Limit 도달
1. status.json에서 reset 시간 확인
2. 자동 재개 대기

## 라이선스

MIT

## 참조

- [Ralph Technique by Geoffrey Huntley](https://ghuntley.com/ralph/)
- [Ralph Orchestrator](https://github.com/mikeyobrien/ralph-orchestrator)
- [ralph-claude-code](https://github.com/frankbria/ralph-claude-code)
