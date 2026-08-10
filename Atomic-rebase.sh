#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=SCRIPTDIR/bin/lib/common.sh
source "${SCRIPT_DIR}/bin/lib/common.sh"

require_not_root

TARGET=""
DRY_RUN=0
ASSUME_YES="${ASSUME_YES:-0}"

usage() {
    printf 'Usage: %s --to <%s> [-y|--yes] [--dry-run]\n' \
        "$(basename "${BASH_SOURCE[0]}")" "$(known_desktops | paste -sd'|')" >&2
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --to)
            [[ $# -ge 2 ]] || { err "--to requires an argument."; exit 1; }
            TARGET="$2"
            shift 2
            ;;
        -y|--yes)
            ASSUME_YES=1
            shift
            ;;
        --dry-run)
            DRY_RUN=1
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

if [[ -z "${TARGET}" ]]; then
    err "You must specify --to <desktop>."
    usage
    exit 1
fi

if ! is_known_desktop "${TARGET}"; then
    err "Unknown target desktop '${TARGET}'."
    usage
    exit 1
fi

require_cmd rpm-ostree
require_cmd sudo

current_ref="$(get_current_image_ref)"
current="$(desktop_from_image_ref "${current_ref}")"
target_ref="$(compute_target_image_ref "${current_ref}" "${TARGET}")"

log "Current desktop: ${current} (${current_ref})"
log "Target image:    ${target_ref}"
warn "Rebasing between Fedora Atomic Desktop variants is not an officially supported workflow; see README.md."

if [[ "${DESKTOP_OFFICIAL[$TARGET]}" != "1" ]]; then
    warn "${TARGET} is published under a separate registry namespace (quay.io/fedora-ostree-desktops) that isn't covered by the pre-configured signed 'fedora' ostree remote. It will be pulled unverified."
fi

if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "Dry run: would back up current settings, then run: sudo rpm-ostree rebase ${target_ref}"
    exit 0
fi

if ! confirm "Proceed with rebasing to ${target_ref}?"; then
    log "Aborted by user."
    exit 1
fi

backup_dir="$("${SCRIPT_DIR}/bin/lib/backup-config.sh")"
log "Settings backed up to ${backup_dir}"

sudo rpm-ostree rebase "${target_ref}"

log "Rebase staged successfully."
log "Next steps:"
log "  1. Reboot into the new deployment."
log "  2. Run: ${SCRIPT_DIR}/bin/lib/restore-config.sh --to ${TARGET}"
