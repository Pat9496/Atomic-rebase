# Atomic-rebase

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Shell: Bash](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnubash&logoColor=white)](Atomic-rebase.sh)
[![ShellCheck](https://github.com/Pat9496/Atomic-rebase/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/Pat9496/Atomic-rebase/actions/workflows/shellcheck.yml)
[![Fedora](https://img.shields.io/badge/Fedora-Atomic%20Desktop-0B57A6)](https://fedoraproject.org/atomic-desktops/)

Hilfsskripte, um eine [Fedora Atomic Desktop](https://fedoraproject.org/atomic-desktops/)-Installation zwischen verschiedenen Desktop-Umgebungs-Images zu wechseln, wobei so viel wie möglich der bestehenden Benutzerkonfiguration erhalten bleibt.

[English version](README.md)

## Inhaltsverzeichnis

- [Unterstützte Desktops](#unterstützte-desktops)
- [Warum es das gibt](#warum-es-das-gibt)
- [Was bei einem Rebase tatsächlich passiert](#was-bei-einem-rebase-tatsächlich-passiert)
- [Anforderungen](#anforderungen)
- [Verwendung](#verwendung)
- [Rollback](#rollback)
- [Beitragen](#beitragen)
- [Danksagungen](#danksagungen)
- [Lizenz](#lizenz)

## Unterstützte Desktops

| Desktop | Name für `--to` | Image | Vertrauen |
|---|---|---|---|
| GNOME | `silverblue` | `quay.io/fedora/fedora-silverblue` | Durch die vorkonfigurierte signierte `fedora` ostree-Remote abgedeckt |
| KDE Plasma | `kinoite` | `quay.io/fedora/fedora-kinoite` | Durch die vorkonfigurierte signierte `fedora` ostree-Remote abgedeckt |
| Budgie | `budgie` | `quay.io/fedora-ostree-desktops/budgie-atomic` | Nicht durch die `fedora`-Remote abgedeckt, unverified abgerufen |
| Sway | `sway` | `quay.io/fedora-ostree-desktops/sway-atomic` | Nicht durch die `fedora`-Remote abgedeckt, unverified abgerufen |
| COSMIC | `cosmic` | `quay.io/fedora-ostree-desktops/cosmic-atomic` | Nicht durch die `fedora`-Remote abgedeckt, unverified abgerufen |
| Bluefin (GNOME) | `bluefin` | [`ghcr.io/ublue-os/bluefin:stable`](https://github.com/ublue-os/bluefin/blob/main/.github/workflows/build-image-stable.yml) | Nach dem ersten Einstieg mit Universal-Blue-cosign signiert |
| Aurora (KDE Plasma) | `aurora` | [`ghcr.io/ublue-os/aurora:stable`](https://github.com/ublue-os/aurora/blob/main/.github/workflows/build-image-stable.yml) | Nach dem ersten Einstieg mit Universal-Blue-cosign signiert |
| Bazzite (KDE-Gaming-Desktop) | `bazzite` | [`ghcr.io/ublue-os/bazzite:stable`](https://docs.bazzite.gg/Installing_and_Managing_Software/Updates_Rollbacks_and_Rebasing/rebase_guide/) | Nach dem ersten Einstieg mit Universal-Blue-cosign signiert |
| Bazzite GNOME (GNOME-Gaming-Desktop) | `bazzite-gnome` | [`ghcr.io/ublue-os/bazzite-gnome:stable`](https://docs.bazzite.gg/Installing_and_Managing_Software/Updates_Rollbacks_and_Rebasing/rebase_guide/) | Nach dem ersten Einstieg mit Universal-Blue-cosign signiert |

Jedes aufgeführte Ziel kann per Rebase auf jedes andere Ziel umgestellt werden. Die Unterstützung
für Universal Blue beschränkt sich auf diese stabilen Desktop-Images; DX,
Nvidia, Deck, uCore und die Auswahl von Update-Kanälen gehören nicht zum
Funktionsumfang. Desktop-Wechsel bei Universal Blue sind experimentell und
upstream nicht unterstützt.

## Warum es das gibt

Fedora stellt jede Atomic Desktop als ein eigenes separates Container-Image bereit, das über `rpm-ostree rebase` ausgetauscht wird. Silverblue und Kinoite werden über die signierte `fedora` ostree-Remote abgerufen, die auf jeder Atomic Desktop-Installation vorkonfiguriert ist. Sway Atomic (früher Sericea), Budgie Atomic (früher Onyx) und COSMIC Atomic werden von ihren jeweiligen SIGs gepflegt und unter einem separaten Registry-Namespace veröffentlicht, der nicht von dieser vorkonfigurierten Remote abgedeckt wird — `rpm-ostree` ruft diese unverified ab.

> [!WARNING]
> Cross-Image-Rebasing ist kein offiziell dokumentierter oder unterstützter
> Arbeitsablauf. Sway/Budgie/COSMIC-Images werden unverified abgerufen, und
> Desktop-Wechsel zu Universal Blue sind experimentell und upstream nicht
> unterstützt. Einsatz auf eigenes Risiko, nur auf Systemen, die neu
> installiert oder zurückgerollt werden können.

## Was bei einem Rebase tatsächlich passiert

Bei einem ostree-basierten System wird nur `/usr` vollständig ersetzt und `/etc` wird bei einem Rebase dreifach zusammengeführt — `/home` und `/var` (wo `/var/lib/flatpak` lebt) bleiben unverändert. In der Praxis bedeutet das:

- Dateien, Shell-Konfiguration, SSH-Schlüssel, Flatpak-Apps, Flatpak-Pro-App-Daten und der Login-/Benutzerwechsel-Avatar (über AccountsService unter `/var/lib/AccountsService` gespeichert) überstehen einen Rebase bereits von selbst — nichts muss dafür „wiederhergestellt" werden.
- Was **nicht** automatisch übertragen wird, sind Dinge, die nur in einem Desktop-Konfigurationssystem Sinn machen (KConfig für Plasma, `dconf`/`gsettings` für GNOME/Budgie, einfache Konfigurationsdateien für Sway, ein anderer Konfigurationsspeicher wiederum für COSMIC). Kein Desktop liest das Format des anderen, daher startet der neue Desktop nach einem Rebase einfach mit seinen eigenen Standardwerten für alles, das noch nie konfiguriert wurde.

Diese Skripte sichern einen Snapshot der aktuellen Einstellungen zur Referenz und wenden eine kleine, gut definierte Reihe von äquivalenten Einstellungen (dunkler/heller Modus und Hintergrundbild, falls ein zuverlässiger Mechanismus vorhanden ist) im nativen Konfigurationssystem des neuen Desktops aktiv erneut an. In [`config-map/README.md`](config-map/README.md) wird dokumentiert, was genau migriert wird und was nicht, sowie wie zuverlässig jeder Mechanismus pro Desktop ist.

## Anforderungen

- Eine laufende Fedora Atomic Desktop-Installation (ein beliebiger oben aufgeführter unterstützter Atomic Desktop), mit `rpm-ostree` und `sudo` verfügbar (standardmäßig auf allen vorhanden). `jq` wird verwendet, falls vorhanden, für zuverlässigere Image-Referenz-Erkennung, ist aber nicht erforderlich.
- Das Rebasing zu Budgie, Sway oder COSMIC erfordert zusätzlich `curl` und `jq` (beide erforderlich, nicht nur `jq`, falls vorhanden): Da diese Images kein `:latest`-Tag haben, fragt das Skript die quay.io-API zur Rebase-Zeit ab, um deren aktuelles neuestes stabiles Tag zu finden.
- Die klassische `fedora:fedora/...`-ostree-Referenz, die auf Installationsmedien enthalten ist, wird nur für Silverblue und Kinoite erkannt. Andere Quellen müssen bereits eine bekannte Container-Image-Referenz verwenden. Mit `rpm-ostree status` überprüfen.
- Als normaler Benutzer ausführen, nicht als Root. Die Skripte erhöhen nur für den `rpm-ostree rebase`-Schritt selbst mit `sudo` und für die optionale Neuschichtung bekannter sicherer Pakete von `restore-config.sh`, da die dconf/gsettings/flatpak-Inspektion in der eigenen Benutzersitzung laufen muss.

## Verwendung

```bash
./Atomic-rebase.sh --to <silverblue|kinoite|budgie|sway|cosmic|bluefin|aurora|bazzite|bazzite-gnome>
```

Dies erkennt den aktuellen Desktop aus dem gestarteten Image, berechnet das Ziel-Image (immer das neueste stabile Release des Ziel-Desktops, unabhängig davon, auf welchem Tag/Digest sich das aktuelle Image befindet) und führt durch den Rest. Nützliche Flags:

- `--dry-run` — gibt aus, was passieren würde, ohne etwas zu ändern.
- `-y`/`--yes` — überspringt die Bestätigungsaufforderung.

```bash
# Von einem beliebigen Atomic Desktop zu Kinoite wechseln
./Atomic-rebase.sh --to kinoite

# Von einem beliebigen Atomic Desktop zu Silverblue wechseln
./Atomic-rebase.sh --to silverblue
```

Das Skript:

1. Erkennt das aktuelle Image und den aktuellen Desktop und berechnet das Ziel als das neueste stabile Release des Ziel-Desktops.
2. Führt `bin/lib/backup-config.sh` aus, um aktuelle Einstellungen unter `~/.local/share/atomic-rebase/backups/<timestamp>/` zu sichern.
3. Gibt das genaue Ziel-Image aus und warnt, falls es ein von der Community gepflegtes, unverified-Image ist, fragt dann vor dem Tun irgendetwas um Bestätigung (überspringt die Aufforderung mit `-y`; nur Vorschau mit `--dry-run`).
4. Führt `rpm-ostree rebase` aus (über `sudo`), um die neue Bereitstellung vorzubereiten.
5. Teilt den passenden nächsten Schritt zum Neustart und zur Wiederherstellung mit.

### Universal Blue: Einstieg in zwei Schritten

Der erste Rebase zu `bluefin`, `aurora`, `bazzite` oder `bazzite-gnome`
verwendet `ostree-unverified-registry:ghcr.io/ublue-os/<image>:stable`. Starte
in dieses Deployment neu und führe anschließend denselben Befehl
`./Atomic-rebase.sh --to <target>` erneut aus. Der zweite Rebase verwendet
`ostree-image-signed:docker://ghcr.io/ublue-os/<image>:stable`. Führe
`restore-config.sh` nicht nach dem Bootstrap-Deployment aus, sondern erst nach
dem finalen signierten Deployment. Ein direkter Wechsel zwischen bereits
signierten UBlue-Images verwendet sofort den signierten Transport. Der Befehl
der zweiten Stufe bewahrt das beim Einstieg angelegte Backup für die finale
Wiederherstellung. Schließe die zweite Stufe ab, bevor du ein anderes Ziel
auswählst; zum Verwerfen des Bootstrap-Deployments verwende `rpm-ostree rollback`.

Nach dem Neustart in den neuen Desktop:

```bash
bin/lib/restore-config.sh --to <silverblue|kinoite|budgie|sway|cosmic|bluefin|aurora|bazzite|bazzite-gnome>
```

Dies wendet die in Schritt 2 erfassten Einstellungen erneut an, die eine bekannte Entsprechung im neuen Desktop haben. Es bietet auch an, alle ostree-geschichteten RPM-Pakete (`rpm-ostree install`) aus einer kleinen Zulassungsliste von bekannten, desktop-agnostischen CLI-Tools (alacritty, btop, chezmoi, cmatrix, distrobox, fastfetch, gh, htop, neovim, podman-compose, rpmdevtools, tmux, vim-enhanced, xclip, xdotool, xsel und alle `git`/`git-*`-Pakete) neu zu schichten, die auf dem alten Desktop geschichtet waren — einmal bestätigen (oder `-y`/`--yes` übergeben, um die Aufforderung zu überspringen) und es schichtet sie über `sudo` erneut, wirksam beim nächsten Neustart. Alles andere Geschichtete — einschließlich hardwarespezifischer Treiber/akmods (z. B. `xorg-x11-drv-nvidia`, `akmod-nvidia`) und des Virtualisierungs-Stacks (`libvirt`, `qemu-kvm`, `virt-install`, `swtpm`, `edk2-ovmf`), das kernelversions- oder hardwaregekoppelt ist und zu bedeutsam zum unbeaufsichtigten Neuinstallieren — wird zur manuellen Neuinstallation überlassen. Es schreibt eine `MANUAL-STEPS.txt` neben der Sicherung, die auflistet, was in diesem Durchlauf migriert wurde und was nicht (Panel/Dock-Layout, Tastaturkürzel, Standard-App-Zuordnungen, Desktop-Erweiterungen/Widgets und ähnliches Desktop-spezifisches Setup sind immer manuell — siehe [`config-map/README.md`](config-map/README.md)).

## Rollback

Falls etwas schief geht, behält `rpm-ostree` die vorherige Bereitstellung bei:

```bash
sudo rpm-ostree rollback
```

Neustart durchführen, und es geht zurück auf das vorherige Image unverändert.

## Beitragen

Fehlerberichte, Funktionsanfragen und Pull-Anfragen sind willkommen — Details zu Codierungsstil und Testverfahren finden sich in [`CONTRIBUTING.md`](CONTRIBUTING.md). Sicherheitsprobleme sollten privat gemäß [`SECURITY.md`](SECURITY.md) gemeldet werden, anstatt als öffentliche Probleme eingereicht zu werden.

## Danksagungen

- Das [Fedora Project](https://fedoraproject.org) und die Teams hinter [Fedora Atomic Desktops](https://fedoraproject.org/atomic-desktops/), für die Images und den `rpm-ostree`-Rebase-Mechanismus, auf dem diese Skripte aufbauen.
- Das [KDE Plasma](https://kde.org/plasma-desktop/)-Projekt, für die `kreadconfig`/`plasma-apply-colorscheme`/`plasma-apply-wallpaperimage`-CLI-Tools, die zum Lesen und Anwenden von KDE-Einstellungen verwendet werden.
- Das [GNOME](https://www.gnome.org/)-Projekt, für `gsettings`/`dconf`, das zum Lesen und Anwenden von GNOME (und Budgie, das denselben Stack teilt) Einstellungen verwendet wird.
- Die [Sway](https://swaywm.org/)- und [COSMIC](https://system76.com/cosmic/)-Projekte.

## Lizenz

[MIT](LICENSE)
