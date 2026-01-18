# Persistent Ralph

**An autonomous agent loop for Claude Code that never stops until the task is complete.**

Based on the [Ralph Technique](https://ghuntley.com/ralph/) by Geoffrey Huntley, integrated as a Claude Code plugin.

## Features

| Problem | Solution |
|---------|----------|
| Claude stops after auto-compact | `PreCompact` hook saves state, `SessionStart` auto-resumes |
| Session ends unexpectedly | `Stop` hook blocks exit with `decision: block` |
| Manual restart needed | `SessionStart` hook injects context automatically |
| Context loss | Progress saved to `experiments.md` |

### Safety Features

- **Circuit Breaker**: Detects stagnation (5 iterations with no progress) and stops the loop
- **Rate Limiter**: 100 API calls/hour limit with automatic pause/resume
- **Session Manager**: 24-hour session expiry with auto-renewal
- **Response Analyzer**: Parses `RALPH_STATUS` blocks and detects completion signals

## Installation

### Option 1: Using `--plugin-dir` flag (Recommended for development)

```bash
# Clone the repository
git clone https://github.com/Lay4U/persistent-ralph.git

# Run Claude Code with the plugin
claude --plugin-dir /path/to/persistent-ralph
```

### Option 2: Global installation

```bash
# Copy to Claude plugins directory
mkdir -p ~/.claude/plugins/local
cp -r persistent-ralph ~/.claude/plugins/local/

# Add to ~/.claude/settings.json
{
  "enabledPlugins": {
    "persistent-ralph@local": true
  }
}
```

### Requirements

- **Git Bash** (Windows): Required for running shell scripts
- **jq**: JSON processor (`choco install jq` on Windows, `brew install jq` on macOS)

## Usage

### Quick Start

```bash
# Start a Ralph loop
/persistent-ralph:ralph-loop "Implement user authentication" --max-iterations 50

# With completion promise (loop exits when promise is fulfilled)
/persistent-ralph:ralph-loop "Fix all bugs" --completion-promise "All tests passing"
```

### Commands

| Command | Description |
|---------|-------------|
| `/persistent-ralph:ralph-loop` | Start the autonomous loop |
| `/persistent-ralph:cancel-ralph` | Cancel the active loop |
| `/persistent-ralph:setup` | Initialize project structure |
| `/persistent-ralph:import` | Import PRD as specs |
| `/persistent-ralph:help` | Show help |

### RALPH_STATUS Block

Claude reports status at the end of each iteration:

```
---RALPH_STATUS---
STATUS: IN_PROGRESS | COMPLETE | BLOCKED
TASKS_COMPLETED_THIS_LOOP: 3
FILES_MODIFIED: 5
TESTS_STATUS: PASSING | FAILING | NOT_RUN
WORK_TYPE: IMPLEMENTATION | TESTING | DOCUMENTATION | REFACTORING
EXIT_SIGNAL: false | true
RECOMMENDATION: Next step summary
---END_RALPH_STATUS---
```

### Exit Conditions

The loop exits when:
1. `EXIT_SIGNAL: true` is reported (all tasks complete)
2. Completion promise is fulfilled (e.g., `<promise>All tests passing</promise>`)
3. Circuit breaker opens (5 iterations with no progress)
4. Max iterations reached
5. User cancels with `/persistent-ralph:cancel-ralph`

## Architecture

```
persistent-ralph/
├── .claude-plugin/
│   └── plugin.json           # Plugin metadata
├── hooks/
│   ├── hooks.json            # Hook definitions
│   ├── stop-hook.sh          # Blocks session exit
│   ├── pre-compact.sh        # Saves state before compact
│   ├── auto-resume.sh        # Resumes on session start
│   ├── prompt-replace.sh     # Replaces empty prompts
│   ├── lib/                  # Utility libraries
│   │   ├── utils.sh
│   │   ├── circuit-breaker.sh
│   │   ├── rate-limiter.sh
│   │   ├── session-manager.sh
│   │   ├── response-analyzer.sh
│   │   └── status-generator.sh
│   └── run-*.cmd             # Windows wrappers
├── commands/
│   ├── ralph-loop.md         # Start loop command
│   ├── cancel-ralph.md       # Cancel loop command
│   ├── setup.md              # Project setup
│   ├── import.md             # Import PRD
│   └── help.md               # Help documentation
└── templates/
    ├── PROMPT.md             # Project prompt template
    ├── fix_plan.md           # Task list template
    └── AGENT.md              # Build instructions template
```

## State Files

| File | Description |
|------|-------------|
| `.claude/ralph-loop.local.md` | Loop state (iteration, promise) |
| `.claude/circuit-breaker.json` | Circuit breaker state |
| `.claude/call-count.json` | API call counter |
| `status.json` | External monitoring status |
| `experiments.md` | Progress log across compacts |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `RALPH_MAX_CALLS_PER_HOUR` | 100 | Max API calls per hour |
| `RALPH_API_LIMIT_HOURS` | 5 | Hours to wait after rate limit |
| `RALPH_SESSION_EXPIRY_HOURS` | 24 | Session expiry time |

## The Ralph Philosophy

> 1. Never stop until the goal is achieved
> 2. Failure is a learning opportunity - record and adapt
> 3. Don't cling to what doesn't work - pivot boldly
> 4. Iterative improvement beats perfect first attempts
> 5. "Impossible" is not in the vocabulary - there's always another way

## Troubleshooting

### Loop doesn't resume
- Check `.claude/ralph-loop.local.md` exists
- Verify `active: true` in the frontmatter

### Circuit breaker is OPEN
- Check `experiments.md` for progress history
- Review git log for recent commits
- Restart with `/persistent-ralph:ralph-loop "continue"`

### Rate limit reached
- Check `status.json` for reset time
- Wait for automatic resume

## Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT License - see [LICENSE](LICENSE) for details.

## Credits

- [Ralph Technique](https://ghuntley.com/ralph/) by Geoffrey Huntley
- [ralph-claude-code](https://github.com/frankbria/ralph-claude-code) by Frank Bria
- [Ralph Orchestrator](https://github.com/mikeyobrien/ralph-orchestrator) by Mike O'Brien
