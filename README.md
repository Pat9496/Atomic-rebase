# Atomic-rebase

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Shell: Bash](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnubash&logoColor=white)](Atomic-rebase.sh)
[![ShellCheck](https://github.com/Pat9496/Atomic-rebase/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/Pat9496/Atomic-rebase/actions/workflows/shellcheck.yml)
[![Fedora](https://img.shields.io/badge/Fedora-Atomic%20Desktop-0B57A6)](https://fedoraproject.org/atomic-desktops/)

Helper scripts to switch a [Fedora Atomic Desktop](https://fedoraproject.org/atomic-desktops/)
installation between its different desktop-environment images, while keeping
as much of the existing user configuration intact as is realistically
possible.

[Deutsche Version](README.de.md)

## Table of Contents

- [Supported desktops](#supported-desktops)
- [Why this exists](#why-this-exists)
- [What actually happens on a rebase](#what-actually-happens-on-a-rebase)
- [Requirements](#requirements)
- [Usage](#usage)
- [Rolling back](#rolling-back)
- [Contributing](#contributing)
- [Credits](#credits)
- [License](#license)

## Supported desktops

| Desktop | Name passed to `--to` | Image | Trust |
|---|---|---|---|
| GNOME | `silverblue` | `quay.io/fedora/fedora-silverblue` | Covered by the pre-configured signed `fedora` ostree remote |
| KDE Plasma | `kinoite` | `quay.io/fedora/fedora-kinoite` | Covered by the pre-configured signed `fedora` ostree remote |
| Budgie | `budgie` | `quay.io/fedora-ostree-desktops/budgie-atomic` | Not covered by the `fedora` remote, pulled unverified |
| Sway | `sway` | `quay.io/fedora/fedora-sway-atomic` | Covered by the pre-configured signed `fedora` ostree remote |
| COSMIC | `cosmic` | `quay.io/fedora-ostree-desktops/cosmic-atomic` | Not covered by the `fedora` remote, pulled unverified |

Any of the five can be rebased to any other.

## Why this exists

Fedora ships each Atomic Desktop as its own separate container image,
swapped via `rpm-ostree rebase`. Silverblue, Kinoite, and Sway Atomic (formerly Sericea) are pulled through the
signed `fedora` ostree remote that's pre-configured on every Atomic Desktop
install. Budgie Atomic (formerly Onyx) and
COSMIC Atomic are maintained by their respective SIGs and published under a
separate registry namespace that isn't covered by that same pre-configured
remote — `rpm-ostree` pulls those unverified.

> [!WARNING]
> Rebasing between Fedora Atomic Desktop variants is not an officially
> documented/supported workflow, and rebasing to a Budgie/COSMIC Atomic
> image means trusting an unverified, community-maintained image. Use at
> your own risk, on a system you can afford to reinstall or roll back.

## What actually happens on a rebase

On an ostree-based system, only `/usr` is replaced wholesale and `/etc` is
three-way merged on a rebase — `/home` and `/var` (which is where
`/var/lib/flatpak` lives) are untouched. In practice this means:

- Your files, shell config, SSH keys, Flatpak apps, Flatpak per-app data, and
  your login/user-switcher avatar (stored via AccountsService under
  `/var/lib/AccountsService`) already survive a rebase on their own —
  nothing needs to be "restored" for those.
- What does **not** carry over automatically is anything that only makes
  sense inside one desktop's own configuration system (KConfig for Plasma,
  `dconf`/`gsettings` for GNOME/Budgie, Sway's config with a generated
  drop-in override at `~/.config/sway/config.d/99-atomic-rebase.conf`, a
  different config store again for COSMIC). Neither desktop reads the
  other's format, so after a rebase the new desktop simply starts from its
  own defaults for anything it's never been configured before.

These scripts back up a snapshot of your current settings for reference, and
actively re-apply a small, well-defined set of equivalent preferences
(dark/light mode, wallpaper, accent colour, keyboard layouts, night light,
idle lock, key repeat, and default terminal where a mechanism exists) in the
new desktop's native config system. See
[`config-map/README.md`](config-map/README.md) for exactly what is and
isn't migrated, and how confident each mechanism is per desktop.

## Requirements

- A running Fedora Atomic Desktop install (any of the five above), with
  `rpm-ostree` and `sudo` available (present by default on all of them).
  `jq` is used if present for more reliable image-reference detection, but
  isn't required.
- Rebasing to Budgie or COSMIC additionally requires `curl` and `jq`
  (both required, not just `jq` if present): since those images have no
  `:latest` tag, the script queries bodhi.fedoraproject.org to identify the
  current stable Fedora release, then confirms that tag exists on quay.io
  before rebasing.
- Your install must be deployed **container-native** (from a
  `quay.io/fedora/...`-style container image), not from the classic ostree
  `fedora:fedora/...` remote that ships by default on install media — these
  scripts identify the current/target desktop from the container image
  reference and can't compute a rebase target from a plain ostree ref. Check
  with `rpm-ostree status`; if you're on the ostree remote, first rebase to
  your current desktop's container image (e.g.
  `sudo rpm-ostree rebase ostree-unverified-registry:quay.io/fedora/fedora-silverblue:<version>`)
  before using `Atomic-rebase.sh`.
- Run as your normal user, not root — the scripts elevate with `sudo`
  internally only for the `rpm-ostree rebase` step itself, and for
  `restore-config.sh`'s optional re-layering of known-safe packages (see
  below), since the dconf/gsettings/flatpak inspection needs to run in your
  own user session.

## Usage

```bash
./Atomic-rebase.sh --to <silverblue|kinoite|budgie|sway|cosmic> [--no-migrate] [-y|--yes] [--dry-run]
```

This detects your current desktop from the booted image, computes the
target image (always the latest stable release of the destination desktop,
regardless of what tag/digest the current image is on), and walks you
through the rest. Useful flags:

- `--no-migrate` — rebase without backing up settings. Afterwards there is nothing to restore, except for Sway: you can run `bin/lib/restore-config.sh --to sway --no-migrate` to be asked a few setup questions (see below).
- `--dry-run` — print what would happen without changing anything.
- `-y`/`--yes` — skip the confirmation prompt.

```bash
# From any Atomic Desktop, switch to Kinoite
./Atomic-rebase.sh --to kinoite

# From any Atomic Desktop, switch to Silverblue
./Atomic-rebase.sh --to silverblue
```

The script:

1. Detects your current image and desktop, and computes the target as the
   destination desktop's own latest stable release.
2. If `--no-migrate` is not set, runs `bin/lib/backup-config.sh` to snapshot current settings under
   `~/.local/share/atomic-rebase/backups/<timestamp>/`. Backup directories
   are created with mode 700, and `settings.env` is a literal `KEY=value`
   file that `restore-config.sh` parses using a key whitelist and never
   sources directly. If `--no-migrate` is set, this step is skipped.
3. Prints the exact target image and warns if it's a community-maintained,
   unverified image, then asks for confirmation before doing anything (skip
   the prompt with `-y`; preview only with `--dry-run`).
4. Runs `rpm-ostree rebase` (via `sudo`) to stage the new deployment.
5. Tells you to reboot. If a backup was created, tells you to run `bin/lib/restore-config.sh` afterwards. If `--no-migrate` was used with Sway, tells you to run `bin/lib/restore-config.sh --to sway --no-migrate` to be asked setup questions.

After rebooting into the new desktop:

```bash
bin/lib/restore-config.sh --to <silverblue|kinoite|budgie|sway|cosmic> [--from <backup-dir> | --no-migrate] [--fresh-sway-config] [-y|--yes]
```

- `--from <backup-dir>` — restore from a specific backup directory (by default, the most recent is used). Cannot be combined with `--no-migrate`.
- `--no-migrate` — for Sway only. Ask interactive setup questions instead of reading a backup. Cannot be combined with `--from`.
- `--fresh-sway-config` — for Sway only. Move an existing `~/.config/sway/config` aside (as `config.bak-<timestamp>`, never deleted) so sway starts from Fedora's default config plus the generated drop-in.
- `-y`/`--yes` — skip confirmation prompts and non-interactive setup questions.

This re-applies the settings captured in the backup that have a known
equivalent in the new desktop. With `--no-migrate`, no backup is read; instead
(Sway only), when run in a terminal without `-y`, it asks a few setup questions:

- Keyboard layout(s), with the captured value (if any) as the default; empty answer skips.
- Keyboard variant(s), one per layout and comma-separated; empty skips.
- Display scaling factor for all outputs (0.5–4); empty keeps Sway's automatic default.
- Touchpad tap-to-click and natural (reversed) scrolling; empty skips each.
- GTK dark mode (only asked if not captured from the source desktop); empty skips.

These answers are written into the generated Sway drop-in (see below). With `-y` or non-interactive stdin, questions are skipped entirely.

The script also offers to re-layer any ostree-layered
RPM packages (`rpm-ostree install`) from a small allowlist of common,
desktop-agnostic CLI tools (alacritty, btop, chezmoi, cmatrix, distrobox,
fastfetch, gh, htop, neovim, podman-compose, rpmdevtools, tmux,
vim-enhanced, xclip, xdotool, xsel, and any `git`/`git-*` package) that were
layered on the old desktop — but only if a backup was read (not with `--no-migrate`). Confirm once (or pass `-y`/`--yes` to skip the prompt) and it re-layers them via `sudo`, taking effect on next reboot.
Anything else layered — including hardware-specific drivers/akmods
(e.g. `xorg-x11-drv-nvidia`, `akmod-nvidia`) and the virtualization stack
(`libvirt`, `qemu-kvm`, `virt-install`, `swtpm`, `edk2-ovmf`), which are
kernel-version- or hardware-coupled and too consequential to reinstall
unattended — is left for you to reinstall manually. It writes a `MANUAL-STEPS.txt`
next to the backup listing what was and wasn't migrated this run (panel/dock
layout, keyboard shortcuts, default app associations, desktop
extensions/widgets, and similar desktop-specific setup are always manual —
see [`config-map/README.md`](config-map/README.md)). With `--no-migrate`, no `MANUAL-STEPS.txt` is written.

### Sway as a rebase target

When rebasing to Sway, the script detects and warns about proprietary NVIDIA kernel arguments and drivers from the old desktop, which survive the rebase and can keep Sway from booting properly. The kernel arguments `rd.driver.blacklist=nouveau` and `modprobe.blacklist=nouveau` block the open-source driver, and the proprietary driver cannot run Sway's `greetd` greeter without special flags, which can make boot hang before the login screen.

The script checks for:
- Kernel arguments matching the pattern `rd.driver.blacklist=nouveau`, `modprobe.blacklist=nouveau`, and `nvidia-drm.*`
- Layered packages matching `akmod-nvidia*`, `kmod-nvidia*`, `xorg-x11-drv-nvidia*`, and `nvidia-*`

If found (even during `--dry-run`), it warns you and asks whether to remove them with `rpm-ostree kargs --delete` and `rpm-ostree uninstall` before rebasing. If you decline, it warns you may need to roll back with `sudo rpm-ostree rollback -r`.

> [!NOTE]
> This detection and removal is untested on real hardware with proprietary NVIDIA drivers. After rebooting, verify the kernel arguments were removed by running `rpm-ostree kargs`.

After rebooting into Sway, run `restore-config.sh` as normal.

### Sway as a restore target

When restoring to Sway, the generated drop-in at `~/.config/sway/config.d/99-atomic-rebase.conf` (mode 600) carries keyboard layouts, keyboard variants, display scaling, touchpad settings, key repeat, wallpaper, GTK dark mode/accent color, and terminal preference. Values come either from the backup (if one was read) or from the interactive setup questions (if using `--no-migrate` and running in a terminal without `-y`). Your main `~/.config/sway/config` is never created or modified; if you have one, it must include `config.d/*.conf` or `restore-config.sh` will warn and add the line to `MANUAL-STEPS.txt`. Existing `99-atomic-rebase.conf` files not generated by this tool are never overwritten. Changes reload automatically if `swaymsg reload` is available and Sway is running; otherwise they take effect on next start/reload. The terminal is applied only if that binary exists on the new system; otherwise Fedora's default `foot` is left unchanged.

## Rolling back

If something goes wrong, `rpm-ostree` keeps the previous deployment around:

```bash
sudo rpm-ostree rollback
```

reboot, and you're back on the prior image untouched.

## Contributing

Bug reports, feature requests, and pull requests are welcome. Before you start, read the ground rules and code style below. Security issues should be reported privately via the repository's Security tab → **Report a vulnerability**, not as public issues.

**Ground rules:**
- Write all commits, comments, documentation, issues, and pull requests in English.
- Each pull request should contain one logical change. Avoid unrelated refactoring.
- Add only the features or abstractions you need right now, not for hypothetical future use.

**Code style:**

Every script starts with:

```bash
#!/usr/bin/env bash
set -euo pipefail
```

When writing Bash:
- Quote all variable and command expansions: `"${var}"`, `"$(cmd)"`.
- Use `[[ ]]` for tests, not `[ ]`.
- Use 4-space indentation.
- Comments explain *why*, not *what* — see the existing code for examples.

Before committing, check syntax and lint:

```bash
bash -n Atomic-rebase.sh bin/lib/*.sh
shellcheck Atomic-rebase.sh bin/lib/*.sh
```

This is the same check that runs in CI (`.github/workflows/shellcheck.yml`).

**Adding a new desktop:**

1. Register it in `bin/lib/common.sh` in the `DESKTOP_IMAGE` and `DESKTOP_OFFICIAL` maps, with a citable source for the image reference in your PR description.
2. Add settings capture in `bin/lib/backup-config.sh` and apply logic in `bin/lib/restore-config.sh` (see existing desktops for patterns).
3. Update `config-map/README.md` to document what is and is not migrated. State your confidence honestly — Sway and COSMIC have no official settings CLI, so best-effort approaches are expected.

**Testing:**

No test suite exists — these scripts manipulate real system state that cannot be mocked. Validation is manual:

- Syntax check: `bash -n Atomic-rebase.sh bin/lib/*.sh`
- Dry-run each affected desktop: `./Atomic-rebase.sh --to <desktop> --dry-run`
- Run `backup-config.sh` and `restore-config.sh` on a real Fedora Atomic Desktop in the target session; restore your own settings afterwards.
- Never test the actual `rpm-ostree rebase` on a system you cannot roll back (`sudo rpm-ostree rollback`) or reinstall.

**Pull requests:**

Describe what you changed and how you tested it. Keep `config-map/README.md` in sync with your migration work — the `MANUAL-STEPS.txt` output must match it.

**Issues:**

Use the provided issue templates. Report security issues via the Security tab → **Report a vulnerability**, not as public issues.

## Credits

- The [Fedora Project](https://fedoraproject.org) and the teams behind
  [Fedora Atomic Desktops](https://fedoraproject.org/atomic-desktops/), for
  the images and the `rpm-ostree` rebase mechanism these scripts build on.
- The [KDE Plasma](https://kde.org/plasma-desktop/) project, for the
  `kreadconfig`/`plasma-apply-colorscheme`/`plasma-apply-wallpaperimage`
  CLI tooling used to read and apply KDE settings.
- The [GNOME](https://www.gnome.org/) project, for `gsettings`/`dconf`,
  used to read and apply GNOME (and Budgie, which shares the same stack)
  settings.
- The [Sway](https://swaywm.org/) and [COSMIC](https://system76.com/cosmic/)
  projects.

## License

[MIT](LICENSE)
