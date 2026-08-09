# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

Bash scripts that switch an installed [Fedora Atomic Desktop](https://fedoraproject.org/atomic-desktops/)
system between any of its five desktop-environment images — Silverblue
(GNOME), Kinoite (KDE Plasma), Budgie Atomic, Sway Atomic, and COSMIC
Atomic — via `rpm-ostree rebase`, migrating the small set of settings that
have a real equivalent across desktops. There is no build step or package
manifest — it's a standalone script toolkit meant to be run directly on a
Fedora Atomic Desktop host. See `README.md` for user-facing usage,
`config-map/README.md` for exactly which settings are and aren't migrated
per desktop, and `CONTRIBUTING.md` for contribution/style guidelines.

## Commands

There is no test framework (see "Architecture" below for why these scripts
can't be meaningfully unit-tested). Useful commands when working on them:

- Syntax-check a script without running it: `bash -n Atomic-rebase.sh`
- Lint with ShellCheck (also runs in CI on every push/PR via
  `.github/workflows/shellcheck.yml`):
  `shellcheck Atomic-rebase.sh bin/lib/*.sh`. If ShellCheck isn't installed
  locally, run it via the container image instead:
  `podman run --rm -v "$(pwd)":/mnt:Z -w /mnt docker.io/koalaman/shellcheck:stable Atomic-rebase.sh bin/lib/*.sh`
- Preview what a rebase would do without changing anything:
  `./Atomic-rebase.sh --to <desktop> --dry-run` where `<desktop>` is one of
  `silverblue`, `kinoite`, `budgie`, `sway`, `cosmic`.
- These scripts are only meaningful on a real, currently-running Fedora
  Atomic Desktop host (they call `rpm-ostree`, `gsettings`/`dconf`, KDE's
  `kreadconfig6`/`plasma-apply-*` tools, or read/write COSMIC's raw config
  files directly) — there's no mock/sandbox mode beyond `--dry-run`, which
  only covers `Atomic-rebase.sh`, not `backup-config.sh`/`restore-config.sh`.

## Architecture

`Atomic-rebase.sh` at the repo root plus three scripts under `bin/lib/`:

- **`Atomic-rebase.sh`** — the single entry point for all rebase
  directions. Sources `bin/lib/common.sh`, parses `--to <desktop>`
  (`-y`/`--yes`, `--dry-run`), detects the current desktop from the booted
  image via `current_desktop()`, computes the target image via
  `compute_target_image_ref()`, warns if the target is a
  community-maintained/unverified image, confirms, backs up, then runs
  `sudo rpm-ostree rebase <target-ref>`. Unlike the two-desktop case (a
  simple KDE↔GNOME toggle), five desktops means 20 directed pairs, which is
  why this is one script with a `--to` flag rather than one script per
  direction.

- **`bin/lib/common.sh`** — sourced by everything else; not run directly.
  Holds the logic the rest of the project depends on:
  - `DESKTOP_IMAGE` / `DESKTOP_OFFICIAL` — the image catalog. This is the
    single source of truth mapping each of the five desktop names to its
    full `registry/path/image-name` (no tag) and whether it's an
    officially-signed Fedora image (Silverblue, Kinoite — pulled via the
    pre-configured `fedora` ostree remote) or a community-maintained image
    on a separate `quay.io/fedora-ostree-desktops` registry (Budgie, Sway,
    Cosmic — always pulled unverified). **This is the function to extend
    when adding a new desktop.**
  - `get_current_image_ref()` — reads the booted deployment's image
    reference via `rpm-ostree status --json` + `jq` if available, with a
    plain-text `rpm-ostree status` parse as a fallback (the JSON schema for
    the container-image-reference field has shifted across `rpm-ostree`
    releases, and `jq` isn't assumed to be preinstalled on stock Fedora
    Atomic Desktops the way it is on some downstreams).
  - `desktop_from_image_ref()` / `compute_target_image_ref()` — identify
    which desktop a full image reference belongs to, and build the target
    reference, purely by checking whether `DESKTOP_IMAGE`'s registry-path
    strings appear as a substring of the ref. This deliberately avoids
    parsing the transport prefix (`ostree-remote-registry:fedora:`,
    `ostree-unverified-registry:`, `docker://`, `@sha256:` digests, ...) —
    unlike Fedora's official images, which share one registry, the two
    trust tiers use genuinely different transports, so `rpm-ostree` accepts
    several equivalent forms for the same image and the registry-path
    substring is the only part that reliably identifies the desktop.
    `compute_target_image_ref()` always emits the *canonical* transport for
    the target's trust tier (not whatever the source ref happened to use)
    and preserves the source ref's tag/digest suffix unchanged.
  - `current_desktop()` — thin wrapper combining the two above; used by
    `Atomic-rebase.sh` to detect the current desktop for logging/dispatch.
  - Also provides `log`/`warn`/`err` (all write to stderr, deliberately —
    callers capture script stdout via command substitution to get backup
    directory paths and image refs, so stdout is reserved for data), a
    `confirm` prompt honoring a global `ASSUME_YES`, `require_cmd`/`require_not_root`
    guards, the `$BACKUP_ROOT` (`~/.local/share/atomic-rebase/backups/`)
    helpers `new_backup_dir`/`latest_backup_dir`, and the KDE-side helpers
    `kde_read_config`/`kde_write_config` (kreadconfig6/kwriteconfig6 with a
    kreadconfig5/kwriteconfig5 fallback) and `kwin_reconfigure` (best-effort
    `qdbus`/`qdbus6 org.kde.KWin /KWin reconfigure`, used after editing
    `kwinrc`/`kxkbrc` directly since there's no `plasma-apply-*` CLI for
    those two).

- **`bin/lib/backup-config.sh`** — run before a rebase (by
  `Atomic-rebase.sh`, or standalone). Writes a timestamped snapshot to
  `$BACKUP_ROOT`: a `dconf` dump, the user's Flatpak app list, `rpm-ostree
  status --json`, and a `settings.env` capturing whichever of
  `SOURCE_DESKTOP`, `DARK_MODE`, `WALLPAPER_PATH`, `ACCENT_COLOR`,
  `INPUT_LAYOUTS`, `NIGHT_LIGHT`(`_TEMP`), `IDLE_LOCK`/`IDLE_DELAY_SECONDS`,
  `KEY_REPEAT_DELAY_MS`/`KEY_REPEAT_INTERVAL_MS` it could read from the
  *current* desktop. Detects the current desktop
  from `XDG_CURRENT_DESKTOP` (Budgie is checked before plain GNOME, since
  Budgie sessions advertise `Budgie:GNOME` and would otherwise be
  misidentified as Silverblue). Two shared functions,
  `capture_gnome_interface()` and `capture_gnome_session_daemon_settings()`,
  are reused across Silverblue/Budgie/Sway rather than duplicating the
  `gsettings` calls per branch — but Sway only ever calls the first one,
  deliberately: `input-sources`/night-light/idle-lock keys still exist in
  dconf under Sway, but nothing there actually acts on them (no
  gnome-settings-daemon), so reading them would silently capture stale
  defaults instead of the user's real sway-config values. Every read is
  best-effort — a missing value is a `warn` and an omitted key in
  `settings.env`, never a hard failure. Confidence varies sharply by
  desktop and by setting — see `config-map/README.md` for the full matrix
  of what's solid vs. best-effort vs. not attempted at all per desktop.

- **`bin/lib/restore-config.sh`** — run manually after rebooting into the
  new desktop (`--to <desktop> [--from <backup-dir>]`, defaults to the most
  recent backup). Sources `settings.env` and re-applies each captured
  setting via a dedicated `apply_*()` function with a `case` branch per
  desktop (`apply_dark_mode`, `apply_accent_color`, `apply_input_layouts`,
  `apply_night_light`, `apply_idle_lock`, `apply_keyboard_repeat`; wallpaper
  stays inline as a `case` since it's a single call per branch). Three of
  these encode a real unit/format translation rather than a straight
  passthrough: idle timeout converts GNOME's seconds to KDE's whole minutes
  (and leaves KDE's `Timeout` unset rather than rounding a captured
  `0`/"never" up to a misleadingly short 1-minute lock); keyboard repeat
  rate converts between GNOME's millisecond interval and KDE's
  characters/second `RepeatRate` (reciprocals — done via `awk` since bash
  can't do the division and KDE's value may not be a whole number); and
  accent color has no KDE read path at all (see `config-map/README.md`), so
  `apply_accent_color` always derives the KDE base scheme to reapply the
  accent onto from whatever `apply_dark_mode` just set (or whatever's
  already on disk), never from a captured value. Also (re)writes
  `MANUAL-STEPS.txt` next to the backup,
  listing what was/wasn't applied this specific run plus the settings that
  are always manual regardless of source/target — that always-manual list must
  stay in sync with the table in `config-map/README.md`.

### Key invariants baked into the design

- **On ostree systems, only `/usr` is replaced and `/etc` is 3-way merged
  by a rebase — `/home` and `/var` (including `/var/lib/flatpak`) persist
  untouched.** This is why there's no "restore my dotfiles/Flatpaks" logic
  anywhere: they never leave. The only real migration problem is that each
  desktop stores desktop-level settings in an incompatible (or, for
  Sway/COSMIC, barely-tooled) format, so anything outside the
  explicitly-handled settings (dark/light mode, wallpaper where supported)
  simply resets to the new desktop's defaults — hence `MANUAL-STEPS.txt`.
- Scripts must never run as root as a whole (dconf/gsettings act on the
  invoking user's session bus, which would be wrong under `sudo`) — only
  the single `rpm-ostree rebase` invocation is elevated internally.
- Image references for new desktops must be backed by a citable source
  (see `CONTRIBUTING.md`) before being added to `DESKTOP_IMAGE` — these
  values are fed directly into `sudo rpm-ostree rebase` against real
  systems, so don't extend that table speculatively.
- Everything that reads live desktop state is written to degrade
  gracefully (`warn` + skip) rather than aborting the whole backup/restore,
  since it runs against real user systems where any given config file,
  key, or CLI tool may legitimately be absent.
