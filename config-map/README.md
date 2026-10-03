# Setting equivalents across Fedora Atomic Desktops

Fedora's Atomic Desktops store almost nothing in a compatible format, and
three of the five (Sway, Budgie, Cosmic Atomic) have no confirmed, reliable
CLI for reading/writing some settings at all. So this is a short, explicit
list rather than a generic mapping engine — `restore-config.sh` implements
exactly these translations in code, nothing more, and is honest in its
warnings about which of these are solid vs. best-effort.

## Actively migrated

| Desktop        | Dark/light mode                                                                                          | Wallpaper                                                                          |
|-----------------|-------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------|
| Silverblue (GNOME) | `gsettings get/set org.gnome.desktop.interface color-scheme` (`prefer-dark`/`default`)                             | `gsettings get/set org.gnome.desktop.background picture-uri` (and `picture-uri-dark`)              |
| Kinoite (KDE Plasma) | `kreadconfig6`/`kreadconfig5` (`kdeglobals`, group `General`, key `ColorScheme`); applied with `plasma-apply-colorscheme` | Plasma per-monitor wallpaper config (read via `plasma-org.kde.plasma.desktop-appletsrc`); applied with `plasma-apply-wallpaperimage` |
| Budgie Atomic  | Same `gsettings`/`color-scheme` key as GNOME (Budgie is built on the GTK/dconf stack)                                  | Not captured — no confirmed gsettings key for Budgie's own wallpaper handling; manual step        |
| Sway Atomic    | Same `gsettings`/`color-scheme` key, **but this only themes GTK apps** — Sway itself (a Wayland compositor, not a full desktop) has no dark-mode concept of its own. On restore it is set once at runtime *and* persisted as `exec_always gsettings set org.gnome.desktop.interface color-scheme '<prefer-dark\|default>'` in the generated drop-in (see below), so it is re-applied on every Sway start/reload | Not read back (no reliable way to query the active `swaybg` wallpaper); but can be *applied* on restore as `output * bg "<path>" fill` in the generated drop-in if a wallpaper path was captured from a different source desktop, the file exists on the new system, and the path can be quoted safely (no newline, quote, backslash, `$`, backtick, `;`, `,`, `#`, `{` or `}`); otherwise it is skipped with a warning |
| Cosmic Atomic  | Direct read/write of `~/.config/cosmic/com.system76.CosmicTheme.Mode/v1/is_dark` (`true`/`false`) — there is no official `cosmic-settings` CLI; a re-login may be needed for it to take effect | Not captured — the `cosmic-bg` config format under `~/.config/cosmic/com.system76.CosmicBackground/v1` is not confirmed stable enough to parse/write; manual step |

| Desktop        | Accent color                                                                                          | Keyboard layout                                                                    | Night light                                                                        | Idle timeout / screen lock                                                        |
|-----------------|-----------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------|
| Silverblue (GNOME) | `gsettings get/set org.gnome.desktop.interface accent-color` (one of `blue`/`teal`/`green`/`yellow`/`orange`/`red`/`pink`/`purple`/`slate`/`brown`) | `gsettings get/set org.gnome.desktop.input-sources sources` (xkb layout codes only; variants like `dvorak` are dropped) | `gsettings get/set org.gnome.settings-daemon.plugins.color night-light-enabled`/`-temperature` | `gsettings get/set org.gnome.desktop.screensaver lock-enabled` + `org.gnome.desktop.session idle-delay` (seconds; `0` = never) |
| Kinoite (KDE Plasma) | Write-only via `plasma-apply-colorscheme --accent-color`, reusing whatever `ColorScheme` is set in `kdeglobals`; **not captured as a source** — no confirmed way to read the active accent color back from disk | `kxkbrc` (group `Layout`, keys `LayoutList`/`Use`), reconfigured via `qdbus`/`qdbus6 org.kde.KWin /KWin reconfigure`; a logout may still be needed | `kwinrc` (group `NightColor`, keys `Active`/`NightTemperature`), same `KWin reconfigure` call | `kscreenlockerrc` (group `Daemon`, keys `Autolock`/`Timeout` — Timeout is **minutes**, converted to/from GNOME's seconds; a captured `0` ("never") is left unset rather than rounded up to 1 minute) |
| Budgie Atomic  | Same `gsettings`/`accent-color` key as GNOME                                                          | Same `gsettings`/`input-sources` key as GNOME (Budgie relies on gnome-settings-daemon)  | Same `gsettings`/`night-light-*` keys as GNOME                                        | Same `gsettings` keys as GNOME                                                        |
| Sway Atomic    | Same `gsettings`/`accent-color` key, **GTK apps only**, same caveat as dark mode; also persisted as an `exec_always gsettings set org.gnome.desktop.interface accent-color '<color>'` line in the generated drop-in | *Not captured* — no gnome-settings-daemon runs under Sway, so `input-sources` would be stale, not the real sway-config layout. Can still be **applied** on restore as `input type:keyboard { xkb_layout "<all layouts, comma-separated>" }` in the generated drop-in (all layouts, persistent; variants are still dropped). **Keyboard variants** (e.g. `dvorak`), **display scaling** (0.5–4), and **touchpad settings** (tap-to-click, natural scrolling) can be set via interactive questions when using `restore-config.sh --to sway --no-migrate` in a terminal without `-y` | *Not captured* — no gnome-settings-daemon runs under Sway to act on these keys | *Not captured* — idle/lock on Sway is handled by the separate `swayidle` program, not a simple config key |
| Cosmic Atomic  | *Not captured* — config format not confirmed                                                          | *Not captured* — config format not confirmed                                          | *Not captured* — config format not confirmed                                          | *Not captured* — config format not confirmed                                          |

| Desktop        | Keyboard repeat rate/delay                                                                              |
|-----------------|-------------------------------------------------------------------------------------------------------------|
| Silverblue (GNOME) | `gsettings get/set org.gnome.desktop.peripherals.keyboard delay`/`repeat-interval` (both milliseconds) |
| Kinoite (KDE Plasma) | `kcminputrc` (group `Keyboard`, keys `RepeatDelay` in ms, `RepeatRate` in **characters/second** — converted to/from GNOME's ms interval via reciprocal, e.g. 40ms ↔ 25cps) |
| Budgie Atomic  | Same `gsettings` keys as GNOME                                                                          |
| Sway Atomic    | *Not captured* — no gnome-settings-daemon runs under Sway; real repeat rate comes from the sway config file. Can be **applied** on restore as `repeat_delay <ms>` / `repeat_rate <chars/sec>` inside `input type:keyboard { ... }` in the generated drop-in (rate = round(1000 / interval ms), same reciprocal conversion as KDE) |
| Cosmic Atomic  | *Not captured* — config format not confirmed                                                            |

| Desktop        | Default terminal (`TERMINAL_CMD`, a hint only)                                                          |
|-----------------|-------------------------------------------------------------------------------------------------------------|
| Silverblue (GNOME) | `gsettings get org.gnome.desktop.default-applications.terminal exec` — GNOME marks this key deprecated and its schema default is `gnome-terminal` even where another terminal is in use, so it is only a hint. Only the first word's basename is kept (arguments are dropped) |
| Kinoite (KDE Plasma) | `kreadconfig6`/`kreadconfig5` (`kdeglobals`, group `General`, key `TerminalApplication`) — a command line; only the first word's basename is kept. Unset (the Konsole default) is not captured |
| Budgie Atomic  | Same `gsettings` key as GNOME                                                                           |
| Sway Atomic    | *Not captured* as a source (see "Sway as a restore target" below for the target side)                   |
| Cosmic Atomic  | *Not captured* — config format not confirmed                                                            |

The terminal is **applied on Sway only**; other targets skip it with a
warning. Launcher prefixes such as `env`, `sh`, `bash`, `dash`, `zsh`, `fish`,
`sudo` and `flatpak` are never accepted as a terminal name.

Every read is best-effort — a missing value is a `warn` and an omitted key
in `settings.env`, never a hard failure. `restore-config.sh` records exactly
what it applied vs. skipped for each run in `MANUAL-STEPS.txt`.

## Sway as a restore target

Sway has no settings CLI, so on restore `restore-config.sh` writes one
generated drop-in, `~/.config/sway/config.d/99-atomic-rebase.conf` (mode
`600`, written via a temporary file and `mv`, rewritten on every run, first
line is a marker comment). Fedora's `/etc/sway/config` ends by including
`config.d/*.conf` from `/usr/share/sway`, `/etc/sway` and
`~/.config/sway`, in name order, so the drop-in is loaded after the main body
and its values win. Sway uses only the first main config it finds, so the
user's `~/.config/sway/config` is **never created or modified** — if one
exists and has no `config.d` include, the drop-in is still written but will
not load, and `restore-config.sh` warns and lists the include line to add in
`MANUAL-STEPS.txt`. An existing `99-atomic-rebase.conf` that lacks the marker
line is never overwritten.

Values in the drop-in come from either a backup file (if one was read) or
interactive setup questions (if using `restore-config.sh --to sway --no-migrate`
in a terminal without `-y`). With a backup or answered questions, only values
that were actually captured or answered are written:

| Setting | Drop-in content | Source |
|---------|-----------------|--------|
| Keyboard layouts | `input type:keyboard { xkb_layout "<list>" }` (all layouts) | Captured from backup, or user answer |
| Keyboard variants | `xkb_variant "<list>"` inside the same input block (if any) | User answer only (not captured from other desktops) |
| Display scaling | `output * scale <n>` | User answer only (not captured from other desktops) |
| Keyboard repeat | `repeat_delay <ms>` and `repeat_rate <chars/sec>` in the same block | Captured from backup only |
| Touchpad settings | `input type:touchpad { tap <enabled\|disabled>, natural_scroll <enabled\|disabled> }` | User answer only (not captured from other desktops) |
| Wallpaper | `output * bg "<path>" fill` (only for an existing file whose path can be quoted safely) | Captured from backup only |
| Dark mode / accent color | `exec_always gsettings set org.gnome.desktop.interface color-scheme '<prefer-dark\|default>'` and `accent-color '<color>'` | Captured from backup, or user answer (for dark mode only) |
| Default terminal | `set $term <bin>` and `bindsym $mod+Return exec <bin>` — **only** if `<bin>` resolves to an executable on the new system (`type -P`); otherwise Fedora's default (`foot`) is left untouched and the name is listed in `MANUAL-STEPS.txt` | Captured from backup only |

If `SWAYSOCK` is set and `swaymsg` exists, `swaymsg reload` is run afterwards
(best-effort, never fatal); otherwise the drop-in takes effect on the next
Sway start or reload. Because of `exec_always`, the GTK color-scheme and
accent color are re-applied on every Sway start/reload. Keep local overrides
in a separate file that sorts after `99-atomic-rebase.conf`
(e.g. `99-local.conf`). Sway as a *source* desktop is unchanged: only
dark mode and accent color are captured.

When using `restore-config.sh --to sway --no-migrate` (no backup), the script
does not read settings from a backup, does not re-layer packages, and does not
write `MANUAL-STEPS.txt`. In a terminal without `-y`, interactive questions
are asked. This is useful when rebasing with `Atomic-rebase.sh --no-migrate`
and still wanting to set up keyboard/display/touchpad preferences with guided
questions rather than editing the drop-in by hand.

## Captured for reference only (nothing to restore)

| Setting      | Mechanism                                                                                                   | Why there's no restore step |
|--------------|----------------------------------------------------------------------------------------------------------------|------------------------------|
| User avatar (login/user-switcher icon) | `org.freedesktop.Accounts` (AccountsService) on the system bus, read via `busctl` for Silverblue (GNOME) and Kinoite (KDE Plasma) — `FindUserByName` then the `IconFile` property | Stored under `/var/lib/AccountsService`, which — like `/var/lib/flatpak` — is untouched by an ostree rebase, and GNOME's and KDE Plasma's avatar UIs already read/write that same shared property. There's no per-desktop format to translate the way there is for dark mode/wallpaper, so `backup-config.sh` records `AVATAR_PATH` in `settings.env` purely for reference and `restore-config.sh` never acts on it. Not attempted for Budgie/Sway/Cosmic — unconfirmed whether their user-management tooling (if any) reads the same AccountsService property. |

## Ostree-layered RPM packages (partially automatic)

Layered packages (`rpm-ostree install <package>`) live in `/usr`, which a
rebase replaces (not merges) with the target image, so unlike Flatpaks —
which live on `/var` and persist automatically — they don't survive a
switch to a different base image on their own.

`restore-config.sh` reads whatever packages were layered at backup time from
`rpm-ostree-status.json` (`requested-packages`, via `jq`) and splits them:

- **Known-safe packages** — a small curated allowlist of desktop-agnostic
  CLI tools with no GUI/desktop-specific integration (`alacritty`, `btop`,
  `chezmoi`, `cmatrix`, `distrobox`, `fastfetch`, `gh`, `htop`, `neovim`,
  `podman-compose`, `rpmdevtools`, `tmux`, `vim-enhanced`, `xclip`,
  `xdotool`, `xsel`, plus any `git` or `git-*` package such as `git-lfs`) —
  are offered back with a single `confirm` prompt (`-y`/`--yes`/`ASSUME_YES` to skip it) and, if accepted,
  re-layered with `sudo rpm-ostree install --idempotent -y <packages>`. Like
  the rebase itself, this takes effect on the next reboot.
- **Everything else** (e.g. GUI apps, desktop-specific packages, or the
  allowlist declined at the prompt) is left for the user, listed by name in
  `MANUAL-STEPS.txt` for reinstalling manually with
  `rpm-ostree install <package>`.

If `jq` isn't available, or `rpm-ostree-status.json` is missing from the
backup, `MANUAL-STEPS.txt` says so instead of silently reinstalling nothing.

## Not migrated (set manually after switching)

These have no reliable 1:1 equivalent, or depend on desktop-specific
components that don't exist on the other side, for any pair of desktops:

- Panel/dock/taskbar layout, widgets, and system tray configuration
- Global and per-application keyboard shortcuts
- Default application associations (`~/.config/mimeapps.list` entries
  reference desktop-specific app IDs, e.g. `org.kde.dolphin.desktop` vs
  `org.gnome.Nautilus.desktop`)
- Per-application settings for desktop-bundled apps (file manager,
  terminal, etc.)
- Workspace/virtual-desktop and window-rule setup (KDE Activities, GNOME
  workspaces, Sway config, ...)
- Desktop extensions/widgets/panels (GNOME Shell extensions, KDE Plasma
  widgets, Budgie applets, Sway bar/keybindings, COSMIC applets)
- Icon theme and GTK/Qt application style (the desktops do not share a
  theme format)

`restore-config.sh` writes a per-run summary of these as a checklist to
`MANUAL-STEPS.txt` alongside each backup so nothing is silently lost.
