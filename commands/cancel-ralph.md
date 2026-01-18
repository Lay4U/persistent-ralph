---
description: "Cancel active Ralph Loop"
---

# Cancel Ralph Loop

Stop the currently active Ralph loop.

## Instructions

1. **Check if loop is active:**
   Check if `.claude/ralph-loop.local.md` exists

2. **If file NOT found:**
   Tell the user "No active Ralph loop found."

3. **If file EXISTS:**
   - Read `.claude/ralph-loop.local.md` to get the current iteration
   - Delete the file to stop the loop
   - Report: "Cancelled Ralph loop at iteration N"

4. **Confirm to user:**
   - Loop has been cancelled
   - To restart: `/persistent-ralph:ralph-loop "continue previous work"`
