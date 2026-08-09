# Contributing to Atomic-rebase

Thanks for considering a contribution. This is a small collection of Bash
scripts, so the bar is mostly: keep it simple, keep it safe, and test it on
a real Fedora Atomic Desktop system before opening a pull request.

## Ground rules

- All commit messages, code comments, documentation, issues, and pull
  requests must be written in English.
- Keep changes focused — one logical change per pull request.
- Don't add features or abstractions beyond what's needed to solve the
  problem at hand.

## Code style

- `#!/usr/bin/env bash` and `set -euo pipefail` at the top of every script.
- Quote all variable expansions; use `[[ ]]` for conditionals.
- 4-space indentation (see `.editorconfig`).
- Comments should explain *why*, not *what* — only add one where the
  reasoning genuinely isn't obvious from the code.
- Run [ShellCheck](https://www.shellcheck.net/) against any script you
  touch before opening a pull request:

  ```bash
  shellcheck Atomic-rebase.sh bin/lib/*.sh
  ```

  The same check runs in CI on every pull request (see
  `.github/workflows/shellcheck.yml`).

## Adding a new desktop

The image catalog is centralized in `bin/lib/common.sh`
(`DESKTOP_IMAGE`/`DESKTOP_OFFICIAL`) — that's the only place a new desktop's
image reference needs to be registered for rebasing to work. Don't add a
new image name or registry path without a source you'd cite in the pull
request description (a Fedora Magazine post, the SIG's own docs, etc.) —
these commands run `sudo rpm-ostree rebase` against real systems.

If the new desktop has a settings-migration mechanism worth adding, extend
`apply_dark_mode`/the wallpaper `case` in `bin/lib/restore-config.sh` and
`bin/lib/backup-config.sh`'s desktop-detection branches, and update
`config-map/README.md` to match — be explicit in that table about how
confident the mechanism actually is (Sway and COSMIC in particular have no
official settings CLI, so anything there is inherently best-effort).

## Testing your changes

There's no test suite — these scripts talk to real system state
(`rpm-ostree`, `dconf`/`gsettings`, KDE's `kreadconfig`/`plasma-apply-*`
tools, COSMIC's config files), so validation is manual:

- Syntax-check every script you changed: `bash -n path/to/script.sh`
- Exercise `./Atomic-rebase.sh --to <desktop> --dry-run` for every desktop
  pair your change affects, to confirm image-reference computation still
  behaves correctly.
- If your change touches `backup-config.sh` or `restore-config.sh`, run it
  for real on a Fedora Atomic Desktop system (in the relevant desktop
  session) and confirm the values it reads/writes are correct. If you
  change a setting it applies (dark mode, wallpaper), restore your own
  prior value afterwards so you don't leave your test system in a
  different state than you found it.
- Never test the actual `rpm-ostree rebase` step against a system you're
  not prepared to roll back (`sudo rpm-ostree rollback`) or reinstall.

## Pull requests

- Describe what you changed and how you tested it (see the pull request
  template).
- If you're changing what is or isn't migrated between desktops, update
  `config-map/README.md` to match — `restore-config.sh`'s
  `MANUAL-STEPS.txt` output is expected to stay in sync with that table.

## Reporting bugs / requesting features

Use the issue templates under **Issues → New Issue**. For security
vulnerabilities, see [`SECURITY.md`](SECURITY.md) instead of opening a
public issue.
