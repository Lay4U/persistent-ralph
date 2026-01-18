---
description: "Explain Ralph Loop plugin and available commands"
---

# Persistent Ralph Help

Please explain the following to the user:

## Overview

Persistent Ralph is a **fully autonomous agent system** for Claude Code. It never stops until the task is complete, even after auto-compact.

## Core Hooks

| Hook | Function |
|------|----------|
| **Stop** | Blocks session exit (`decision: block`) + Rate Limiting |
| **PreCompact** | Saves state before compact (`experiments.md`) |
| **SessionStart** | Auto-resumes on new session (context injection) |
| **UserPromptSubmit** | Replaces empty input with task prompt |

## Safety Features

### 1. Circuit Breaker
- **CLOSED**: Normal operation
- **HALF_OPEN**: Monitoring mode (2 iterations with no progress)
- **OPEN**: Stops execution (5 iterations with no progress)

### 2. Response Analyzer
- Parses `RALPH_STATUS` blocks
- Detects completion signals
- Dual-condition EXIT_SIGNAL gate

### 3. Rate Limiter
- 100 API calls/hour limit
- 5-hour API limit detection
- Automatic reset and resume

### 4. Session Manager
- 24-hour session expiry
- Session history tracking
- Automatic session extension

### 5. Status Generator
- Real-time `status.json` generation
- External monitoring support
- Progress tracking

## Commands

### Project Setup
```bash
/persistent-ralph:setup
```
Creates PROMPT.md, @fix_plan.md, @AGENT.md and specs/ directory.

### Import PRD
```bash
/persistent-ralph:import <path-to-prd>
```
Converts PRD to Ralph specs format.

### Start Ralph Loop
```bash
/persistent-ralph:ralph-loop "task description" --completion-promise "DONE" --max-iterations 100
```

### Check Status
```bash
cat status.json
```

### Cancel Loop
```bash
/persistent-ralph:cancel-ralph
```

## RALPH_STATUS Block

Claude reports status in this format:

```
---RALPH_STATUS---
STATUS: IN_PROGRESS | COMPLETE | BLOCKED
TASKS_COMPLETED_THIS_LOOP: <number>
FILES_MODIFIED: <number>
TESTS_STATUS: PASSING | FAILING | NOT_RUN
WORK_TYPE: IMPLEMENTATION | TESTING | DOCUMENTATION | REFACTORING
EXIT_SIGNAL: false | true
RECOMMENDATION: <next step summary>
---END_RALPH_STATUS---
```

### EXIT_SIGNAL = true Conditions
1. All items in @fix_plan.md completed
2. All tests passing
3. No errors
4. All specs/ requirements implemented

## Completion Condition

Loop exits when Claude outputs:

```
<promise>DONE</promise>
```

## State Files

| File | Description |
|------|-------------|
| `.claude/ralph-loop.local.md` | Loop state (iteration, promise) |
| `.claude/circuit-breaker.json` | Circuit breaker state |
| `.claude/call-count.json` | API call counter |
| `status.json` | Monitoring status |
| `experiments.md` | Progress log |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `RALPH_MAX_CALLS_PER_HOUR` | 100 | Max API calls per hour |
| `RALPH_API_LIMIT_HOURS` | 5 | Hours to wait after rate limit |
| `RALPH_SESSION_EXPIRY_HOURS` | 24 | Session expiry time |

## Troubleshooting

### Loop doesn't resume
1. Check `.claude/ralph-loop.local.md` exists
2. Verify `active: true`

### Stop Hook not working
1. Verify Git Bash is installed
2. Check hooks.json Stop definition

### Circuit Breaker OPEN
1. Check experiments.md
2. Review git log for progress
3. Restart with `/persistent-ralph:ralph-loop "continue"`

### Rate Limit reached
1. Check status.json for reset time
2. Wait for automatic resume
