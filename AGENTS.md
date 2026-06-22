# AGENTS.md

## Cursor Cloud specific instructions

This repository is a **static GitHub profile README** (`README.md`) for a personal
profile. There is no application source code, package manifest, build system,
automated test suite, or linter configuration. The "product" is simply the
Markdown profile as rendered by GitHub.

- **Build / test / lint:** none exist. There is nothing to compile, no tests to
  run, and no lint config. Do not invent build/test infrastructure unless a task
  explicitly asks for it.
- **Run / preview the profile:** the faithful way to view the page as GitHub
  renders it is with a GitHub-flavored Markdown previewer such as
  [`grip`](https://github.com/joeyespo/grip). It serves the rendered README on a
  local port (default `6419`):

  ```bash
  python3 -m venv /tmp/gripenv
  /tmp/gripenv/bin/pip install grip
  /tmp/gripenv/bin/grip README.md 0.0.0.0:6419
  # then open http://localhost:6419/
  ```

  Note: creating the venv requires the `python3.12-venv` system package
  (`sudo apt-get install -y python3.12-venv`). `grip` calls GitHub's Markdown
  rendering API, so previewing requires outbound network access.
