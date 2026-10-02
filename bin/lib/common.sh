#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail
IFS=$'\n\t'

log() {
    printf '[atomic-rebase] %s\n' "$*" >&2
}

warn() {
    printf '[atomic-rebase] warning: %s\n' "$*" >&2
}

err() {
    printf '[atomic-rebase] error: %s\n' "$*" >&2
}

require_cmd() {
    local cmd="$1"
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        err "Required command '${cmd}' not found on PATH."
        exit 1
    fi
}

require_not_root() {
    if [[ "${EUID}" -eq 0 ]]; then
        err "This script must be run as your normal user, not root. It elevates with sudo internally only for the rpm-ostree rebase step."
        exit 1
    fi
}

confirm() {
    local prompt="${1:-Are you sure?}"
    if [[ "${ASSUME_YES:-0}" == "1" ]]; then
        return 0
    fi
    local reply=""
    read -r -p "${prompt} [y/N] " reply || true
    case "${reply}" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

BACKUP_ROOT="${HOME}/.local/share/atomic-rebase/backups"

new_backup_dir() {
    local dir
    dir="${BACKUP_ROOT}/$(date +%Y%m%d-%H%M%S)"
    (umask 077 && mkdir -p "${BACKUP_ROOT}" "${dir}")
    # mkdir -p leaves a pre-existing directory's mode alone, so tighten it
    # explicitly in case an older version of this tool created it as 755.
    chmod 700 "${BACKUP_ROOT}" "${dir}"
    printf '%s\n' "${dir}"
}

# Backup directories are named YYYYmmdd-HHMMSS, so a plain name sort is
# chronological. Sorting by mtime instead would pick whichever directory was
# touched last (e.g. when MANUAL-STEPS.txt is written during a restore), not
# the newest backup.
latest_backup_dir() {
    local name="" dir=""
    if [[ -d "${BACKUP_ROOT}" ]]; then
        name="$(find "${BACKUP_ROOT}" -mindepth 1 -maxdepth 1 -type d \
            -regextype posix-extended -regex '.*/[0-9]{8}-[0-9]{6}' -printf '%f\n' 2>/dev/null \
            | sort | tail -n1)"
    fi
    if [[ -z "${name}" ]]; then
        err "No backups found under ${BACKUP_ROOT}."
        return 1
    fi
    dir="${BACKUP_ROOT}/${name}"
    printf '%s\n' "${dir}"
}

readonly SETTINGS_FORMAT_HEADER="# atomic-rebase settings format 2"
readonly SETTINGS_KEYS=(
    SOURCE_DESKTOP DARK_MODE WALLPAPER_PATH AVATAR_PATH ACCENT_COLOR
    INPUT_LAYOUTS NIGHT_LIGHT NIGHT_LIGHT_TEMP IDLE_LOCK IDLE_DELAY_SECONDS
    KEY_REPEAT_DELAY_MS KEY_REPEAT_INTERVAL_MS TERMINAL_CMD
)

# Decodes a value written by older versions of backup-config.sh, which used
# printf %q for WALLPAPER_PATH/AVATAR_PATH. Only the backslash-escaped form
# (what %q emits for spaces and shell metacharacters) is understood; the
# $'...' form %q uses for control characters is refused rather than evaluated.
decode_legacy_quoted_value() {
    local raw="$1" out="" i ch
    if [[ "${raw}" == \$\'* ]]; then
        return 1
    fi
    for ((i = 0; i < ${#raw}; i++)); do
        ch="${raw:i:1}"
        if [[ "${ch}" == "\\" ]]; then
            i=$((i + 1))
            ch="${raw:i:1}"
        fi
        out+="${ch}"
    done
    printf '%s' "${out}"
}

# Returns 0 if the value is acceptable for the given settings key. Values end
# up as arguments to gsettings/kwriteconfig6/plasma-apply-*, and INPUT_LAYOUTS
# is also interpolated into a GVariant string and into the generated Sway
# drop-in (as is TERMINAL_CMD), so each key is held to the narrowest shape it
# can legitimately have.
settings_value_is_valid() {
    local key="$1" value="$2"
    case "${key}" in
        SOURCE_DESKTOP) [[ "${value}" =~ ^[a-z]+$ ]] ;;
        DARK_MODE|NIGHT_LIGHT|IDLE_LOCK) [[ "${value}" == "true" || "${value}" == "false" ]] ;;
        ACCENT_COLOR) [[ "${value}" =~ ^[a-z]+$ ]] ;;
        INPUT_LAYOUTS) [[ "${value}" =~ ^[A-Za-z0-9_-]+(,[A-Za-z0-9_-]+)*$ ]] ;;
        NIGHT_LIGHT_TEMP|IDLE_DELAY_SECONDS|KEY_REPEAT_DELAY_MS|KEY_REPEAT_INTERVAL_MS)
            [[ "${value}" =~ ^[0-9]+$ ]] ;;
        WALLPAPER_PATH|AVATAR_PATH) [[ -n "${value}" && "${value}" != -* ]] ;;
        TERMINAL_CMD) [[ "${value}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] ;;
        *) return 1 ;;
    esac
}

# Returns 0 for launchers/shells that commonly prefix a terminal command line
# (e.g. "env FOO=1 konsole"). Taking only the first word of such a line would
# yield the launcher, not the terminal, so it must never be used as one.
is_terminal_launcher_name() {
    case "$1" in
        env|sh|bash|dash|zsh|fish|sudo|flatpak) return 0 ;;
        *) return 1 ;;
    esac
}

# Reduces a terminal command line (a gsettings string with its quotes already
# removed, or KDE's TerminalApplication) to the bare binary name of its first
# word, e.g. "/usr/bin/konsole --foo" -> "konsole". Arguments are dropped on
# purpose: only the binary can be safely re-mapped to another desktop. Prints
# nothing and returns 1 if no valid name results.
terminal_command_name() {
    local raw="$1" first
    raw="${raw#"${raw%%[![:space:]]*}"}"
    first="${raw%%[[:space:]]*}"
    first="${first#[\"\']}"
    first="${first%[\"\']}"
    first="${first##*/}"
    settings_value_is_valid TERMINAL_CMD "${first}" || return 1
    ! is_terminal_launcher_name "${first}" || return 1
    printf '%s\n' "${first}"
}

# Reads a settings.env file into the global variables named by
# SETTINGS_KEYS without executing anything from it. Each line is split at the
# first "=", the key must be on the whitelist, and the value is taken
# literally. Unknown keys and values that fail validation are skipped with a
# warning. Files without SETTINGS_FORMAT_HEADER come from older versions that
# wrote WALLPAPER_PATH/AVATAR_PATH shell-quoted, so those two are decoded.
load_settings_file() {
    local file="$1" line key value known recognized legacy=1 first=1

    while IFS= read -r line || [[ -n "${line}" ]]; do
        if ((first)); then
            first=0
            if [[ "${line}" == "${SETTINGS_FORMAT_HEADER}" ]]; then
                legacy=0
                continue
            fi
        fi
        [[ -z "${line}" || "${line}" == \#* ]] && continue
        if [[ "${line}" != *=* ]]; then
            warn "Ignoring malformed line in ${file}."
            continue
        fi
        key="${line%%=*}"
        value="${line#*=}"

        recognized=0
        for known in "${SETTINGS_KEYS[@]}"; do
            if [[ "${key}" == "${known}" ]]; then
                recognized=1
                break
            fi
        done
        if ((!recognized)); then
            warn "Ignoring unknown key in ${file}: ${key}"
            continue
        fi

        if ((legacy)) && [[ "${key}" == WALLPAPER_PATH || "${key}" == AVATAR_PATH ]]; then
            if ! value="$(decode_legacy_quoted_value "${value}")"; then
                warn "Ignoring ${key} in ${file}: unsupported legacy quoting."
                continue
            fi
        fi

        if ! settings_value_is_valid "${key}" "${value}"; then
            warn "Ignoring ${key} in ${file}: value is not valid for this setting."
            continue
        fi
        printf -v "${key}" '%s' "${value}"
    done < "${file}"
}

# Fedora Atomic Desktop image catalog: desktop name -> registry/path/image-name
# (no tag). Silverblue and Kinoite are official Fedora images, verified and
# pulled through the "fedora" ostree remote pre-configured on every Atomic
# Desktop install, and so is Sway (fedora-sway-atomic, ":latest" = stable).
# Budgie/Cosmic Atomic are community-maintained images published under a
# separate quay.io organization with no equivalent signed remote configured
# out of the box, so they are always pulled unverified. See
# DESKTOP_OFFICIAL below and README.md.
declare -gA DESKTOP_IMAGE=(
    [silverblue]="quay.io/fedora/fedora-silverblue"
    [kinoite]="quay.io/fedora/fedora-kinoite"
    [budgie]="quay.io/fedora-ostree-desktops/budgie-atomic"
    [sway]="quay.io/fedora/fedora-sway-atomic"
    [cosmic]="quay.io/fedora-ostree-desktops/cosmic-atomic"
)

declare -gA DESKTOP_OFFICIAL=(
    [silverblue]=1
    [kinoite]=1
    [budgie]=0
    [sway]=1
    [cosmic]=0
)

known_desktops() {
    printf '%s\n' "${!DESKTOP_IMAGE[@]}" | sort
}

is_known_desktop() {
    [[ -n "${DESKTOP_IMAGE[$1]+set}" ]]
}

# rpm-ostree's JSON schema for the container image reference has shifted
# across releases, so fall back to parsing the plain-text status output
# (the line prefixed with the booted marker) if the jq lookup comes up empty
# or jq itself isn't installed.
get_current_image_ref() {
    local ref=""
    if command -v rpm-ostree >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
        ref="$(rpm-ostree status --json 2>/dev/null \
            | jq -r '.deployments[] | select(.booted==true) | ."container-image-reference" // empty' 2>/dev/null || true)"
    fi
    if [[ -z "${ref}" ]] && command -v rpm-ostree >/dev/null 2>&1; then
        ref="$(rpm-ostree status 2>/dev/null | awk '/^● / {print $2; exit}' || true)"
    fi
    if [[ -z "${ref}" ]]; then
        err "Unable to determine the currently booted container image reference from rpm-ostree status."
        return 1
    fi
    printf '%s\n' "${ref}"
}

# Identifies which known Fedora Atomic Desktop image a full image reference
# belongs to, by checking whether the reference contains one of the registry
# paths in DESKTOP_IMAGE. This deliberately avoids parsing the transport
# prefix (ostree-remote-registry:fedora:, ostree-unverified-registry:,
# docker://, oci://, @sha256: digest pins, ...) since rpm-ostree accepts many
# equivalent forms for the same image and the registry path substring is the
# part that reliably identifies which desktop is booted.
desktop_from_image_ref() {
    local ref="$1" name path
    # Sway used to be pulled from the community namespace; installs rebased
    # with an earlier version of this tool still boot that image.
    if [[ "${ref}" == *"quay.io/fedora-ostree-desktops/sway-atomic"* ]]; then
        printf 'sway\n'
        return 0
    fi
    for name in "${!DESKTOP_IMAGE[@]}"; do
        path="${DESKTOP_IMAGE[$name]}"
        if [[ "${ref}" == *"${path}"* ]]; then
            printf '%s\n' "${name}"
            return 0
        fi
    done

    # Classic (non-container) ostree refspec, e.g. "fedora:fedora/43/x86_64/kinoite"
    # — the format installs have before they've been rebased to the OCI
    # container image. Only Silverblue/Kinoite ship this way via the "fedora"
    # remote; Sway/Budgie/COSMIC only exist as container images.
    for name in "${!DESKTOP_IMAGE[@]}"; do
        if [[ "${DESKTOP_OFFICIAL[$name]}" == "1" && "${ref}" == fedora:fedora/*/*/"${name}" ]]; then
            printf '%s\n' "${name}"
            return 0
        fi
    done

    err "Image reference does not match any known Fedora Atomic Desktop image: ${ref}"
    return 1
}

# Budgie/COSMIC Atomic have no ":latest" tag, only major-version tags
# ("43", "44", "45", ...). quay.io publishes the next release's tag as soon as
# builds for it start, long before that release is GA, so the highest numeric
# tag in the repository is a pre-release (Beta) image, not the stable one.
# The authoritative source for "which Fedora release is stable" is Bodhi, so
# the stable release number is taken from there and quay.io is only asked
# whether that tag exists for the image.
quay_api_get() {
    curl -fsSL --connect-timeout 10 -m 30 --retry 2 "$1" 2>/dev/null
}

# Prints the newest Fedora release number Bodhi lists in state "current",
# i.e. the newest stable release. Pre-releases (Beta) and Rawhide are in other
# states and are therefore never returned. rows_per_page is set well above the
# number of current releases (Fedora, EPEL, Container, Flatpak, ...) so the
# list is never truncated to a first page.
latest_stable_fedora_release() {
    local releases_json release

    releases_json="$(curl -fsSL --connect-timeout 10 -m 20 --retry 2 \
        'https://bodhi.fedoraproject.org/releases/?state=current&rows_per_page=50' 2>/dev/null)" || {
        err "Failed to query bodhi.fedoraproject.org for the current Fedora releases."
        return 1
    }

    release="$(jq -r '[.releases[] | select(.id_prefix=="FEDORA") | .version | tonumber] | max' \
        <<<"${releases_json}" 2>/dev/null)" || release=""

    if [[ ! "${release}" =~ ^[0-9]+$ ]]; then
        err "Could not determine the current stable Fedora release from bodhi.fedoraproject.org."
        return 1
    fi
    printf '%s\n' "${release}"
}

latest_stable_tag_for_image() {
    local image_path="$1" repo_path release tag_json

    require_cmd curl
    require_cmd jq

    release="$(latest_stable_fedora_release)" || return 1

    repo_path="${image_path#quay.io/}"
    tag_json="$(quay_api_get "https://quay.io/api/v1/repository/${repo_path}/tag/?specificTag=${release}&onlyActiveTags=true")" || {
        err "Failed to query quay.io for tag ${release} of ${image_path}."
        return 1
    }

    if ! jq -e '.tags | length > 0' <<<"${tag_json}" >/dev/null 2>&1; then
        err "${image_path} has no tag '${release}' on quay.io, although Fedora ${release} is the current stable release. Refusing to fall back to another tag."
        return 1
    fi
    printf '%s\n' "${release}"
}

# Builds the image reference to rebase to: always the target desktop's own
# latest stable release, never whatever tag/digest current_ref happens to be
# on. Silverblue/Kinoite keep ":latest" pointed at the current stable release,
# so that tag is used directly. Budgie/COSMIC have no ":latest" tag —
# only numeric major-version tags, so latest_stable_tag_for_image uses the
# current stable Fedora release number (from Bodhi) as the tag. Also picks
# the canonical transport for the target's trust level
# (ostree-remote-registry:fedora: for the images signed via the pre-configured
# "fedora" ostree remote, ostree-unverified-registry: for the rest).
compute_target_image_ref() {
    local current_ref="$1" target="$2"

    if ! is_known_desktop "${target}"; then
        err "compute_target_image_ref: unknown target desktop '${target}'."
        return 1
    fi

    local current
    current="$(desktop_from_image_ref "${current_ref}")" || return 1
    if [[ "${current}" == "${target}" ]]; then
        err "Current image is already ${target}."
        return 1
    fi

    if [[ "${DESKTOP_OFFICIAL[$target]}" == "1" ]]; then
        printf 'ostree-remote-registry:fedora:%s:latest\n' "${DESKTOP_IMAGE[$target]}"
    else
        local tag
        tag="$(latest_stable_tag_for_image "${DESKTOP_IMAGE[$target]}")" || return 1
        printf 'ostree-unverified-registry:%s:%s\n' "${DESKTOP_IMAGE[$target]}" "${tag}"
    fi
}

# Determines which Fedora Atomic Desktop is currently booted, from the
# booted image reference.
current_desktop() {
    local ref=""
    ref="$(get_current_image_ref)" || return 1
    desktop_from_image_ref "${ref}"
}

# Reads a KDE config value with kreadconfig6, falling back to kreadconfig5
# on older Plasma installs. Prints nothing (not an error) if neither tool or
# the key is available, matching the best-effort read style used elsewhere.
kde_read_config() {
    if command -v kreadconfig6 >/dev/null 2>&1; then
        kreadconfig6 "$@" 2>/dev/null || true
    elif command -v kreadconfig5 >/dev/null 2>&1; then
        kreadconfig5 "$@" 2>/dev/null || true
    fi
}

# Writes a KDE config value with kwriteconfig6, falling back to kwriteconfig5
# on older Plasma installs. Returns 1 if neither tool is available.
kde_write_config() {
    if command -v kwriteconfig6 >/dev/null 2>&1; then
        kwriteconfig6 "$@"
    elif command -v kwriteconfig5 >/dev/null 2>&1; then
        kwriteconfig5 "$@"
    else
        return 1
    fi
}

# Asks a running KWin to reload kwinrc after it's been edited directly with
# kde_write_config. Best-effort: a missing qdbus binary or failed call isn't
# fatal, since the change is already on disk and will take effect on the
# next login regardless.
kwin_reconfigure() {
    if command -v qdbus6 >/dev/null 2>&1; then
        qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
    elif command -v qdbus >/dev/null 2>&1; then
        qdbus org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
    fi
}

# Reads the invoking user's login/user-switcher avatar path via
# AccountsService (org.freedesktop.Accounts on the system bus) — the one
# avatar mechanism GNOME and KDE Plasma both already read, unlike
# dconf/kdeglobals which are desktop-specific formats. Uses busctl (part of
# systemd, present on every Fedora Atomic Desktop) since there's no
# gsettings/kreadconfig equivalent for a system-bus-only property.
# Best-effort: prints nothing if busctl, the service, or an icon isn't
# available.
accountsservice_icon_file() {
    if ! command -v busctl >/dev/null 2>&1; then
        return
    fi

    local user_obj
    user_obj="$(busctl --system call org.freedesktop.Accounts /org/freedesktop/Accounts \
        org.freedesktop.Accounts FindUserByName s "$(id -un)" 2>/dev/null || true)"
    user_obj="${user_obj#o \"}"
    user_obj="${user_obj%\"}"
    [[ "${user_obj}" == /* ]] || return

    local icon
    icon="$(busctl --system get-property org.freedesktop.Accounts "${user_obj}" \
        org.freedesktop.Accounts.User IconFile 2>/dev/null || true)"
    icon="${icon#s \"}"
    icon="${icon%\"}"
    [[ "${icon}" == /* ]] || return

    printf '%s\n' "${icon}"
}
