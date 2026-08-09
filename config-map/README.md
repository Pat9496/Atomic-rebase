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
| Sway Atomic    | Same `gsettings`/`color-scheme` key, **but this only themes GTK apps** — Sway itself (a Wayland compositor, not a full desktop) has no dark-mode concept of its own | Not read back (no reliable way to query the active `swaybg` wallpaper); but can be *applied* on restore via `swaymsg output "*" bg <path> fill` if a wallpaper path was captured from a different source desktop |
| Cosmic Atomic  | Direct read/write of `~/.config/cosmic/com.system76.CosmicTheme.Mode/v1/is_dark` (`true`/`false`) — there is no official `cosmic-settings` CLI; a re-login may be needed for it to take effect | Not captured — the `cosmic-bg` config format under `~/.config/cosmic/com.system76.CosmicBackground/v1` is not confirmed stable enough to parse/write; manual step |

| Desktop        | Accent color                                                                                          | Keyboard layout                                                                    | Night light                                                                        | Idle timeout / screen lock                                                        |
|-----------------|-----------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------|
| Silverblue (GNOME) | `gsettings get/set org.gnome.desktop.interface accent-color` (one of `blue`/`teal`/`green`/`yellow`/`orange`/`red`/`pink`/`purple`/`slate`/`brown`) | `gsettings get/set org.gnome.desktop.input-sources sources` (xkb layout codes only; variants like `dvorak` are dropped) | `gsettings get/set org.gnome.settings-daemon.plugins.color night-light-enabled`/`-temperature` | `gsettings get/set org.gnome.desktop.screensaver lock-enabled` + `org.gnome.desktop.session idle-delay` (seconds; `0` = never) |
| Kinoite (KDE Plasma) | Write-only via `plasma-apply-colorscheme --accent-color`, reusing whatever `ColorScheme` is set in `kdeglobals`; **not captured as a source** — no confirmed way to read the active accent color back from disk | `kxkbrc` (group `Layout`, keys `LayoutList`/`Use`), reconfigured via `qdbus`/`qdbus6 org.kde.KWin /KWin reconfigure`; a logout may still be needed | `kwinrc` (group `NightColor`, keys `Active`/`NightTemperature`), same `KWin reconfigure` call | `kscreenlockerrc` (group `Daemon`, keys `Autolock`/`Timeout` — Timeout is **minutes**, converted to/from GNOME's seconds; a captured `0` ("never") is left unset rather than rounded up to 1 minute) |
| Budgie Atomic  | Same `gsettings`/`accent-color` key as GNOME                                                          | Same `gsettings`/`input-sources` key as GNOME (Budgie relies on gnome-settings-daemon)  | Same `gsettings`/`night-light-*` keys as GNOME                                        | Same `gsettings` keys as GNOME                                                        |
| Sway Atomic    | Same `gsettings`/`accent-color` key, **GTK apps only**, same caveat as dark mode                       | *Not captured* — no gnome-settings-daemon runs under Sway, so `input-sources` would be stale, not the real sway-config layout. Can still be **applied** at runtime via `swaymsg input type:keyboard xkb_layout <code>` (first layout only; doesn't persist across reboot) | *Not captured* — no gnome-settings-daemon runs under Sway to act on these keys | *Not captured* — idle/lock on Sway is handled by the separate `swayidle` program, not a simple config key |
| Cosmic Atomic  | *Not captured* — config format not confirmed                                                          | *Not captured* — config format not confirmed                                          | *Not captured* — config format not confirmed                                          | *Not captured* — config format not confirmed                                          |

| Desktop        | Keyboard repeat rate/delay                                                                              |
|-----------------|-------------------------------------------------------------------------------------------------------------|
| Silverblue (GNOME) | `gsettings get/set org.gnome.desktop.peripherals.keyboard delay`/`repeat-interval` (both milliseconds) |
| Kinoite (KDE Plasma) | `kcminputrc` (group `Keyboard`, keys `RepeatDelay` in ms, `RepeatRate` in **characters/second** — converted to/from GNOME's ms interval via reciprocal, e.g. 40ms ↔ 25cps) |
| Budgie Atomic  | Same `gsettings` keys as GNOME                                                                          |
| Sway Atomic    | *Not captured* — no gnome-settings-daemon runs under Sway; real repeat rate comes from the sway config file |
| Cosmic Atomic  | *Not captured* — config format not confirmed                                                            |

Every read is best-effort — a missing value is a `warn` and an omitted key
in `settings.env`, never a hard failure. `restore-config.sh` records exactly
what it applied vs. skipped for each run in `MANUAL-STEPS.txt`.

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
