# Ralph PRD Import

Convert a PRD (Product Requirements Document) or any requirements document into Ralph format.

## Usage

```
/ralph-loop:import <path-to-prd>
```

Or with content:
```
/ralph-loop:import
<paste PRD content here>
```

## Instructions

1. **Read the PRD/requirements document**

2. **Create specs/ directory if not exists**

3. **Convert PRD to Ralph specs:**

   For each major feature or requirement section:
   - Create a spec file in `specs/` (e.g., `specs/feature-auth.md`)
   - Use this format:

   ```markdown
   # Feature: [Name]

   ## Overview
   [Brief description]

   ## Requirements
   - [ ] Requirement 1
   - [ ] Requirement 2

   ## Acceptance Criteria
   - [ ] Criteria 1
   - [ ] Criteria 2

   ## Technical Notes
   [Any implementation hints]
   ```

4. **Update @fix_plan.md:**

   Convert requirements to prioritized tasks:

   ```markdown
   # Ralph Fix Plan

   ## High Priority
   - [ ] [Critical tasks from PRD]

   ## Medium Priority
   - [ ] [Important but not critical]

   ## Low Priority
   - [ ] [Nice to have]

   ## Completed
   - [x] Project initialization
   - [x] PRD import
   ```

5. **Update PROMPT.md:**

   Add project-specific context to PROMPT.md's "Context" section.

6. **Commit the import:**
   ```bash
   git add .
   git commit -m "feat: Import PRD to Ralph specs"
   ```

## Output

After import, report:
- Number of spec files created
- Number of tasks added to @fix_plan.md
- Suggested first task to tackle

## Example

If PRD contains:
```
## User Authentication
- Users can register with email
- Users can login with password
- Password reset via email
```

Create `specs/auth.md`:
```markdown
# Feature: User Authentication

## Requirements
- [ ] User registration with email
- [ ] Login with password
- [ ] Password reset via email

## Acceptance Criteria
- [ ] Valid email format required
- [ ] Password minimum 8 characters
- [ ] Reset email sent within 1 minute
```

And add to @fix_plan.md:
```markdown
## High Priority
- [ ] Implement user registration with email validation
- [ ] Implement login with password authentication
- [ ] Implement password reset flow
```
