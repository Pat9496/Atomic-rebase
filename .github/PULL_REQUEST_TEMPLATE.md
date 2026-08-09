## What does this change?

<!-- A clear description of the change and why it's needed. -->

## How was this tested?

<!--
These scripts touch real system state, so please describe manual testing:
- bash -n on every changed script
- shellcheck on every changed script
- --dry-run output for the desktop pair(s) your change affects
- Actual run against a real Fedora Atomic Desktop system, if applicable —
  which desktops (source/target), and what you confirmed afterwards
-->

## Checklist

- [ ] All text (code comments, docs, commit messages) is in English.
- [ ] `shellcheck Atomic-rebase.sh bin/lib/*.sh` passes.
- [ ] If this adds/changes an image reference, a source is cited (Fedora
      Magazine, the SIG's own docs, etc.).
- [ ] If this changes what is/isn't migrated between desktops,
      `config-map/README.md` was updated to match.
