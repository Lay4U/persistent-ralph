---
description: "Start Ralph Loop in current session"
argument-hint: "PROMPT [--max-iterations N] [--completion-promise TEXT]"
---

# Ralph Loop Command

## STEP 1: Create the state file

First, create the Ralph loop state file. Use the Write tool to create `.claude/ralph-loop.local.md` with this content:

```markdown
---
active: true
iteration: 1
max_iterations: 0
completion_promise: null
started_at: "[current timestamp]"
---

[THE USER'S PROMPT/TASK GOES HERE]
```

Parse the ARGUMENTS:
- If `--max-iterations N` is provided, set `max_iterations: N`
- If `--completion-promise "TEXT"` is provided, set `completion_promise: "TEXT"`
- Everything else is the PROMPT

## STEP 2: Start working

After creating the state file, immediately start working on the task.

## CRITICAL INSTRUCTIONS

**DO NOT WAIT FOR USER INPUT. EVER.**

1. Create the state file first
2. Start working on the task IMMEDIATELY
3. When you finish one step, move to the next step WITHOUT asking
4. DO NOT ask "should I continue?" or "what next?"
5. DO NOT wait for confirmation
6. When you think you're done, just END your response (the Stop hook will restart you)
7. The loop will automatically feed the same prompt back to you

**WORKFLOW:**
1. Create `.claude/ralph-loop.local.md` state file
2. Check git log and experiments.md for previous work
3. Continue where you left off
4. Make progress on the task
5. Output RALPH_STATUS block
6. END your response (Stop hook handles the rest)

**RALPH_STATUS FORMAT (output at end of each iteration):**
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

CRITICAL RULE: If a completion promise is set, you may ONLY output `<promise>TEXT</promise>` when the statement is completely and unequivocally TRUE.

NOW CREATE THE STATE FILE AND START WORKING. DO NOT ASK QUESTIONS.
