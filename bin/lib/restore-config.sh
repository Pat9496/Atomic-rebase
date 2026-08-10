#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# shellcheck source=SCRIPTDIR/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require_not_root

usage() {
    printf 'Usage: %s --to <%s> [--from <backup-dir>] [-y|--yes]\n' \
        "$(basename "${BASH_SOURCE[0]}")" "$(known_desktops | paste -sd'|')" >&2
}

target_desktop=""
from_dir=""
ASSUME_YES="${ASSUME_YES:-0}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --to)
            [[ $# -ge 2 ]] || { err "--to requires an argument."; exit 1; }
            target_desktop="$2"
            shift 2
            ;;
        --from)
            [[ $# -ge 2 ]] || { err "--from requires an argument."; exit 1; }
            from_dir="$2"
            shift 2
            ;;
        -y|--yes)
            ASSUME_YES=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            err "Unknown argument: $1"
            usage
            exit 1
            ;;
    esac
done

if ! is_known_desktop "${target_desktop}"; then
    err "You must specify --to <desktop>."
    usage
    exit 1
fi

if [[ -z "${from_dir}" ]]; then
    from_dir="$(latest_backup_dir)"
fi

if [[ ! -d "${from_dir}" ]]; then
    err "Backup directory not found: ${from_dir}"
    exit 1
fi

settings_file="${from_dir}/settings.env"
if [[ ! -f "${settings_file}" ]]; then
    err "No settings.env found in ${from_dir}"
    exit 1
fi

SOURCE_DESKTOP=""
DARK_MODE=""
WALLPAPER_PATH=""
ACCENT_COLOR=""
INPUT_LAYOUTS=""
NIGHT_LIGHT=""
NIGHT_LIGHT_TEMP=""
IDLE_LOCK=""
IDLE_DELAY_SECONDS=""
KEY_REPEAT_DELAY_MS=""
KEY_REPEAT_INTERVAL_MS=""
# shellcheck source=/dev/null
source "${settings_file}"
log "Settings were captured on: ${SOURCE_DESKTOP:-unknown desktop}"

applied=()
skipped=()

# Applies DARK_MODE to the target desktop's own native config mechanism.
# Returns 1 if the target has no known mechanism (currently unreachable,
# since every entry in DESKTOP_IMAGE is handled below, but kept as a guard
# in case a new desktop is added to the catalog without updating this file).
apply_dark_mode() {
    local target="$1" value="$2"
    case "${target}" in
        silverblue|budgie)
            require_cmd gsettings
            if [[ "${value}" == "true" ]]; then
                gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
            else
                gsettings set org.gnome.desktop.interface color-scheme 'default'
            fi
            ;;
        kinoite)
            require_cmd plasma-apply-colorscheme
            if [[ "${value}" == "true" ]]; then
                plasma-apply-colorscheme BreezeDark
            else
                plasma-apply-colorscheme BreezeClassic
            fi
            ;;
        sway)
            require_cmd gsettings
            warn "Sway has no desktop-wide dark mode; only the GTK app color-scheme is being set."
            if [[ "${value}" == "true" ]]; then
                gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
            else
                gsettings set org.gnome.desktop.interface color-scheme 'default'
            fi
            ;;
        cosmic)
            local mode_dir="${HOME}/.config/cosmic/com.system76.CosmicTheme.Mode/v1"
            mkdir -p "${mode_dir}"
            printf '%s' "${value}" > "${mode_dir}/is_dark"
            warn "Wrote ${mode_dir}/is_dark directly (COSMIC has no settings CLI); a re-login may be needed for it to take effect."
            ;;
        *)
            return 1
            ;;
    esac
}

if [[ -n "${DARK_MODE}" ]]; then
    if apply_dark_mode "${target_desktop}" "${DARK_MODE}"; then
        applied+=("dark/light mode")
    else
        warn "No dark-mode mechanism defined for ${target_desktop}."
        skipped+=("dark/light mode")
    fi
else
    warn "No DARK_MODE recorded in ${settings_file}; skipping."
    skipped+=("dark/light mode")
fi

if [[ -n "${WALLPAPER_PATH}" ]]; then
    case "${target_desktop}" in
        silverblue)
            require_cmd gsettings
            wallpaper_uri="file://${WALLPAPER_PATH}"
            gsettings set org.gnome.desktop.background picture-uri "${wallpaper_uri}"
            gsettings set org.gnome.desktop.background picture-uri-dark "${wallpaper_uri}"
            applied+=("wallpaper")
            ;;
        kinoite)
            require_cmd plasma-apply-wallpaperimage
            plasma-apply-wallpaperimage "${WALLPAPER_PATH}"
            applied+=("wallpaper")
            ;;
        sway)
            if command -v swaymsg >/dev/null 2>&1; then
                swaymsg output "*" bg "${WALLPAPER_PATH}" fill >/dev/null
                applied+=("wallpaper")
            else
                warn "swaymsg not found; skipping wallpaper."
                skipped+=("wallpaper")
            fi
            ;;
        *)
            warn "No confirmed wallpaper mechanism for ${target_desktop}; skipping."
            skipped+=("wallpaper")
            ;;
    esac
else
    warn "No WALLPAPER_PATH recorded in ${settings_file}; skipping."
    skipped+=("wallpaper")
fi

# kdeglobals has no confirmed way to read the accent color back (see
# backup-config.sh), so apply_accent_color always derives the KDE base
# scheme from whatever apply_dark_mode just set (or the scheme already on
# disk if dark mode wasn't applied this run) rather than guessing one.
apply_accent_color() {
    local target="$1" value="$2"
    case "${target}" in
        silverblue|budgie)
            require_cmd gsettings
            gsettings set org.gnome.desktop.interface accent-color "${value}"
            ;;
        sway)
            require_cmd gsettings
            warn "Sway has no desktop-wide accent color; only the GTK app accent-color is being set."
            gsettings set org.gnome.desktop.interface accent-color "${value}"
            ;;
        kinoite)
            require_cmd plasma-apply-colorscheme
            local kde_color="${value}"
            # GNOME's "slate" isn't a standard SVG/CSS color name; slategray
            # is the closest real one plasma-apply-colorscheme will accept.
            [[ "${kde_color}" == "slate" ]] && kde_color="slategray"
            local scheme
            scheme="$(kde_read_config --file kdeglobals --group General --key ColorScheme)"
            if [[ -z "${scheme}" ]]; then
                warn "Could not determine the current KDE color scheme; skipping accent color."
                return 1
            fi
            plasma-apply-colorscheme --accent-color "${kde_color}" "${scheme}"
            ;;
        *)
            return 1
            ;;
    esac
}

if [[ -n "${ACCENT_COLOR}" ]]; then
    if apply_accent_color "${target_desktop}" "${ACCENT_COLOR}"; then
        applied+=("accent color")
    else
        warn "No accent-color mechanism defined for ${target_desktop}."
        skipped+=("accent color")
    fi
else
    warn "No ACCENT_COLOR recorded in ${settings_file}; skipping."
    skipped+=("accent color")
fi

# Applies INPUT_LAYOUTS (a comma-separated list of xkb layout codes, e.g.
# "us,de") captured from GNOME/Budgie's input-sources or KDE's kxkbrc.
# Keyboard variants (dvorak, colemak, ...) are not preserved by this tool.
apply_input_layouts() {
    local target="$1" value="$2"
    case "${target}" in
        silverblue|budgie)
            require_cmd gsettings
            local tuples="" layout first=1 layout_arr
            IFS=',' read -ra layout_arr <<< "${value}"
            for layout in "${layout_arr[@]}"; do
                [[ -n "${layout}" ]] || continue
                if ((first)); then
                    tuples="('xkb', '${layout}')"
                    first=0
                else
                    tuples="${tuples}, ('xkb', '${layout}')"
                fi
            done
            [[ -n "${tuples}" ]] || return 1
            gsettings set org.gnome.desktop.input-sources sources "[${tuples}]"
            ;;
        kinoite)
            kde_write_config --file kxkbrc --group Layout --key LayoutList "${value}"
            kde_write_config --file kxkbrc --group Layout --key Use true
            kwin_reconfigure
            warn "Wrote kxkbrc directly; a logout/login may be needed for the new keyboard layout to fully apply."
            ;;
        sway)
            if command -v swaymsg >/dev/null 2>&1; then
                local first_layout="${value%%,*}"
                swaymsg input type:keyboard xkb_layout "${first_layout}" >/dev/null
                warn "Applied only the first layout (${first_layout}) via swaymsg; this is a runtime change only and won't survive a reboot unless added to the sway config."
            else
                warn "swaymsg not found; skipping keyboard layout."
                return 1
            fi
            ;;
        *)
            return 1
            ;;
    esac
}

if [[ -n "${INPUT_LAYOUTS}" ]]; then
    if apply_input_layouts "${target_desktop}" "${INPUT_LAYOUTS}"; then
        applied+=("keyboard layout")
    else
        warn "No keyboard-layout mechanism defined for ${target_desktop}."
        skipped+=("keyboard layout")
    fi
else
    warn "No INPUT_LAYOUTS recorded in ${settings_file}; skipping."
    skipped+=("keyboard layout")
fi

# Applies NIGHT_LIGHT (true/false) and, if present, NIGHT_LIGHT_TEMP (Kelvin).
apply_night_light() {
    local target="$1" enabled="$2" temp="$3"
    case "${target}" in
        silverblue|budgie)
            require_cmd gsettings
            gsettings set org.gnome.settings-daemon.plugins.color night-light-enabled "${enabled}"
            [[ -n "${temp}" ]] && gsettings set org.gnome.settings-daemon.plugins.color night-light-temperature "${temp}"
            ;;
        kinoite)
            kde_write_config --file kwinrc --group NightColor --key Active "${enabled}"
            [[ -n "${temp}" ]] && kde_write_config --file kwinrc --group NightColor --key NightTemperature "${temp}"
            kwin_reconfigure
            ;;
        *)
            return 1
            ;;
    esac
}

if [[ -n "${NIGHT_LIGHT}" ]]; then
    if apply_night_light "${target_desktop}" "${NIGHT_LIGHT}" "${NIGHT_LIGHT_TEMP}"; then
        applied+=("night light")
    else
        warn "No night-light mechanism defined for ${target_desktop}."
        skipped+=("night light")
    fi
else
    warn "No NIGHT_LIGHT recorded in ${settings_file}; skipping."
    skipped+=("night light")
fi

# Applies IDLE_LOCK (true/false) and/or IDLE_DELAY_SECONDS. GNOME's
# idle-delay is in seconds, with 0 meaning "never" (not "instantly"); KDE's
# kscreenlockerrc Timeout is in whole minutes with no "never" value of its
# own, so a captured 0 is left for Autolock=false to represent instead of
# being rounded up into a very short, unintended lock timeout.
apply_idle_lock() {
    local target="$1" lock_enabled="$2" delay_seconds="$3"
    case "${target}" in
        silverblue|budgie)
            require_cmd gsettings
            [[ -n "${lock_enabled}" ]] && gsettings set org.gnome.desktop.screensaver lock-enabled "${lock_enabled}"
            [[ -n "${delay_seconds}" ]] && gsettings set org.gnome.desktop.session idle-delay "${delay_seconds}"
            ;;
        kinoite)
            [[ -n "${lock_enabled}" ]] && kde_write_config --file kscreenlockerrc --group Daemon --key Autolock "${lock_enabled}"
            if [[ -n "${delay_seconds}" && "${delay_seconds}" -eq 0 ]]; then
                warn "Source idle-delay was 0 (\"never\"); KDE's Timeout has no equivalent value, so it's left unset (rely on Autolock instead)."
            elif [[ -n "${delay_seconds}" ]]; then
                local minutes=$(( (delay_seconds + 59) / 60 ))
                ((minutes < 1)) && minutes=1
                kde_write_config --file kscreenlockerrc --group Daemon --key Timeout "${minutes}"
            fi
            ;;
        *)
            return 1
            ;;
    esac
}

if [[ -n "${IDLE_LOCK}" || -n "${IDLE_DELAY_SECONDS}" ]]; then
    if apply_idle_lock "${target_desktop}" "${IDLE_LOCK}" "${IDLE_DELAY_SECONDS}"; then
        applied+=("idle timeout/screen lock")
    else
        warn "No idle-timeout/screen-lock mechanism defined for ${target_desktop}."
        skipped+=("idle timeout/screen lock")
    fi
else
    warn "No IDLE_LOCK/IDLE_DELAY_SECONDS recorded in ${settings_file}; skipping."
    skipped+=("idle timeout/screen lock")
fi

# Applies KEY_REPEAT_DELAY_MS and/or KEY_REPEAT_INTERVAL_MS. GNOME's
# repeat-interval is milliseconds between repeats; KDE's RepeatRate is
# characters/second — the two are reciprocals, converted via awk since
# bash can't do the division (and KDE's value may not be a whole number).
apply_keyboard_repeat() {
    local target="$1" delay_ms="$2" interval_ms="$3"
    case "${target}" in
        silverblue|budgie)
            require_cmd gsettings
            [[ -n "${delay_ms}" ]] && gsettings set org.gnome.desktop.peripherals.keyboard delay "${delay_ms}"
            [[ -n "${interval_ms}" ]] && gsettings set org.gnome.desktop.peripherals.keyboard repeat-interval "${interval_ms}"
            ;;
        kinoite)
            [[ -n "${delay_ms}" ]] && kde_write_config --file kcminputrc --group Keyboard --key RepeatDelay "${delay_ms}"
            if [[ -n "${interval_ms}" ]]; then
                local rate_cps
                rate_cps="$(awk -v ms="${interval_ms}" 'BEGIN { if (ms > 0) printf "%d", (1000 / ms) + 0.5 }')"
                [[ -n "${rate_cps}" ]] && kde_write_config --file kcminputrc --group Keyboard --key RepeatRate "${rate_cps}"
            fi
            warn "Wrote kcminputrc directly; a logout/login may be needed for the new repeat rate to fully apply."
            ;;
        *)
            return 1
            ;;
    esac
}

if [[ -n "${KEY_REPEAT_DELAY_MS}" || -n "${KEY_REPEAT_INTERVAL_MS}" ]]; then
    if apply_keyboard_repeat "${target_desktop}" "${KEY_REPEAT_DELAY_MS}" "${KEY_REPEAT_INTERVAL_MS}"; then
        applied+=("keyboard repeat rate")
    else
        warn "No keyboard-repeat-rate mechanism defined for ${target_desktop}."
        skipped+=("keyboard repeat rate")
    fi
else
    warn "No KEY_REPEAT_DELAY_MS/KEY_REPEAT_INTERVAL_MS recorded in ${settings_file}; skipping."
    skipped+=("keyboard repeat rate")
fi

# Curated allowlist of common, desktop-agnostic CLI tools (no GUI or
# desktop-specific integration) that are safe to automatically re-layer via
# `rpm-ostree install` on restore. Nothing here is ever installed that wasn't
# already layered on the source desktop — this only recognizes which of the
# packages actually found in rpm-ostree-status.json are common enough to
# reapply without asking the user to type the package name back in manually.
# Git tooling is matched by prefix rather than listed exhaustively, since
# "git-lfs", "git-delta", etc. are all equally unambiguous re-layers.
is_known_safe_layered_package() {
    local pkg="$1" known
    [[ "${pkg}" == "git" || "${pkg}" == git-* ]] && return 0
    for known in alacritty btop chezmoi fastfetch gh htop neovim tmux; do
        [[ "${pkg}" == "${known}" ]] && return 0
    done
    return 1
}

join_comma() {
    local sep="" item result=""
    for item in "$@"; do
        result="${result}${sep}${item}"
        sep=", "
    done
    printf '%s' "${result}"
}

# Ostree-layered RPM packages live in /usr, which a rebase replaces (unlike
# /var, where Flatpaks live and survive untouched) — so they never carry over
# to the new base image on their own. rpm-ostree-status.json is whatever
# backup-config.sh captured, so this reads the *source* desktop's layered
# packages, not the target's.
layered_packages_known=0
layered_package_list=()
rpm_ostree_status_file="${from_dir}/rpm-ostree-status.json"
if [[ -f "${rpm_ostree_status_file}" ]] && command -v jq >/dev/null 2>&1; then
    layered_packages_known=1
    while IFS= read -r pkg; do
        [[ -n "${pkg}" ]] && layered_package_list+=("${pkg}")
    done < <(jq -r '.deployments[] | select(.booted==true) | ."requested-packages"[]?' "${rpm_ostree_status_file}" 2>/dev/null || true)
fi

safe_layered_packages=()
other_layered_packages=()
for pkg in "${layered_package_list[@]}"; do
    if is_known_safe_layered_package "${pkg}"; then
        safe_layered_packages+=("${pkg}")
    else
        other_layered_packages+=("${pkg}")
    fi
done

reinstalled_packages=()
if ((${#safe_layered_packages[@]})); then
    safe_str="$(join_comma "${safe_layered_packages[@]}")"
    if command -v rpm-ostree >/dev/null 2>&1 && command -v sudo >/dev/null 2>&1; then
        if confirm "Re-layer known packages onto ${target_desktop} via rpm-ostree install (${safe_str})?"; then
            if sudo rpm-ostree install --idempotent -y "${safe_layered_packages[@]}"; then
                reinstalled_packages=("${safe_layered_packages[@]}")
                applied+=("layered packages (reboot required)")
            else
                warn "rpm-ostree install failed for one or more known layered packages (${safe_str}); reinstall them manually."
                other_layered_packages+=("${safe_layered_packages[@]}")
                skipped+=("layered packages")
            fi
        else
            log "Skipped re-layering known packages."
            other_layered_packages+=("${safe_layered_packages[@]}")
            skipped+=("layered packages")
        fi
    else
        warn "rpm-ostree or sudo not found; skipping automatic re-layering of known packages (${safe_str})."
        other_layered_packages+=("${safe_layered_packages[@]}")
        skipped+=("layered packages")
    fi
fi

applied_str="none"
if ((${#applied[@]})); then
    applied_str="$(IFS=', '; printf '%s' "${applied[*]}")"
fi
skipped_str="none"
if ((${#skipped[@]})); then
    skipped_str="$(IFS=', '; printf '%s' "${skipped[*]}")"
fi

manual_steps_file="${from_dir}/MANUAL-STEPS.txt"
{
    printf 'Rebase: %s -> %s\n\n' "${SOURCE_DESKTOP:-unknown}" "${target_desktop}"
    printf 'Automatically applied this run: %s\n' "${applied_str}"
    printf 'Not applied this run (see warnings above for why): %s\n\n' "${skipped_str}"
    if ((${#reinstalled_packages[@]})); then
        printf -- '- Ostree-layered RPM packages: re-layered automatically this run via rpm-ostree install: %s. Like the rebase itself, this takes effect on next reboot.\n' "$(join_comma "${reinstalled_packages[@]}")"
    fi
    if ((${#other_layered_packages[@]})); then
        printf -- '- Ostree-layered RPM packages not reinstalled automatically: %s. Rebasing replaces /usr, so these are gone after switching to a different base image (unlike Flatpaks, which live on /var and persist automatically). Reinstall what you still need with rpm-ostree install <package>.\n' "$(join_comma "${other_layered_packages[@]}")"
    fi
    if ! ((layered_packages_known)); then
        printf -- '- Ostree-layered RPM packages: could not determine what was layered at backup time (jq not available, or rpm-ostree-status.json missing from this backup); check rpm-ostree status output from before the rebase. Rebasing replaces /usr, so anything layered is gone after switching to a different base image (Flatpaks are unaffected).\n'
    elif ((${#layered_package_list[@]} == 0)); then
        printf -- '- Ostree-layered RPM packages: none were recorded at backup time.\n'
    fi
    printf '\n'
    printf 'Always manual, regardless of source/target (no reliable cross-desktop equivalent):\n\n'
    printf -- '- Panel/dock/taskbar layout, widgets, and system tray configuration\n'
    printf -- '- Global and per-application keyboard shortcuts\n'
    printf -- '- Default application associations (~/.config/mimeapps.list entries reference desktop-specific app IDs, e.g. org.kde.dolphin.desktop vs org.gnome.Nautilus.desktop)\n'
    printf -- '- Per-application settings for desktop-bundled apps (file manager, terminal, etc.)\n'
    printf -- '- Workspace/virtual-desktop and window-rule setup (KDE Activities, GNOME workspaces, Sway config, ...)\n'
    printf -- '- Desktop extensions/widgets/panels (GNOME Shell extensions, KDE Plasma widgets, Budgie applets, Sway bar/keybindings, COSMIC applets)\n'
    printf -- "- Icon theme and GTK/Qt application style (the desktops do not share a theme format)\n"
} > "${manual_steps_file}"

log "Applied: ${applied_str}"
log "Skipped: ${skipped_str}"
log "Manual steps checklist written to ${manual_steps_file}"
