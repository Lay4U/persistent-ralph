# Persistent Ralph

**완전 자율 Ralph Loop - Auto-compact 이후에도 절대 멈추지 않는 시스템**

## 핵심 기능

기존 `ralph-loop` 플러그인의 한계를 극복한 완전 자율 에이전트 시스템:

| 문제 | 해결책 |
|------|--------|
| Auto-compact 후 멈춤 | `PreCompact` hook으로 상태 저장, `SessionStart`로 자동 재개 |
| 세션 종료 시 멈춤 | `Stop` hook에서 `decision: block`으로 종료 차단 |
| 새 세션에서 수동 재개 필요 | `SessionStart` hook에서 강력한 컨텍스트 자동 주입 |
| 컨텍스트 손실 | `experiments.md`에 진행 상황 영구 저장 |

## 설치

### 1. 플러그인 디렉토리 생성

```bash
# Windows
mkdir -p ~/.claude/plugins/local/persistent-ralph

# 또는 직접 복사
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
- **jq** 설치 권장 (JSON 처리)
- **기존 ralph-loop 플러그인과 함께 사용** (Stop hook 보완)

## 사용법

### Ralph Loop 시작

```bash
# 완료 조건과 함께
/ralph-loop "새로운 기능 구현" --completion-promise "DONE" --max-iterations 100

# 무제한 (취소할 때까지)
/ralph-loop "실험 계속"
```

### 완료 조건

Claude가 `<promise>DONE</promise>` 형식으로 출력하면 루프 종료:

```
작업이 완료되었습니다.
<promise>DONE</promise>
```

### 취소

```bash
/cancel-ralph
# 또는
/ralph-loop:cancel-ralph
```

## 아키텍처

```
┌─────────────────────────────────────────────────────────────────┐
│                    PERSISTENT RALPH SYSTEM                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐    │
│  │  Stop Hook   │────▶│  Block Exit  │────▶│  Continue    │    │
│  │              │     │  decision:   │     │  Loop        │    │
│  │  stop-hook.sh│     │  block       │     │              │    │
│  └──────────────┘     └──────────────┘     └──────────────┘    │
│         │                                                        │
│         │ (if completion promise met)                            │
│         ▼                                                        │
│  ┌──────────────┐                                               │
│  │  Allow Exit  │                                               │
│  │  Clean up    │                                               │
│  └──────────────┘                                               │
│                                                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐    │
│  │ PreCompact   │────▶│ Save State   │────▶│ experiments. │    │
│  │ Hook         │     │ Update       │     │ md           │    │
│  │              │     │ iteration    │     │              │    │
│  └──────────────┘     └──────────────┘     └──────────────┘    │
│                                                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐    │
│  │ SessionStart │────▶│ Inject       │────▶│ Auto Resume  │    │
│  │ Hook         │     │ Context      │     │ Work         │    │
│  │              │     │ git log      │     │              │    │
│  │              │     │ experiments  │     │              │    │
│  └──────────────┘     └──────────────┘     └──────────────┘    │
│                                                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐    │
│  │ UserPrompt   │────▶│ Replace      │────▶│ Full Prompt  │    │
│  │ Submit Hook  │     │ "continue"   │     │ Injection    │    │
│  │              │     │ with task    │     │              │    │
│  └──────────────┘     └──────────────┘     └──────────────┘    │
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
│   ├── stop-hook.sh         # 세션 종료 차단
│   ├── run-stop-hook.cmd    # Windows 래퍼
│   ├── pre-compact.sh       # Compact 전 상태 저장
│   ├── run-pre-compact.cmd  # Windows 래퍼
│   ├── auto-resume.sh       # 세션 시작 시 자동 재개
│   ├── run-auto-resume.cmd  # Windows 래퍼
│   ├── prompt-replace.sh    # 빈 입력 시 프롬프트 대체
│   └── run-prompt-replace.cmd
├── commands/
│   └── help.md              # 도움말
└── README.md
```

## 상태 파일

### `.claude/ralph-loop.local.md`

```markdown
---
active: true
iteration: 5
max_iterations: 100
completion_promise: "DONE"
started_at: 2024-01-15T10:30:00Z
compact_count: 2
last_compact: 2024-01-15T12:45:00Z
---

원본 프롬프트 내용...
```

### `experiments.md`

자동 생성되는 진행 상황 로그:

```markdown
# Ralph Loop Experiments Log

## Compact Event: 2024-01-15T12:45:00Z

**Trigger:** auto
**Iteration:** 5 / 100
**Compact Count:** 2

### Recent Git Commits
abc1234 feat: add new feature
def5678 fix: resolve bug
...
```

## Hooks 상세

### Stop Hook

세션 종료 시 호출. 루프가 활성화되어 있으면 종료를 차단:

```json
{
  "decision": "block",
  "reason": "RALPH LOOP ACTIVE - Continue working on: ..."
}
```

**종료 허용 조건:**
- `completion_promise`가 출력에서 발견됨
- `max_iterations`에 도달
- 루프가 비활성화됨

### PreCompact Hook

Auto-compact 전에 실행. 상태를 저장:

- `ralph-loop.local.md`에 `compact_count` 증가
- `experiments.md`에 진행 상황 기록
- git log 스냅샷 저장

### SessionStart Hook

새 세션/compact 후 실행. 강력한 컨텍스트 주입:

- 원본 프롬프트
- 최근 git commits
- experiments.md 요약
- 즉시 시작 지시

### UserPromptSubmit Hook

빈 입력이나 "continue" 등 입력 시 전체 프롬프트로 대체.

**트리거 키워드:**
- (빈 입력/엔터)
- `c`, `continue`, `go`, `resume`, `start`
- `계속`, `시작`

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
3. Git Bash 설치 확인: `C:\Program Files\Git\bin\bash.exe`

### Stop Hook이 작동하지 않음

1. `hooks.json`에 Stop hook 정의 확인
2. `run-stop-hook.cmd` 파일 존재 확인
3. Claude Code 로그 확인

### Compact 후 컨텍스트 손실

1. `experiments.md` 파일 확인
2. `PreCompact` hook 동작 확인
3. git log로 이전 작업 확인

## 기존 ralph-loop 플러그인과의 차이점

| 기능 | ralph-loop | persistent-ralph |
|------|------------|------------------|
| Stop Hook | 없음 | **있음** (세션 종료 차단) |
| PreCompact Hook | 없음 | **있음** (상태 저장) |
| SessionStart matcher | `resume\|compact\|clear` | **없음** (모든 세션) |
| 상태 영구 저장 | 없음 | **experiments.md** |
| Auto-compact 후 재개 | 수동 | **자동** |

## 라이선스

MIT

## 참조

- [Ralph Technique by Geoffrey Huntley](https://ghuntley.com/ralph/)
- [Ralph Orchestrator](https://github.com/mikeyobrien/ralph-orchestrator)
- [ralph-claude-code](https://github.com/frankbria/ralph-claude-code)
