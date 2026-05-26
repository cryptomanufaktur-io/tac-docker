# Contributing to tac-docker

Thank you for your interest in contributing to tac-docker!

## Development Setup

1. Fork the repository
2. Clone your fork:
   ```bash
   git clone https://github.com/YOUR_USERNAME/tac-docker.git
   cd tac-docker
   ```
3. Create a branch for your changes:
   ```bash
   git checkout -b feature/your-feature-name
   ```

## Code Style

### Bash Scripts
- Use `#!/usr/bin/env bash` shebang
- Enable strict mode: `set -Eeuo pipefail` (or `set -euo pipefail` for entrypoints)
- Use double quotes around variables
- Prefix private functions with double underscore: `__function_name`
- Use SCREAMING_SNAKE_CASE for environment variables
- No dashes in variable names

### Docker Compose
- Use YAML anchors for repeated configuration (e.g., logging)
- Keep services organized and well-commented
- Use explicit version tags, avoid `latest`

### Documentation
- Keep README.md up to date with new features
- Update CLAUDE.md for significant architectural changes
- Add inline comments for complex logic

## Testing

Before submitting a PR:

1. **Test the build**:
   ```bash
   ./tacd update
   ```

2. **Test basic operations**:
   ```bash
   ./tacd up
   ./tacd logs
   ./tacd ps
   ./tacd down
   ```

3. **Verify configuration changes**:
   ```bash
   # Check that environment variables are properly used
   ./tacd exec-node env | grep TAC
   ```

4. **Test with a fresh environment**:
   ```bash
   docker volume rm tac-docker_consensus-data
   ./tacd up
   ```

## Shellcheck

If you modify bash scripts, run shellcheck:

```bash
# Install shellcheck (Ubuntu/Debian)
sudo apt-get install shellcheck

# Check scripts
shellcheck tacd
shellcheck tac/docker-entrypoint.sh
shellcheck scripts/check_sync.sh
```

## Pull Request Process

1. Update documentation for any user-facing changes
2. Test your changes thoroughly
3. Ensure scripts pass shellcheck
4. Create a pull request with a clear description of:
   - What changes you made
   - Why you made them
   - How you tested them

## Version Bumps

When updating `default.env`:

1. Increment `ENV_VERSION` if you:
   - Add new environment variables
   - Rename existing variables
   - Remove variables
   - Change default values in a breaking way

2. Document the migration in the `tacd` script if needed

## Reporting Issues

When reporting issues, include:

- Your operating system and version
- Docker version (`docker --version`)
- Docker Compose version (`docker compose version`)
- Relevant logs (`./tacd logs`)
- Steps to reproduce the issue

## Questions?

Open an issue for questions or discussion!
