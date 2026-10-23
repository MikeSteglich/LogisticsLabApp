# Distribution der Desktop-App

`dist/buildDist.py` baut die Desktop-App von LogisticsLabApp für das System, auf dem das Skript läuft (macOS, Windows, Linux). Der lokale Rechenkern `logisticsLabStdio` von pyLogisticsLab wird in die App gelegt. Er kommt ohne Python aus, bringt CMPL und HiGHS mit, und die App startet ihn als Kindprozess. So läuft die App ohne weitere Installation und ohne Server.

## Ergebnis

| System  | in `dist/out/`                                                  | Rechenkern in der App                                      |
|---------|-----------------------------------------------------------------|------------------------------------------------------------|
| macOS   | `LogisticsLabApp-<version>-macos-<arch>.zip` (und `.dmg`)       | `LogisticsLab.app/Contents/Resources/logisticsLabStdio/`   |
| Windows | `LogisticsLabApp-<version>-windows-<arch>.zip`                  | `LogisticsLab/logisticsLabStdio/` neben `LogisticsLab.exe` |
| Linux   | `LogisticsLabApp-<version>-linux-<arch>.tar.gz`                 | `LogisticsLab/logisticsLabStdio/` neben `LogisticsLab`     |

Die App findet den Rechenkern dort selbst (`lib/backend/backend_local_io.dart`). Unter *Einstellungen → Rechnen* lässt sich ein anderes Programm oder ein Server eintragen. Konfiguration (`confs/`) und Logs findet der Rechenkern wie in seiner eigenen Distribution. Die Logs liegen im Verzeichnis des Benutzers, unter macOS in `~/Library/Logs/LogisticsLab`.

## Ablauf

1. **Rechenkern bereitstellen:** Standard ist die fertige Distribution aus `pyLogisticsLab/dist/build/<os>-<arch>/logisticsLabStdio`. Mit `--build-stdio` wird sie vorher mit `pyLogisticsLab/dist/buildStdio.py` (Nuitka) neu gebaut, mit `--stdio DIR` kommt sie von woanders.
2. **App bauen:** `flutter build <os> --release`, die Version kommt aus `pubspec.yaml`.
3. **Zusammenstellen:** App kopieren, Rechenkern hineinlegen.
4. **Signieren (macOS):** Der Rechenkern, die Frameworks und die App werden von innen nach außen signiert. Ohne `--sign` geschieht das ad hoc, denn das Hineinlegen macht die Signatur von `flutter build` ungültig. Die App startet dann auf dem eigenen Rechner. Für andere Rechner braucht es `--sign` mit einer Developer ID und `--notarize`.
5. **Testen:**
   - Der Rechenkern in der App löst über JSON-RPC (`solveScenario`) das TPP des Beispiels mit Luftlinie, also ohne Netz, ohne Python und ohne conda.
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
| `--no-test`, `--no-archive` | ohne Tests bzw. ohne Archiv |

## Hinweise

- Gebaut wird immer für das eigene System. Windows und Linux brauchen einen Rechner (oder eine CI) mit diesem System, mit Flutter und den Werkzeugen für `buildStdio.py`.
- macOS: Die App läuft ohne Sandbox (`macos/Runner/Release.entitlements`), weil sie den Rechenkern startet. Der Rechenkern wird mit `dist/resources/stdio.entitlements` signiert (`disable-library-validation` für die Erweiterungsmodule).
- Windows ist nicht getestet. Der Rechenkern ist ein Konsolenprogramm (`--windows-console-mode=force` in `buildStdio.py`). Startet ihn die App, kann ein Konsolenfenster aufgehen. Falls ja, muss `buildStdio.py` ihn ohne eigene Konsole bauen.
