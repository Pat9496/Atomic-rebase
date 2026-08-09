#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# shellcheck source=SCRIPTDIR/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require_not_root

backup_dir="$(new_backup_dir)"

if command -v dconf >/dev/null 2>&1; then
    if ! dconf dump / > "${backup_dir}/dconf-dump.ini" 2>/dev/null; then
        warn "Failed to dump dconf settings."
        rm -f "${backup_dir}/dconf-dump.ini"
    fi
else
    warn "dconf not found; skipping dconf dump."
fi

if command -v flatpak >/dev/null 2>&1; then
    if ! flatpak list --user --app --columns=application,version,branch,origin > "${backup_dir}/flatpak-user-apps.txt" 2>/dev/null; then
        warn "Failed to list flatpak user apps."
        rm -f "${backup_dir}/flatpak-user-apps.txt"
    fi
else
    warn "flatpak not found; skipping flatpak app list."
fi

if command -v rpm-ostree >/dev/null 2>&1; then
    if ! rpm-ostree status --json > "${backup_dir}/rpm-ostree-status.json" 2>/dev/null; then
        warn "Failed to capture rpm-ostree status."
        rm -f "${backup_dir}/rpm-ostree-status.json"
    fi
else
    warn "rpm-ostree not found; skipping status capture."
fi

source_desktop=""
dark_mode=""
wallpaper_path=""
accent_color=""
input_layouts=""
night_light=""
night_light_temp=""
idle_lock=""
idle_delay=""
key_repeat_delay=""
key_repeat_interval=""

# Reads org.gnome.desktop.interface color-scheme/accent-color via gsettings.
# Shared by Silverblue, Budgie, and (interface-only) Sway, since all three
# have GTK apps that read these same two keys regardless of which shell or
# compositor is actually running.
capture_gnome_interface() {
    local label="$1"
    if ! command -v gsettings >/dev/null 2>&1; then
        warn "gsettings not found; skipping ${label} settings read."
        return
    fi

    local color_scheme
    color_scheme="$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null || true)"
    if [[ -n "${color_scheme}" ]]; then
        if [[ "${color_scheme}" == *prefer-dark* ]]; then
            dark_mode="true"
        else
            dark_mode="false"
        fi
    else
        warn "Could not determine ${label} color-scheme."
    fi

    local accent
    accent="$(gsettings get org.gnome.desktop.interface accent-color 2>/dev/null || true)"
    accent="${accent#\'}"
    accent="${accent%\'}"
    if [[ -n "${accent}" ]]; then
        accent_color="${accent}"
    else
        warn "Could not determine ${label} accent-color."
    fi
}

# Reads the settings that are only meaningful when gnome-settings-daemon (or
# Budgie's reuse of it) is actually running to act on them: input sources,
# night light, and idle/lock. Deliberately NOT called for Sway — those keys
# still exist in dconf under Sway, but nothing reads them there (keyboard
# layout comes from the sway config file, and there's no gnome-settings-daemon
# to drive night light or idle locking), so capturing them would silently
# record stale/default values instead of what the user actually configured.
capture_gnome_session_daemon_settings() {
    local label="$1"
    if ! command -v gsettings >/dev/null 2>&1; then
        return
    fi

    local sources
    sources="$(gsettings get org.gnome.desktop.input-sources sources 2>/dev/null || true)"
    if [[ -n "${sources}" ]] && command -v grep >/dev/null 2>&1; then
        local layouts
        layouts="$(grep -oP "(?<='xkb', ')[^']*" <<<"${sources}" 2>/dev/null | cut -d'+' -f1 | paste -sd',' - || true)"
        if [[ -n "${layouts}" ]]; then
            input_layouts="${layouts}"
        else
            warn "Could not parse ${label} input-sources."
        fi
    fi

    local nl_enabled nl_temp
    nl_enabled="$(gsettings get org.gnome.settings-daemon.plugins.color night-light-enabled 2>/dev/null || true)"
    [[ -n "${nl_enabled}" ]] && night_light="${nl_enabled}"
    nl_temp="$(gsettings get org.gnome.settings-daemon.plugins.color night-light-temperature 2>/dev/null || true)"
    nl_temp="${nl_temp#uint32 }"
    [[ -n "${nl_temp}" ]] && night_light_temp="${nl_temp}"

    local lock_enabled delay_raw
    lock_enabled="$(gsettings get org.gnome.desktop.screensaver lock-enabled 2>/dev/null || true)"
    [[ -n "${lock_enabled}" ]] && idle_lock="${lock_enabled}"
    delay_raw="$(gsettings get org.gnome.desktop.session idle-delay 2>/dev/null || true)"
    delay_raw="${delay_raw#uint32 }"
    [[ -n "${delay_raw}" ]] && idle_delay="${delay_raw}"

    local repeat_delay repeat_interval
    repeat_delay="$(gsettings get org.gnome.desktop.peripherals.keyboard delay 2>/dev/null || true)"
    repeat_delay="${repeat_delay#uint32 }"
    [[ -n "${repeat_delay}" ]] && key_repeat_delay="${repeat_delay}"
    repeat_interval="$(gsettings get org.gnome.desktop.peripherals.keyboard repeat-interval 2>/dev/null || true)"
    repeat_interval="${repeat_interval#uint32 }"
    [[ -n "${repeat_interval}" ]] && key_repeat_interval="${repeat_interval}"
}

xdg="${XDG_CURRENT_DESKTOP:-}"

# Budgie is checked before plain GNOME because Budgie sessions advertise
# XDG_CURRENT_DESKTOP=Budgie:GNOME (it shares the GNOME/gsettings stack), so
# a plain *GNOME* match would misidentify it as Silverblue.
if [[ "${xdg}" == *Budgie* ]]; then
    source_desktop="budgie"
    capture_gnome_interface "Budgie"
    capture_gnome_session_daemon_settings "Budgie"
    warn "Budgie has no confirmed wallpaper gsettings key; not captured (set it manually after switching)."

elif [[ "${xdg}" == *KDE* || -n "${KDE_FULL_SESSION:-}" ]]; then
    source_desktop="kinoite"

    scheme="$(kde_read_config --file kdeglobals --group General --key ColorScheme)"
    if [[ -n "${scheme}" ]]; then
        if [[ "${scheme,,}" == *dark* ]]; then
            dark_mode="true"
        else
            dark_mode="false"
        fi
    else
        warn "Could not determine KDE color scheme."
    fi
    warn "KDE has no confirmed way to read the current accent color back from disk; not captured (set it manually after switching)."

    appletsrc="${HOME}/.config/plasma-org.kde.plasma.desktop-appletsrc"
    if [[ -f "${appletsrc}" ]]; then
        image_line="$(awk '/^\[.*Wallpaper\]\[org\.kde\.image\]\[General\]/{flag=1;next} /^\[/{flag=0} flag && /^Image=/{print;exit}' "${appletsrc}" 2>/dev/null || true)"
        if [[ -n "${image_line}" ]]; then
            wallpaper_uri="${image_line#Image=}"
            wallpaper_path="${wallpaper_uri#file://}"
        else
            warn "Could not find a wallpaper Image= entry in ${appletsrc}."
        fi
    else
        warn "Plasma appletsrc config not found at ${appletsrc}."
    fi

    layout_list="$(kde_read_config --file kxkbrc --group Layout --key LayoutList)"
    [[ -n "${layout_list}" ]] && input_layouts="${layout_list}"

    nc_active="$(kde_read_config --file kwinrc --group NightColor --key Active)"
    [[ -n "${nc_active}" ]] && night_light="${nc_active}"
    nc_temp="$(kde_read_config --file kwinrc --group NightColor --key NightTemperature)"
    [[ -n "${nc_temp}" ]] && night_light_temp="${nc_temp}"

    lock_autolock="$(kde_read_config --file kscreenlockerrc --group Daemon --key Autolock)"
    [[ -n "${lock_autolock}" ]] && idle_lock="${lock_autolock}"
    lock_timeout_min="$(kde_read_config --file kscreenlockerrc --group Daemon --key Timeout)"
    if [[ -n "${lock_timeout_min}" ]]; then
        idle_delay=$((lock_timeout_min * 60))
    fi

    repeat_delay_ms="$(kde_read_config --file kcminputrc --group Keyboard --key RepeatDelay)"
    [[ -n "${repeat_delay_ms}" ]] && key_repeat_delay="${repeat_delay_ms}"
    repeat_rate_cps="$(kde_read_config --file kcminputrc --group Keyboard --key RepeatRate)"
    if [[ -n "${repeat_rate_cps}" ]]; then
        # KDE's RepeatRate is characters/second; GNOME's repeat-interval is
        # milliseconds between repeats, so the two are reciprocals.
        repeat_interval_ms="$(awk -v r="${repeat_rate_cps}" 'BEGIN { if (r > 0) printf "%d", (1000 / r) + 0.5 }')"
        [[ -n "${repeat_interval_ms}" ]] && key_repeat_interval="${repeat_interval_ms}"
    fi

elif [[ "${xdg}" == *GNOME* ]]; then
    source_desktop="silverblue"
    capture_gnome_interface "GNOME"
    capture_gnome_session_daemon_settings "GNOME"

    if command -v gsettings >/dev/null 2>&1; then
        picture_uri="$(gsettings get org.gnome.desktop.background picture-uri 2>/dev/null || true)"
        if [[ -n "${picture_uri}" ]]; then
            picture_uri="${picture_uri#\'}"
            picture_uri="${picture_uri%\'}"
            wallpaper_path="${picture_uri#file://}"
        else
            warn "Could not determine GNOME wallpaper picture-uri."
        fi
    fi

elif [[ "${xdg,,}" == *sway* ]]; then
    source_desktop="sway"
    capture_gnome_interface "the GTK theme under Sway"
    warn "Sway itself has no dark-mode concept (only GTK apps read the key above), and its keyboard layout/night light/idle-lock come from the sway config file, not gsettings; only dark mode and accent color are captured here."
    warn "Sway's wallpaper is set via swaybg/the sway config file, with no reliable way to read the active value back; not captured (set it manually after switching)."

elif [[ "${xdg}" == *COSMIC* ]]; then
    source_desktop="cosmic"

    cosmic_mode_file="${HOME}/.config/cosmic/com.system76.CosmicTheme.Mode/v1/is_dark"
    if [[ -f "${cosmic_mode_file}" ]]; then
        case "$(cat "${cosmic_mode_file}" 2>/dev/null || true)" in
            true) dark_mode="true" ;;
            false) dark_mode="false" ;;
            *) warn "Unrecognized value in ${cosmic_mode_file}." ;;
        esac
    else
        warn "COSMIC theme mode file not found at ${cosmic_mode_file}."
    fi
    warn "COSMIC's wallpaper, accent color, input, night light, and idle-lock config formats are not confirmed stable enough to read; only dark mode is captured (set the rest manually after switching)."

else
    warn "Could not determine current desktop environment (XDG_CURRENT_DESKTOP=${xdg:-unset})."
fi

settings_file="${backup_dir}/settings.env"
: > "${settings_file}"
[[ -n "${source_desktop}" ]] && printf 'SOURCE_DESKTOP=%s\n' "${source_desktop}" >> "${settings_file}"
[[ -n "${dark_mode}" ]] && printf 'DARK_MODE=%s\n' "${dark_mode}" >> "${settings_file}"
[[ -n "${wallpaper_path}" ]] && printf 'WALLPAPER_PATH=%q\n' "${wallpaper_path}" >> "${settings_file}"
[[ -n "${accent_color}" ]] && printf 'ACCENT_COLOR=%s\n' "${accent_color}" >> "${settings_file}"
[[ -n "${input_layouts}" ]] && printf 'INPUT_LAYOUTS=%s\n' "${input_layouts}" >> "${settings_file}"
[[ -n "${night_light}" ]] && printf 'NIGHT_LIGHT=%s\n' "${night_light}" >> "${settings_file}"
[[ -n "${night_light_temp}" ]] && printf 'NIGHT_LIGHT_TEMP=%s\n' "${night_light_temp}" >> "${settings_file}"
[[ -n "${idle_lock}" ]] && printf 'IDLE_LOCK=%s\n' "${idle_lock}" >> "${settings_file}"
[[ -n "${idle_delay}" ]] && printf 'IDLE_DELAY_SECONDS=%s\n' "${idle_delay}" >> "${settings_file}"
[[ -n "${key_repeat_delay}" ]] && printf 'KEY_REPEAT_DELAY_MS=%s\n' "${key_repeat_delay}" >> "${settings_file}"
[[ -n "${key_repeat_interval}" ]] && printf 'KEY_REPEAT_INTERVAL_MS=%s\n' "${key_repeat_interval}" >> "${settings_file}"

log "Backup written to ${backup_dir}"
printf '%s\n' "${backup_dir}"
