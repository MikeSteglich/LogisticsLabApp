# Distribution der Desktop-App

`dist/buildDist.py` baut die Desktop-App LogisticsLab Studio (Repository LogisticsLabApp) für das System, auf dem das Skript läuft (macOS, Windows, Linux). Der lokale Rechenkern `logisticsLabStdio` von pyLogisticsLab wird in die App gelegt. Er kommt ohne Python aus, bringt CMPL und HiGHS mit, und die App startet ihn als Kindprozess. So läuft die App ohne weitere Installation und ohne Server.

## Ergebnis

| System  | in `dist/out/`                                                  | Rechenkern in der App                                      |
|---------|-----------------------------------------------------------------|------------------------------------------------------------|
| macOS   | `LogisticsLabStudio-<version>-macos-<arch>.zip` (und `.dmg`)       | `LogisticsLab Studio.app/Contents/Resources/logisticsLabStdio/`   |
| Windows | `LogisticsLabStudio-<version>-windows-<arch>.zip`                  | `LogisticsLabStudio/logisticsLabStdio/` neben `LogisticsLabStudio.exe` |
| Linux   | `LogisticsLabStudio-<version>-linux-<arch>.tar.gz`                 | `LogisticsLabStudio/logisticsLabStdio/` neben `logisticslab-studio`     |

Die App findet den Rechenkern dort selbst (`lib/backend/backend_local_io.dart`). Unter *Einstellungen → Rechnen* lässt sich ein anderes Programm oder ein Server eintragen. Konfiguration (`confs/`) und Logs findet der Rechenkern wie in seiner eigenen Distribution. Die Logs liegen im Verzeichnis des Benutzers, unter macOS in `~/Library/Logs/LogisticsLab`.

## Ablauf

1. **Rechenkern bereitstellen:** Standard ist die fertige Distribution aus `pyLogisticsLab/dist/build/<os>-<arch>/logisticsLabStdio`. Mit `--build-stdio` wird sie vorher mit `pyLogisticsLab/dist/buildStdio.py` (Nuitka) neu gebaut, mit `--stdio DIR` kommt sie von woanders.
2. **App bauen:** `flutter build <os> --release`, die Version kommt aus `pubspec.yaml`.
3. **Zusammenstellen:** App kopieren, Rechenkern hineinlegen.
4. **Signieren (macOS):** Der Rechenkern, die Frameworks und die App werden von innen nach außen signiert. Ohne `--sign` geschieht das ad hoc, denn das Hineinlegen macht die Signatur von `flutter build` ungültig. Die App startet dann auf dem eigenen Rechner. Ad hoc bleibt die Hardened Runtime aus: Deren Library Validation verlangt dieselbe Team ID für App und Frameworks, und Ad-hoc-Signaturen haben keine. Die App würde sonst beim Start abstürzen. Für andere Rechner braucht es `--sign` mit einer Developer ID und `--notarize`.
5. **Testen:**
   - Der Rechenkern in der App löst über JSON-RPC (`solveScenario`) das TPP des Beispiels mit Luftlinie, also ohne Netz, ohne Python und ohne conda.
   - Die fertige App wird gestartet und muss nach 8 Sekunden noch laufen. Das findet Fehler beim Laden (Signatur, Bibliotheken). Dabei geht kurz ein Fenster auf, ohne Bildschirm hilft `--no-launch-test`.
   - Mit `--app-test` löst zusätzlich die App selbst mit diesem Rechenkern. Das läuft als Flutter-Test ohne Fenster (`test/screenshot_test.dart`) und braucht Netz für die OSM-Matrix.
6. **Packen:** nach `dist/out/`.

## Aufruf

```sh
# mit der fertigen stdio-Distribution von pyLogisticsLab
python3 dist/buildDist.py

# Rechenkern neu bauen (Python des Nuitka-Envs), mit App-Test und .dmg
python3 dist/buildDist.py --build-stdio --stdio-python /opt/anaconda3/envs/nuitka/bin/python --app-test --dmg

# macOS für andere Rechner: signieren und notarisieren
python3 dist/buildDist.py --sign "Developer ID Application: ..." --notarize <keychain-profile>
```

| Option | Bedeutung |
|---|---|
| `--flutter PATH` | flutter (Standard: aus `PATH` oder `~/opt/flutter/bin/flutter`) |
| `--pylogisticslab DIR` | pyLogisticsLab-Repository (Standard: `../pyLogisticsLab`) |
| `--stdio DIR` | fertige Distribution `logisticsLabStdio` |
| `--build-stdio` | `logisticsLabStdio` vorher neu bauen |
| `--stdio-python PYTHON` | Python für `buildStdio.py`, Basis seiner Build-Umgebung |
| `--clean` | `flutter clean`, mit `--build-stdio` auch dessen Build-Umgebung |
| `--sign IDENTITY` | macOS: mit Developer ID signieren (sonst ad hoc) |
| `--dmg` | macOS: zusätzlich ein `.dmg` mit Verweis auf `/Applications` |
| `--notarize PROFILE` | macOS: `.dmg` notarisieren und Ticket anheften (braucht `--sign`) |
| `--app-test` | zusätzlich die App mit dem Rechenkern aus der App testen |
| `--no-launch-test` | die fertige App nicht starten (ohne Bildschirm, CI) |
| `--no-test`, `--no-archive` | ohne Tests bzw. ohne Archiv |

## Hinweise

- Gebaut wird immer für das eigene System. Windows und Linux brauchen einen Rechner (oder eine CI) mit diesem System, mit Flutter und den Werkzeugen für `buildStdio.py`.
- macOS: Die App läuft ohne Sandbox (`macos/Runner/Release.entitlements`), weil sie den Rechenkern startet. Der Rechenkern wird mit `dist/resources/stdio.entitlements` signiert (`disable-library-validation` für die Erweiterungsmodule).
- Windows ist nicht getestet. Der Rechenkern ist ein Konsolenprogramm (`--windows-console-mode=force` in `buildStdio.py`). Startet ihn die App, kann ein Konsolenfenster aufgehen. Falls ja, muss `buildStdio.py` ihn ohne eigene Konsole bauen.

## Windows, Linux und macOS mit GitHub Actions

`.github/workflows/desktop.yml` baut die App auf GitHub-Rechnern für Windows, Linux und macOS, jeweils auf dem eigenen System. Gestartet wird der Workflow von Hand (*Actions → Desktop builds → Run workflow*) oder durch einen Tag `v*`. Die Archive liegen danach als Artefakte am Lauf. Bei einem Tag entsteht zusätzlich ein Release mit den Archiven.

- Ausgecheckt werden die drei Repositories nebeneinander, wie `buildDist.py` sie erwartet: `LogisticsLabApp`, `pyLogisticsLab` (privat) und `Cmpl2` (öffentlich).
- pyLogisticsLab und pyCmpl sind privat. Der Workflow braucht deshalb das Secret `LOGLAB_REPOS_TOKEN`: einen *fine-grained personal access token* mit Lesezugriff (*Contents: Read-only*) auf pyLogisticsLab und pyCmpl. Er wird unter *Settings → Secrets and variables → Actions* des Repositorys LogisticsLabApp eingetragen.
- Windows: Der CMPL-Kern wird mit MSYS2/MinGW gebaut, die App mit Visual Studio. Die Werkzeuge von MSYS2 stehen nur für diesen Schritt und ganz hinten im `PATH`.
- Linux: GTK-3-Entwicklungspakete, `clang`, `cmake`, `ninja`.
- Die fertige App wird auf den Rechnern nicht gestartet (`--no-launch-test`, kein Bildschirm). Der Test des Rechenkerns in der App läuft.
- macOS: ohne weitere Secrets ad hoc signiert, mit `.dmg`. Mit diesen Secrets wird mit der Developer ID signiert und das `.dmg` notarisiert (Ticket angeheftet):
  - `MACOS_CERTIFICATE`: Zertifikat „Developer ID Application“ mit privatem Schlüssel als `.p12`, base64 (`base64 -i zert.p12 | pbcopy`)
  - `MACOS_CERTIFICATE_PASSWORD`: Passwort des `.p12`
  - `MACOS_SIGN_IDENTITY`: z. B. `Developer ID Application: Mike Steglich (QPNW56NP5J)`
  - `NOTARY_KEY`: App Store Connect API Key (`AuthKey_….p8`), base64
  - `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`: Key ID und Issuer ID des API Keys

  Der Workflow legt das Zertifikat in einen temporären Schlüsselbund und den API Key als Profil `loglab-notary` für `notarytool` ab, beides wird am Ende entfernt.
