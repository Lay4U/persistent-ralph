---
description: "Initialize the current directory as a Ralph project"
---

# Ralph Project Setup

Initialize the current directory as a Ralph project.

## Instructions

Create the following project structure and files:

1. **Create directories:**
   - `specs/` - Project specifications
   - `src/` - Source code
   - `examples/` - Example usage
   - `logs/` - Log files (add to .gitignore)
   - `.claude/` - Ralph state files (add to .gitignore)

2. **Copy template files:**
   - Create `PROMPT.md` from plugin templates/PROMPT.md
   - Create `@fix_plan.md` from plugin templates/fix_plan.md
   - Create `@AGENT.md` from plugin templates/AGENT.md

3. **Update .gitignore:**
   Add these entries:
   ```
   logs/
   .claude/
   experiments.md
   status.json
   .call_count
   .last_reset
   .exit_signals
   ```

4. **Create initial spec file:**
   Create `specs/README.md` with project goals placeholder.

5. **Commit initial setup:**
   ```bash
   git add .
   git commit -m "feat: Ralph project setup"
   ```

## After Setup

Tell the user:
- Edit `PROMPT.md` to describe your project
- Add specifications to `specs/` directory
- Update `@fix_plan.md` with initial tasks
- Start Ralph loop with: `/ralph-loop "your task"`

## IMPORTANT

Actually create all the files and directories. Do not just describe what to do.

Read the template files from the plugin directory:
- Plugin root: ${CLAUDE_PLUGIN_ROOT} or find it from this file's location
- Templates are in: `templates/PROMPT.md`, `templates/fix_plan.md`, `templates/AGENT.md`

If templates are not accessible, use default content from knowledge.
