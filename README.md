# Atomic-rebase

Helper scripts to switch a [Fedora Atomic Desktop](https://fedoraproject.org/atomic-desktops/)
installation between its different desktop-environment images, while keeping
as much of the existing user configuration intact as is realistically
possible.

## Supported desktops

| Desktop | Name passed to `--to` | Image | Trust |
|---|---|---|---|
| GNOME | `silverblue` | `quay.io/fedora/fedora-silverblue` | Covered by the pre-configured signed `fedora` ostree remote |
| KDE Plasma | `kinoite` | `quay.io/fedora/fedora-kinoite` | Covered by the pre-configured signed `fedora` ostree remote |
| Budgie | `budgie` | `quay.io/fedora-ostree-desktops/budgie-atomic` | Not covered by the `fedora` remote, pulled unverified |
| Sway | `sway` | `quay.io/fedora-ostree-desktops/sway-atomic` | Not covered by the `fedora` remote, pulled unverified |
| COSMIC | `cosmic` | `quay.io/fedora-ostree-desktops/cosmic-atomic` | Not covered by the `fedora` remote, pulled unverified |

Any of the five can be rebased to any other.

## Why this exists

Fedora ships each Atomic Desktop as its own separate container image,
swapped via `rpm-ostree rebase`. Silverblue and Kinoite are pulled through the
signed `fedora` ostree remote that's pre-configured on every Atomic Desktop
install. Sway Atomic (formerly Sericea), Budgie Atomic (formerly Onyx), and
COSMIC Atomic are maintained by their respective SIGs and published under a
separate registry namespace that isn't covered by that same pre-configured
remote — `rpm-ostree` pulls those unverified.

> [!WARNING]
> Rebasing between Fedora Atomic Desktop variants is not an officially
> documented/supported workflow, and rebasing to a Sway/Budgie/COSMIC Atomic
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
- Rebasing to Budgie, Sway, or COSMIC additionally requires `curl` and `jq`
  (both required, not just `jq` if present): since those images have no
  `:latest` tag, the script queries the quay.io API at rebase time to find
  their current latest stable tag.
- Your install must be deployed **container-native** (from a
  `quay.io/fedora/...`-style container image), not from the classic ostree
  `fedora:fedora/...` remote that ships by default on install media — these
  scripts identify the current/target desktop from the container image
  reference and can't compute a rebase target from a plain ostree ref. Check
  with `rpm-ostree status`; if you're on the ostree remote, first rebase to
  your current desktop's container image (e.g.
  `sudo rpm-ostree rebase ostree-remote-registry:fedora:quay.io/fedora/fedora-silverblue:<version>`)
  before using `Atomic-rebase.sh`.
- Run as your normal user, not root — the scripts elevate with `sudo`
  internally only for the `rpm-ostree rebase` step itself, and for
  `restore-config.sh`'s optional re-layering of known-safe packages (see
  below), since the dconf/gsettings/flatpak inspection needs to run in your
  own user session.

## Usage

```bash
./Atomic-rebase.sh --to <silverblue|kinoite|budgie|sway|cosmic>
```

This detects your current desktop from the booted image, computes the
target image (always the latest stable release of the destination desktop,
regardless of what tag/digest the current image is on), and walks you
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

1. Detects your current image and desktop, and computes the target as the
   destination desktop's own latest stable release.
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
equivalent in the new desktop. It also offers to re-layer any ostree-layered
RPM packages (`rpm-ostree install`) from a small allowlist of common,
desktop-agnostic CLI tools (alacritty, btop, chezmoi, cmatrix, distrobox,
fastfetch, gh, htop, neovim, podman-compose, rpmdevtools, tmux,
vim-enhanced, xclip, xdotool, xsel, and any `git`/`git-*` package) that were
layered on the old desktop — confirm once (or pass `-y`/`--yes` to skip the
prompt) and it re-layers them via `sudo`, taking effect on next reboot.
Anything else layered — including hardware-specific drivers/akmods
(e.g. `xorg-x11-drv-nvidia`, `akmod-nvidia`) and the virtualization stack
(`libvirt`, `qemu-kvm`, `virt-install`, `swtpm`, `edk2-ovmf`), which are
kernel-version- or hardware-coupled and too consequential to reinstall
unattended — is left for you to reinstall manually. It writes a `MANUAL-STEPS.txt`
next to the backup listing what was and wasn't migrated this run (panel/dock
layout, keyboard shortcuts, default app associations, desktop
extensions/widgets, and similar desktop-specific setup are always manual —
see [`config-map/README.md`](config-map/README.md)).

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
