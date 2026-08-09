# Atomic-rebase

Helper scripts to switch a [Fedora Atomic Desktop](https://fedoraproject.org/atomic-desktops/)
installation between its different desktop-environment images, while keeping
as much of the existing user configuration intact as is realistically
possible.

## Supported desktops

| Desktop | Name passed to `--to` | Image | Trust |
|---|---|---|---|
| GNOME | `silverblue` | `quay.io/fedora/fedora-silverblue` | Official, signed via the pre-configured `fedora` ostree remote |
| KDE Plasma | `kinoite` | `quay.io/fedora/fedora-kinoite` | Official, signed via the pre-configured `fedora` ostree remote |
| Budgie | `budgie` | `quay.io/fedora-ostree-desktops/budgie-atomic` | Community-maintained, pulled unverified |
| Sway | `sway` | `quay.io/fedora-ostree-desktops/sway-atomic` | Community-maintained, pulled unverified |
| COSMIC | `cosmic` | `quay.io/fedora-ostree-desktops/cosmic-atomic` | Community-maintained, pulled unverified |

Any of the five can be rebased to any other.

## Why this exists

Fedora ships each Atomic Desktop as its own separate container image,
swapped via `rpm-ostree rebase`. Silverblue and Kinoite are official Fedora
images. Sway Atomic (formerly Sericea), Budgie Atomic (formerly Onyx), and
COSMIC Atomic are maintained by their respective SIGs and published to a
separate, community-run registry that isn't backed by the same signed
`fedora` ostree remote — `rpm-ostree` pulls those unverified.

> [!WARNING]
> Rebasing between Fedora Atomic Desktop variants is not an officially
> documented/supported workflow, and rebasing to a Sway/Budgie/COSMIC Atomic
> image means trusting an unverified, community-maintained image. Use at
> your own risk, on a system you can afford to reinstall or roll back.

## What actually happens on a rebase

On an ostree-based system, only `/usr` is replaced wholesale and `/etc` is
three-way merged on a rebase — `/home` and `/var` (which is where
`/var/lib/flatpak` lives) are untouched. In practice this means:

- Your files, shell config, SSH keys, Flatpak apps, and Flatpak per-app data
  already survive a rebase on their own — nothing needs to be "restored" for
  those.
- What does **not** carry over automatically is anything that only makes
  sense inside one desktop's own configuration system (KConfig for Plasma,
  `dconf`/`gsettings` for GNOME/Budgie, plain config files for Sway, a
  different config store again for COSMIC). Neither desktop reads the
  other's format, so after a rebase the new desktop simply starts from its
  own defaults for anything it's never been configured before.

These scripts back up a snapshot of your current settings for reference, and
actively re-apply a small, well-defined set of equivalent preferences
(dark/light mode, and wallpaper where there's a reliable mechanism) in the
new desktop's native config system. See
[`config-map/README.md`](config-map/README.md) for exactly what is and
isn't migrated, and how confident each mechanism is per desktop.

## Requirements

- A running Fedora Atomic Desktop install (any of the five above), with
  `rpm-ostree` and `sudo` available (present by default on all of them).
  `jq` is used if present for more reliable image-reference detection, but
  isn't required.
- Run as your normal user, not root — the scripts elevate with `sudo`
  internally only for the `rpm-ostree rebase` step itself, since the
  dconf/gsettings/flatpak inspection needs to run in your own user session.

## Usage

```bash
./Atomic-rebase.sh --to <silverblue|kinoite|budgie|sway|cosmic>
```

This detects your current desktop from the booted image, computes the
target image (keeping your current device/version tag), and walks you
through the rest. Useful flags:

- `--dry-run` — print what would happen without changing anything.
- `-y`/`--yes` — skip the confirmation prompt.

```bash
# From any Atomic Desktop, switch to Kinoite
./Atomic-rebase.sh --to kinoite

# From any Atomic Desktop, switch to Silverblue
./Atomic-rebase.sh --to silverblue
```

The script:

1. Detects your current image and desktop (the Fedora version/tag is
   preserved — only the desktop-environment image changes).
2. Runs `bin/lib/backup-config.sh` to snapshot current settings under
   `~/.local/share/atomic-rebase/backups/<timestamp>/`.
3. Prints the exact target image and warns if it's a community-maintained,
   unverified image, then asks for confirmation before doing anything (skip
   the prompt with `-y`; preview only with `--dry-run`).
4. Runs `rpm-ostree rebase` (via `sudo`) to stage the new deployment.
5. Tells you to reboot, and to run `bin/lib/restore-config.sh` afterwards.

After rebooting into the new desktop:

```bash
bin/lib/restore-config.sh --to <silverblue|kinoite|budgie|sway|cosmic>
```

This re-applies the settings captured in step 2 that have a known
equivalent in the new desktop, and writes a `MANUAL-STEPS.txt` next to the
backup listing what was and wasn't migrated this run (panel/dock layout,
keyboard shortcuts, default app associations, desktop extensions/widgets,
and similar desktop-specific setup are always manual — see
[`config-map/README.md`](config-map/README.md)).

## Rolling back

If something goes wrong, `rpm-ostree` keeps the previous deployment around:

```bash
sudo rpm-ostree rollback
```

reboot, and you're back on the prior image untouched.

## Contributing

Bug reports, feature requests, and pull requests are welcome — see
[`CONTRIBUTING.md`](CONTRIBUTING.md) for coding style and how to test
changes. Security issues should be reported privately per
[`SECURITY.md`](SECURITY.md) rather than filed as public issues.

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
