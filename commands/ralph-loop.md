---
description: "Start Ralph Loop in current session"
argument-hint: "PROMPT [--max-iterations N] [--completion-promise TEXT]"
---

# Ralph Loop Command

## STEP 0: Read project rules (CRITICAL!)

**BEFORE doing anything else**, read the project's rule files to understand constraints:

1. Check for and read these files if they exist:
   - `@AGENT.md` - Agent instructions and constraints
   - `requirements.md` - Project requirements and forbidden actions
   - `PROMPT.md` - Development instructions
   - `@fix_plan.md` - Current TODO and fixed assumptions

2. **Extract all constraints and forbidden actions** from these files
3. **Include key constraints in the state file** you create in Step 1

This prevents violating project rules (e.g., "100% position sizing" means NO leverage).

## STEP 1: Create the state file

After reading rules, create the Ralph loop state file. Use the Write tool to create `.claude/ralph-loop.local.md` with this content:

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
1. **Read @AGENT.md, requirements.md, PROMPT.md** for project rules and constraints
2. Create `.claude/ralph-loop.local.md` state file (include key constraints!)
3. Check git log and experiments.md for previous work
4. Continue where you left off (respecting all constraints)
5. Make progress on the task
6. Output RALPH_STATUS block
7. END your response (Stop hook handles the rest)

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
