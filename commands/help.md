# Persistent Ralph Help

Please explain the following to the user:

## 개요

Persistent Ralph는 **완전 자율 에이전트 시스템**입니다. Auto-compact 이후에도 절대 멈추지 않습니다.

Ralph-claude-code의 모든 핵심 기능을 Claude Code 플러그인으로 통합했습니다.

## 핵심 기능

| Hook | 기능 |
|------|------|
| **Stop** | 세션 종료 차단 (`decision: block`) + Rate Limiting |
| **PreCompact** | Compact 전 상태 저장 (`experiments.md`) |
| **SessionStart** | 새 세션에서 자동 재개 (컨텍스트 주입) |
| **UserPromptSubmit** | 빈 입력 시 프롬프트 대체 |

## 고급 기능 (ralph-claude-code에서 통합)

### 1. Circuit Breaker (회로 차단기)
- **CLOSED**: 정상 동작
- **HALF_OPEN**: 모니터링 모드 (진행 없음 2회)
- **OPEN**: 실행 중지 (진행 없음 5회)

### 2. Response Analyzer (응답 분석기)
- `RALPH_STATUS` 블록 파싱
- 완료 신호 감지
- Dual-condition EXIT_SIGNAL gate

### 3. Rate Limiter (속도 제한)
- 시간당 100회 API 호출 제한
- 5시간 API 제한 감지
- 자동 리셋 및 재개

### 4. Session Manager (세션 관리)
- 24시간 세션 만료
- 세션 히스토리 추적
- 자동 세션 연장

### 5. Status Generator (상태 생성)
- `status.json` 실시간 생성
- 외부 모니터링 지원
- 진행 상황 추적

## 사용법

### 프로젝트 설정
```bash
/ralph-loop:setup
```
- PROMPT.md, @fix_plan.md, @AGENT.md 생성
- specs/ 디렉토리 구조 생성
- .gitignore 설정

### PRD 가져오기
```bash
/ralph-loop:import <path-to-prd>
```
- PRD를 Ralph specs 형식으로 변환
- @fix_plan.md에 작업 추가

### Ralph Loop 시작
```bash
/ralph-loop "작업 설명" --completion-promise "DONE" --max-iterations 100
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

Claude가 다음 형식으로 상태를 보고합니다:

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

## 완료 조건

Claude가 다음 형식으로 출력하면 루프 종료:

```
<promise>DONE</promise>
```

## 동작 흐름

```
┌─────────────────────────────────────────────────────┐
│                    RALPH LOOP                        │
├─────────────────────────────────────────────────────┤
│                                                      │
│   [작업 시작] ────▶ [작업 중] ────▶ [완료 시도]     │
│        │                               │            │
│        │                               ▼            │
│        │                        [Stop Hook]         │
│        │                               │            │
│        │              ┌────────────────┴────────┐   │
│        │              │                         │   │
│        │         completion             루프 활성  │
│        │         promise 발견           상태 확인  │
│        │              │                         │   │
│        │              ▼                         ▼   │
│        │         [종료 허용]          [종료 차단]  │
│        │                               reason 주입 │
│        │                                    │      │
│        │                                    ▼      │
│        │                              [작업 계속]  │
│        │                                    │      │
│        └────────────────────────────────────┘      │
│                                                      │
├─────────────────────────────────────────────────────┤
│                  추가 기능                           │
├─────────────────────────────────────────────────────┤
│  Circuit Breaker → Rate Limiter → Session Manager   │
│         ↓               ↓               ↓           │
│  스태그 감지      속도 제한        세션 만료        │
│         ↓               ↓               ↓           │
│  루프 중지        일시 정지        루프 종료        │
└─────────────────────────────────────────────────────┘
```

## 랄프의 법칙

1. **멈추지 않는다** - 목표 달성까지 계속
2. **실패는 학습** - 기록하고 다음 시도에 반영
3. **과감히 버린다** - 안 되는 것에 집착 금지
4. **반복적 개선** - 완벽한 첫 시도보다 나음
5. **항상 방법이 있다** - "불가능"은 없다

## 상태 파일

| 파일 | 설명 |
|------|------|
| `.claude/ralph-loop.local.md` | 루프 상태 (iteration, promise 등) |
| `.claude/circuit-breaker.json` | Circuit Breaker 상태 |
| `.claude/response-analysis.json` | 응답 분석 결과 |
| `.claude/call-count.json` | API 호출 카운트 |
| `.claude/ralph-session.json` | 세션 정보 |
| `status.json` | 모니터링용 상태 |
| `experiments.md` | 진행 상황 로그 (compact 마다 갱신) |

## 환경 변수

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `RALPH_MAX_CALLS_PER_HOUR` | 100 | 시간당 최대 API 호출 |
| `RALPH_API_LIMIT_HOURS` | 5 | API 제한 해제 대기 시간 |
| `RALPH_SESSION_EXPIRY_HOURS` | 24 | 세션 만료 시간 |

## 트러블슈팅

### 루프가 재개되지 않음
1. `.claude/ralph-loop.local.md` 파일 확인
2. `active: true` 확인

### Stop Hook 미작동
1. Git Bash 설치 확인
2. hooks.json의 Stop 정의 확인

### Circuit Breaker OPEN
1. experiments.md 확인
2. git log로 진행 상황 확인
3. 문제 해결 후 `/ralph-loop "continue"` 실행

### Rate Limit 도달
1. status.json에서 reset 시간 확인
2. 자동 재개 대기

## 관련 명령어

- `/ralph-loop` - 루프 시작
- `/ralph-loop:setup` - 프로젝트 설정
- `/ralph-loop:import` - PRD 가져오기
- `/ralph-loop:help` - 도움말
- `/cancel-ralph` - 루프 취소
