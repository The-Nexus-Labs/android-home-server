## Skills

- [git-and-commit-guidelines.md](skills/git-and-commit-guidelines.md)

## Working rules for this repo

- Prefer extending existing device and OS abstractions instead of hardcoding special cases in the interactive flow.
- Keep shared behavior in `scripts/common.sh` and stage-specific behavior in dedicated scripts.
- Keep provisioning reproducible and rerunnable. If a step can be resumed safely, prefer resume logic over one-shot assumptions.
