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
    mkdir -p "${dir}"
    printf '%s\n' "${dir}"
}

latest_backup_dir() {
    local dir=""
    if [[ -d "${BACKUP_ROOT}" ]]; then
        dir="$(find "${BACKUP_ROOT}" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' 2>/dev/null \
            | sort -rn | head -n1 | cut -d' ' -f2-)"
    fi
    if [[ -z "${dir}" ]]; then
        err "No backups found under ${BACKUP_ROOT}."
        return 1
    fi
    printf '%s\n' "${dir}"
}

# Fedora Atomic Desktop image catalog: desktop name -> registry/path/image-name
# (no tag). Silverblue and Kinoite are official Fedora images, verified and
# pulled through the "fedora" ostree remote pre-configured on every Atomic
# Desktop install. Budgie/Sway/Cosmic Atomic are community-maintained images
# published under a separate quay.io organization with no equivalent signed
# remote configured out of the box, so they are always pulled unverified. See
# DESKTOP_OFFICIAL below and README.md.
declare -gA DESKTOP_IMAGE=(
    [silverblue]="quay.io/fedora/fedora-silverblue"
    [kinoite]="quay.io/fedora/fedora-kinoite"
    [budgie]="quay.io/fedora-ostree-desktops/budgie-atomic"
    [sway]="quay.io/fedora-ostree-desktops/sway-atomic"
    [cosmic]="quay.io/fedora-ostree-desktops/cosmic-atomic"
)

declare -gA DESKTOP_OFFICIAL=(
    [silverblue]=1
    [kinoite]=1
    [budgie]=0
    [sway]=0
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
    for name in "${!DESKTOP_IMAGE[@]}"; do
        path="${DESKTOP_IMAGE[$name]}"
        if [[ "${ref}" == *"${path}"* ]]; then
            printf '%s\n' "${name}"
            return 0
        fi
    done
    err "Image reference does not match any known Fedora Atomic Desktop image: ${ref}"
    return 1
}

# Returns the ":<tag>" or "@sha256:<digest>" suffix that follows the matched
# registry path in ref, so compute_target_image_ref can carry the same
# Fedora release/pin across to the target image.
_image_ref_suffix() {
    local ref="$1" name path
    for name in "${!DESKTOP_IMAGE[@]}"; do
        path="${DESKTOP_IMAGE[$name]}"
        if [[ "${ref}" == *"${path}"* ]]; then
            printf '%s\n' "${ref#*"${path}"}"
            return 0
        fi
    done
    err "Image reference does not match any known Fedora Atomic Desktop image: ${ref}"
    return 1
}

# Builds the image reference to rebase to: same tag/digest as current_ref,
# but the target desktop's own image path, using the canonical transport for
# its trust level (ostree-remote-registry:fedora: for the officially signed
# images, ostree-unverified-registry: for the community-maintained ones).
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

    local suffix
    suffix="$(_image_ref_suffix "${current_ref}")" || return 1
    if [[ -z "${suffix}" || ( "${suffix:0:1}" != ":" && "${suffix:0:1}" != "@" ) ]]; then
        err "Unrecognized image reference (no tag or digest): ${current_ref}"
        return 1
    fi

    if [[ "${DESKTOP_OFFICIAL[$target]}" == "1" ]]; then
        printf 'ostree-remote-registry:fedora:%s%s\n' "${DESKTOP_IMAGE[$target]}" "${suffix}"
    else
        printf 'ostree-unverified-registry:%s%s\n' "${DESKTOP_IMAGE[$target]}" "${suffix}"
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
