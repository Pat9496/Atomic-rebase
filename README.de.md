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
| Sway | `sway` | `quay.io/fedora/fedora-sway-atomic` | Durch die vorkonfigurierte signierte `fedora` ostree-Remote abgedeckt |
| COSMIC | `cosmic` | `quay.io/fedora-ostree-desktops/cosmic-atomic` | Nicht durch die `fedora`-Remote abgedeckt, unverified abgerufen |

Jeder der fünf Desktops kann zu jedem anderen gewechselt werden.

## Warum es das gibt

Fedora stellt jede Atomic Desktop als ein eigenes separates Container-Image bereit, das über `rpm-ostree rebase` ausgetauscht wird. Silverblue, Kinoite und Sway Atomic (früher Sericea) werden über die signierte `fedora` ostree-Remote abgerufen, die auf jeder Atomic Desktop-Installation vorkonfiguriert ist. Budgie Atomic (früher Onyx) und COSMIC Atomic werden von ihren jeweiligen SIGs gepflegt und unter einem separaten Registry-Namespace veröffentlicht, der nicht von dieser vorkonfigurierten Remote abgedeckt wird — `rpm-ostree` ruft diese unverified ab.

> [!WARNING]
> Das Rebasing zwischen Fedora Atomic Desktop-Varianten ist kein offiziell dokumentierter/unterstützter Arbeitsablauf, und das Rebasing auf ein Budgie/COSMIC Atomic-Image bedeutet, einem unverified, von der Community gepflegten Image zu vertrauen. Einsatz auf eigenes Risiko, nur auf Systemen, die neu installiert oder zurückgerollt werden können.

## Was bei einem Rebase tatsächlich passiert

Bei einem ostree-basierten System wird nur `/usr` vollständig ersetzt und `/etc` wird bei einem Rebase dreifach zusammengeführt — `/home` und `/var` (wo `/var/lib/flatpak` lebt) bleiben unverändert. In der Praxis bedeutet das:

- Dateien, Shell-Konfiguration, SSH-Schlüssel, Flatpak-Apps, Flatpak-Pro-App-Daten und der Login-/Benutzerwechsel-Avatar (über AccountsService unter `/var/lib/AccountsService` gespeichert) überstehen einen Rebase bereits von selbst — nichts muss dafür „wiederhergestellt" werden.
- Was **nicht** automatisch übertragen wird, sind Dinge, die nur in einem Desktop-Konfigurationssystem Sinn machen (KConfig für Plasma, `dconf`/`gsettings` für GNOME/Budgie, Sway-Konfiguration mit einem erzeugten Drop-in unter `~/.config/sway/config.d/99-atomic-rebase.conf`, ein anderer Konfigurationsspeicher wiederum für COSMIC). Kein Desktop liest das Format des anderen, daher startet der neue Desktop nach einem Rebase einfach mit seinen eigenen Standardwerten für alles, das noch nie konfiguriert wurde.

Diese Skripte sichern einen Snapshot der aktuellen Einstellungen zur Referenz und wenden eine kleine, gut definierte Reihe von äquivalenten Einstellungen (dunkler/heller Modus, Hintergrundbild, Akzentfarbe, Tastaturlayouts, Nachtlicht, Bildschirmsperre, Tastenwiederholung und Standard-Terminal, sofern ein zuverlässiger Mechanismus vorhanden ist) im nativen Konfigurationssystem des neuen Desktops aktiv erneut an. In [`config-map/README.md`](config-map/README.md) wird dokumentiert, was genau migriert wird und was nicht, sowie wie zuverlässig jeder Mechanismus pro Desktop ist.

## Anforderungen

- Eine laufende Fedora Atomic Desktop-Installation (eine der fünf oben), mit `rpm-ostree` und `sudo` verfügbar (standardmäßig auf allen vorhanden). `jq` wird verwendet, falls vorhanden, für zuverlässigere Image-Referenz-Erkennung, ist aber nicht erforderlich.
- Das Rebasing zu Budgie oder COSMIC erfordert zusätzlich `curl` und `jq` (beide erforderlich, nicht nur `jq`, falls vorhanden): Da diese Images kein `:latest`-Tag haben, fragt das Skript bodhi.fedoraproject.org ab, um das aktuelle stabile Fedora-Release zu identifizieren, und bestätigt dann, dass dieses Tag auf quay.io existiert, bevor es rebaset wird.
- Die Installation muss **container-native** bereitgestellt sein (aus einem Container-Image im Stil `quay.io/fedora/...`), nicht aus der klassischen ostree-Remote `fedora:fedora/...`, die standardmäßig auf Installationsmedien enthalten ist — diese Skripte identifizieren den aktuellen/Ziel-Desktop aus der Container-Image-Referenz und können kein Rebase-Ziel aus einer einfachen ostree-Referenz berechnen. Mit `rpm-ostree status` überprüfen. Falls die ostree-Remote verwendet wird: zunächst ein Rebasing zum Container-Image des aktuellen Desktops durchführen (z. B. `sudo rpm-ostree rebase ostree-unverified-registry:quay.io/fedora/fedora-silverblue:<version>`), vor Verwendung von `Atomic-rebase.sh`.
- Als normaler Benutzer ausführen, nicht als Root. Die Skripte erhöhen nur für den `rpm-ostree rebase`-Schritt selbst mit `sudo` und für die optionale Neuschichtung bekannter sicherer Pakete von `restore-config.sh`, da die dconf/gsettings/flatpak-Inspektion in der eigenen Benutzersitzung laufen muss.

## Verwendung

```bash
./Atomic-rebase.sh --to <silverblue|kinoite|budgie|sway|cosmic> [--no-migrate] [-y|--yes] [--dry-run]
```

Dies erkennt den aktuellen Desktop aus dem gestarteten Image, berechnet das Ziel-Image (immer das neueste stabile Release des Ziel-Desktops, unabhängig davon, auf welchem Tag/Digest sich das aktuelle Image befindet) und führt durch den Rest. Nützliche Flags:

- `--no-migrate` — Rebase ohne Sicherung der Einstellungen. Danach ist nichts wiederherzustellen, außer für Sway: Dort können Einrichtungsfragen mit `bin/lib/restore-config.sh --to sway --no-migrate` beantwortet werden (Details weiter unten).
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
2. Wenn `--no-migrate` nicht gesetzt ist, wird `bin/lib/backup-config.sh` ausgeführt, um aktuelle Einstellungen unter `~/.local/share/atomic-rebase/backups/<timestamp>/` zu sichern. Backup-Verzeichnisse werden mit Modus 700 erstellt, und `settings.env` ist eine literal `KEY=value`-Datei, die `restore-config.sh` mit einer Schlüssel-Whitelist parst und niemals direkt ausführt. Wenn `--no-migrate` gesetzt ist, wird dieser Schritt übersprungen.
3. Gibt das genaue Ziel-Image aus und warnt, falls es ein von der Community gepflegtes, unverified-Image ist, fragt dann vor dem Tun irgendetwas um Bestätigung (überspringt die Aufforderung mit `-y`; nur Vorschau mit `--dry-run`).
4. Führt `rpm-ostree rebase` aus (über `sudo`), um die neue Bereitstellung vorzubereiten.
5. Teilt mit, neu zu starten. Wenn eine Sicherung erstellt wurde, teilt es mit, danach `bin/lib/restore-config.sh` auszuführen. Wenn `--no-migrate` mit Sway verwendet wurde, teilt es mit, `bin/lib/restore-config.sh --to sway --no-migrate` auszuführen, um Einrichtungsfragen zu beantworten.

Nach dem Neustart in den neuen Desktop:

```bash
bin/lib/restore-config.sh --to <silverblue|kinoite|budgie|sway|cosmic> [--from <backup-dir> | --no-migrate] [--fresh-sway-config] [-y|--yes]
```

- `--from <backup-dir>` — Wiederherstellung aus einem bestimmten Backup-Verzeichnis (standardmäßig wird das neueste verwendet). Kann nicht mit `--no-migrate` kombiniert werden.
- `--no-migrate` — nur für Sway. Interaktive Einrichtungsfragen beantworten statt ein Backup zu lesen. Kann nicht mit `--from` kombiniert werden.
- `--fresh-sway-config` — nur für Sway. Verschiebt eine vorhandene `~/.config/sway/config` beiseite (als `config.bak-<timestamp>`, nie gelöscht), sodass Sway mit Fedoras Standardkonfiguration plus dem erzeugten Drop-in startet.
- `-y`/`--yes` — überspringt Bestätigungsaufforderungen und nicht-interaktive Einrichtungsfragen.

Dies wendet die Einstellungen aus der Sicherung erneut an, die eine bekannte Entsprechung im neuen Desktop haben. Mit `--no-migrate` wird keine Sicherung gelesen; stattdessen werden (nur für Sway) einige Einrichtungsfragen gestellt, wenn in einem Terminal ohne `-y` ausgeführt:

- Tastaturlayout(s), mit dem erfassten Wert (sofern vorhanden) als Vorgabe; leere Antwort überspringt.
- Tastaturvariante(n), eine pro Layout und kommagetrennt; leere überspringt.
- Bildschirmskalierungsfaktor für alle Ausgaben (0,5–4); leere behält Sways automatische Vorgabe.
- Touchpad Tap-to-Click und natürliches (umgekehrtes) Scrollen; leere überspringt jeweils.
- GTK-Dunkelmodus (nur gefragt, wenn nicht vom Quell-Desktop erfasst); leere überspringt.

Diese Antworten werden in das erzeugte Sway Drop-in geschrieben (Details unten). Mit `-y` oder nicht-interaktivem stdin werden Fragen vollständig übersprungen.

Das Skript bietet auch an, alle ostree-geschichteten RPM-Pakete (`rpm-ostree install`) aus einer kleinen Zulassungsliste von bekannten, desktop-agnostischen CLI-Tools erneut zu schichten (alacritty, btop, chezmoi, cmatrix, distrobox, fastfetch, gh, htop, neovim, podman-compose, rpmdevtools, tmux, vim-enhanced, xclip, xdotool, xsel und alle `git`/`git-*`-Pakete), die auf dem alten Desktop geschichtet waren — aber nur, wenn eine Sicherung gelesen wurde (nicht mit `--no-migrate`). Einmal bestätigen (oder `-y`/`--yes` übergeben, um die Aufforderung zu überspringen) und es schichtet sie über `sudo` erneut, wirksam beim nächsten Neustart. Alles andere Geschichtete — einschließlich hardwarespezifischer Treiber/akmods (z. B. `xorg-x11-drv-nvidia`, `akmod-nvidia`) und des Virtualisierungs-Stacks (`libvirt`, `qemu-kvm`, `virt-install`, `swtpm`, `edk2-ovmf`), das kernelversions- oder hardwaregekoppelt ist und zu bedeutsam zum unbeaufsichtigten Neuinstallieren — wird zur manuellen Neuinstallation überlassen. Es schreibt eine `MANUAL-STEPS.txt` neben der Sicherung, die auflistet, was in diesem Durchlauf migriert wurde und was nicht (Panel/Dock-Layout, Tastaturkürzel, Standard-App-Zuordnungen, Desktop-Erweiterungen/Widgets und ähnliches Desktop-spezifisches Setup sind immer manuell — Details in [`config-map/README.md`](config-map/README.md)). Mit `--no-migrate` wird keine `MANUAL-STEPS.txt` geschrieben.

### Sway als Rebase-Ziel

Beim Rebase zu Sway erkennt das Skript proprietäre NVIDIA-Kernel-Argumente und -Treiber vom alten Desktop, die den Rebase überstehen und Sway daran hindern können, richtig zu starten. Die Kernel-Argumente `rd.driver.blacklist=nouveau` und `modprobe.blacklist=nouveau` sperren den Open-Source-Treiber, und der proprietäre Treiber kann Sways `greetd`-Greeter ohne spezielle Flags nicht ausführen, was zum Aufhängen beim Boot vor der Anmeldeseite führen kann.

Das Skript überprüft auf:
- Kernel-Argumente, die dem Muster `rd.driver.blacklist=nouveau`, `modprobe.blacklist=nouveau` und `nvidia-drm.*` entsprechen
- Geschichtete Pakete, die `akmod-nvidia*`, `kmod-nvidia*`, `xorg-x11-drv-nvidia*` und `nvidia-*` entsprechen

Wenn gefunden (sogar während `--dry-run`), warnt es und fragt, ob diese mit `rpm-ostree kargs --delete` und `rpm-ostree uninstall` vor dem Rebase entfernt werden sollen. Falls abgelehnt, warnt es, dass möglicherweise `sudo rpm-ostree rollback -r` erforderlich ist.

> [!NOTE]
> Diese Erkennung und Entfernung ist auf echter Hardware mit proprietären NVIDIA-Treibern nicht getestet. Nach dem Neustart sind die Kernel-Argumente durch Ausführung von `rpm-ostree kargs` zu überprüfen.

Nach dem Neustart in Sway sollte `restore-config.sh` wie gewöhnlich ausgeführt werden.

### Sway als Restore-Ziel

Beim Wiederherstellen zu Sway enthält das erzeugte Drop-in unter `~/.config/sway/config.d/99-atomic-rebase.conf` (Modus 600) Tastaturlayouts, Tastaturvarianten, Bildschirmskalierung, Touchpad-Einstellungen, Tastenwiederholung, Hintergrundbild, GTK-Dunkelmodus/Akzentfarbe und Terminal-Voreinstellung. Werte stammen entweder aus der Sicherung (wenn eine gelesen wurde) oder aus den interaktiven Einrichtungsfragen (wenn `--no-migrate` verwendet wird und in einem Terminal ohne `-y` ausgeführt). Die Hauptdatei `~/.config/sway/config` wird niemals erstellt oder geändert; falls vorhanden, muss sie `config.d/*.conf` einbinden, ansonsten wird `restore-config.sh` warnen und die Zeile zu `MANUAL-STEPS.txt` hinzufügen. Bestehende `99-atomic-rebase.conf`-Dateien, die nicht von diesem Tool erzeugt wurden, werden niemals überschrieben. Änderungen werden automatisch neu geladen, falls `swaymsg reload` verfügbar ist und Sway läuft; ansonsten wirken sie beim nächsten Start/Neuladen. Das Terminal wird nur angewendet, falls die Binärdatei auf dem neuen System existiert; ansonsten bleibt Fedoras Standard `foot` unverändert.

## Rollback

Falls etwas schief geht, behält `rpm-ostree` die vorherige Bereitstellung bei:

```bash
sudo rpm-ostree rollback
```

Neustart durchführen, und es geht zurück auf das vorherige Image unverändert.

## Beitragen

Fehlerberichte, Funktionsanfragen und Pull-Anfragen sind willkommen. Bitte vor Beginn die Grundregeln und den Codierungsstil unten lesen. Sicherheitsprobleme sollten privat über die Registerkarte Security → **Report a vulnerability** des Repositories gemeldet werden, nicht als öffentliche Probleme.

**Grundregeln:**
- Alle Commits, Kommentare, Dokumentation, Probleme und Pull-Anfragen in English verfassen.
- Jede Pull-Anfrage sollte eine logische Änderung enthalten. Unabhängiges Refactoring vermeiden.
- Nur die aktuell benötigten Funktionen oder Abstraktionen hinzufügen, nicht für hypothetische zukünftige Verwendung.

**Codierungsstil:**

Jedes Skript beginnt mit:

```bash
#!/usr/bin/env bash
set -euo pipefail
```

Beim Schreiben von Bash:
- Alle Variablen- und Befehlerweiterungen in Anführungszeichen: `"${var}"`, `"$(cmd)"`.
- `[[ ]]` für Tests verwenden, nicht `[ ]`.
- 4-Leerzeichen-Einrückung verwenden.
- Kommentare erklären *warum*, nicht *was* — Beispiele im vorhandenen Code.

Vor dem Commit Syntax und Lint überprüfen:

```bash
bash -n Atomic-rebase.sh bin/lib/*.sh
shellcheck Atomic-rebase.sh bin/lib/*.sh
```

Dies ist die gleiche Überprüfung, die in CI (`.github/workflows/shellcheck.yml`) läuft.

**Einen neuen Desktop hinzufügen:**

1. In `bin/lib/common.sh` in den `DESKTOP_IMAGE` und `DESKTOP_OFFICIAL` Maps registrieren, mit einer zitierbaren Quelle für die Image-Referenz in der PR-Beschreibung.
2. Einstellungs-Capture in `bin/lib/backup-config.sh` und Anwendungslogik in `bin/lib/restore-config.sh` hinzufügen. Muster finden sich in vorhandenen Desktops.
3. `config-map/README.md` aktualisieren, um zu dokumentieren, was migriert wird und was nicht. Die Zuverlässigkeit ehrlich angeben — Sway und COSMIC haben keine offizielle Settings-CLI, daher sind Best-Effort-Ansätze zu erwarten.

**Testen:**

Es gibt keine Test-Suite — diese Skripte manipulieren echten Systemzustand, der nicht simuliert werden kann. Validierung ist manuell:

- Syntax-Prüfung: `bash -n Atomic-rebase.sh bin/lib/*.sh`
- Dry-run für jeden betroffenen Desktop: `./Atomic-rebase.sh --to <desktop> --dry-run`
- `backup-config.sh` und `restore-config.sh` auf einem echten Fedora Atomic Desktop in der Ziel-Sitzung ausführen; danach eigene Einstellungen wiederherstellen.
- Den tatsächlichen `rpm-ostree rebase` nie auf einem System testen, das nicht zurückgerollt (`sudo rpm-ostree rollback`) oder neu installiert werden kann.

**Pull-Anfragen:**

Beschreiben, was geändert wurde und wie es getestet wurde. `config-map/README.md` mit der Migrations-Arbeit synchron halten — die `MANUAL-STEPS.txt`-Ausgabe muss damit übereinstimmen.

**Probleme:**

Die bereitgestellten Problemvorlagen verwenden. Sicherheitsprobleme über die Registerkarte Security → **Report a vulnerability** melden, nicht als öffentliche Probleme.

## Danksagungen

- Das [Fedora Project](https://fedoraproject.org) und die Teams hinter [Fedora Atomic Desktops](https://fedoraproject.org/atomic-desktops/), für die Images und den `rpm-ostree`-Rebase-Mechanismus, auf dem diese Skripte aufbauen.
- Das [KDE Plasma](https://kde.org/plasma-desktop/)-Projekt, für die `kreadconfig`/`plasma-apply-colorscheme`/`plasma-apply-wallpaperimage`-CLI-Tools, die zum Lesen und Anwenden von KDE-Einstellungen verwendet werden.
- Das [GNOME](https://www.gnome.org/)-Projekt, für `gsettings`/`dconf`, das zum Lesen und Anwenden von GNOME (und Budgie, das denselben Stack teilt) Einstellungen verwendet wird.
- Die [Sway](https://swaywm.org/)- und [COSMIC](https://system76.com/cosmic/)-Projekte.

## Lizenz

[MIT](LICENSE)
