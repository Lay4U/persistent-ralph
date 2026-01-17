# Persistent Ralph Help

Please explain the following to the user:

## 개요

Persistent Ralph는 **완전 자율 에이전트 시스템**입니다. Auto-compact 이후에도 절대 멈추지 않습니다.

## 핵심 기능

| Hook | 기능 |
|------|------|
| **Stop** | 세션 종료 차단 (`decision: block`) |
| **PreCompact** | Compact 전 상태 저장 (`experiments.md`) |
| **SessionStart** | 새 세션에서 자동 재개 (컨텍스트 주입) |
| **UserPromptSubmit** | 빈 입력 시 프롬프트 대체 |

## 사용법

### Ralph Loop 시작

```bash
/ralph-loop "작업 설명" --completion-promise "DONE" --max-iterations 100
```

### 완료 조건

Claude가 다음 형식으로 출력하면 루프 종료:

```
<promise>DONE</promise>
```

### 취소

```bash
/cancel-ralph
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
│                  AUTO-COMPACT 시                     │
├─────────────────────────────────────────────────────┤
│                                                      │
│   [Compact 감지] ────▶ [PreCompact Hook]            │
│                               │                     │
│                               ▼                     │
│                     [상태 저장: experiments.md]     │
│                               │                     │
│                               ▼                     │
│                        [Compact 실행]               │
│                               │                     │
│                               ▼                     │
│                     [SessionStart Hook]             │
│                               │                     │
│                               ▼                     │
│                    [컨텍스트 주입 + 자동 재개]      │
│                                                      │
└─────────────────────────────────────────────────────┘
```

## 랄프의 법칙

1. **멈추지 않는다** - 목표 달성까지 계속
2. **실패는 학습** - 기록하고 다음 시도에 반영
3. **과감히 버린다** - 안 되는 것에 집착 금지
4. **반복적 개선** - 완벽한 첫 시도보다 나음
5. **항상 방법이 있다** - "불가능"은 없다

## 상태 파일

- `.claude/ralph-loop.local.md` - 루프 상태 (iteration, promise 등)
- `experiments.md` - 진행 상황 로그 (compact 마다 갱신)

## 트러블슈팅

### 루프가 재개되지 않음
1. `.claude/ralph-loop.local.md` 파일 확인
2. `active: true` 확인

### Stop Hook 미작동
1. Git Bash 설치 확인
2. hooks.json의 Stop 정의 확인

## 관련 명령어

- `/ralph-loop` - 루프 시작
- `/cancel-ralph` - 루프 취소
