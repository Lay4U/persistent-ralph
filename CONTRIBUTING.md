# Contributing to Persistent Ralph

Thank you for your interest in contributing to Persistent Ralph!

## How to Contribute

### Reporting Bugs

1. Check if the issue already exists in the GitHub Issues
2. If not, create a new issue with:
   - Clear description of the problem
   - Steps to reproduce
   - Expected vs actual behavior
   - Your environment (OS, Claude Code version)

### Suggesting Features

1. Open a GitHub Issue with the `enhancement` label
2. Describe the feature and its use case
3. Explain why it would benefit the project

### Pull Requests

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Test thoroughly
5. Commit with clear messages (`git commit -m 'feat: add amazing feature'`)
6. Push to your fork (`git push origin feature/amazing-feature`)
7. Open a Pull Request

## Development Setup

```bash
# Clone your fork
git clone https://github.com/yourusername/persistent-ralph.git
cd persistent-ralph

# Test the plugin
claude --plugin-dir .
```

## Code Style

- Shell scripts: Follow [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
- Use meaningful variable names
- Add comments for complex logic
- Keep functions focused and small

## Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

- `feat:` New feature
- `fix:` Bug fix
- `docs:` Documentation changes
- `refactor:` Code refactoring
- `test:` Adding or updating tests
- `chore:` Maintenance tasks

## Testing

Before submitting a PR:

1. Test on Windows (with Git Bash) if possible
2. Test on macOS/Linux
3. Verify all hooks work correctly
4. Check that the loop starts, runs, and stops properly

## Questions?

Feel free to open an issue for any questions about contributing.
