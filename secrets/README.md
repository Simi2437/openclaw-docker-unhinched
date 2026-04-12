# Secrets Folder

Dieses Verzeichnis dient zur sicheren Ablage von geheimen Dateien und Zugangsdaten ("Secrets"), die für den Betrieb oder die Automatisierung des Projekts benötigt werden.

## Verwendung

1. **Ablage von Secrets:**
   - Lege geheime Dateien (z.B. API-Keys, Zugangsdaten, verschlüsselte Container) in dieses Verzeichnis.
   - **WICHTIG:** Füge den `secrets/`-Ordner zur `.gitignore` hinzu, damit keine sensiblen Daten ins Repository gelangen!

2. **Beispiel-Workflow: Google Drive + KeePass**
   - Lege eine verschlüsselte KeePass-Datenbankdatei (`vault.kdbx`) in den `secrets/`-Ordner.
   - Lege ein Skript oder eine Anleitung bei, wie die Datei automatisiert von Google Drive heruntergeladen werden kann (z.B. per `gdrive` CLI oder API).
   - Optional: Lege ein Skript bei, das die KeePass-Datei entschlüsselt und die enthaltenen Secrets für den Workflow bereitstellt.

## Beispielstruktur

```
secrets/
  README.md         # Diese Anleitung
```

## Beispiel: gdrive

```bash

rclone config (gdrive einrichten)

rclone bisync "gdrive:/bla/pw" "$HOME/gdrive_pw_sync"

# in crontab put this:
*/2 * * * * rclone bisync "gdrive:/bla/pw"" "$HOME/gdrive_pw_sync" >> "$HOME/rclone_bisync.log" 2>&1

```

dann mounte die Files einfach einzeln in das secrets folder wie du sie brauchst.

**Hinweis:** 

---

**Sicherheitshinweis:**
- Lege keine Passwörter oder Secrets im Klartext ab!
- Nutze verschlüsselte Container (wie KeePass) und sichere Übertragungswege.
- Gib den Zugriff auf diesen Ordner nur an vertrauenswürdige Personen weiter.

