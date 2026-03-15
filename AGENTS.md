## Skills

- [git-and-commit-guidelines.md](skills/git-and-commit-guidelines.md)

## Working rules for this repo

- Prefer extending existing device and OS abstractions instead of hardcoding special cases in the interactive flow.
- Keep shared behavior in `src/common/`, `src/runtime.sh`, and `src/state.sh`, with `src/common.sh` only acting as the loader and stage-specific behavior inside the appropriate `src/steps/<nn-name>/` folder.
- Keep provisioning reproducible and rerunnable. If a step can be resumed safely, prefer resume logic over one-shot assumptions.
- After finishing a task, create a conventional commit for the completed work before ending the session.
