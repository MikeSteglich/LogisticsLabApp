# LogisticsLab Studio

LogisticsLab Studio (repository LogisticsLabApp) is the user interface of [pyLogisticsLab](https://github.com/MikeSteglich/pyLogisticsLab): one app for all of its logistics optimisation problems, on the desktop (macOS, Windows, Linux), in the web browser and on tablets. It is written in Flutter. A project of the Technical University of Applied Sciences Wildau. It succeeds LogisticsLab 5 (version 5.4.3) as a new development, starting with version 1.0.0; the name *Studio* tells them apart, and the X files of LogisticsLab 5 can be imported.

**Status: first prototype.** It works with the transportation problem (TPP). The other problem types appear in the problem chooser but are not implemented yet.

## Features

- **Scenario files** (`.llab`) are opened, edited and saved. The app works directly on the JSON of the file, so fields it does not know yet are kept. The formats are described in `pyLogisticsLab/docs/dateiformate.md`.
- **Map** (OpenStreetMap) with the nodes and the solution. Edges follow the roads when the scenario uses the road network (`matrixSource: osm`) and are drawn as straight lines when it uses straight-line distances (`beeline`).
- **Data area** with the tabs:
  - **Nodes:** list for display only, editing in the mask below. Positions can be set by clicking into the map.
  - **Network:** the network of the problem and its edges.
  - **Parameters:** the parameters of the problem and the matrix settings of the scenario.
  - **Solution:** key figures, connections, and saving as a solution file (`.llsol`).
- **Divider** between the map and the data area: drag it to resize, double click to reset. Side by side on wide windows, one above the other on narrow ones (tablet in portrait).
- **Problem chooser** in the header: the problems of the file and new problems by group.
- **Languages:** German and English, switchable in the header. Numbers and dates follow the language.
- **Computing** locally or on a server:
  - **Local** (desktop): the core of LogisticsLab as child process, JSON-RPC over stdio (`logisticsLabStdio` from the pyLogisticsLab distribution, or `python -m logisticsLabCore.stdio`).
  - **Server:** a LogisticsLab REST server with an API key. In the browser the app always uses a server, which must allow the app's origin (`corsOrigins` in `logisticsLabServer.yml`).

Both use the scenario interface of pyLogisticsLab (stdio method `solveScenario`, REST endpoint `/v1/scenario`). The core translates the problem of the scenario, computes the matrix and returns the solution document.

## Design

- **ModuleSpec** (`lib/modules/`): a problem type is described once, with the node fields per role, the parameters with defaults, checks and conditions, the edge fields and the result columns. The masks and tables are built from it, so a new problem type needs no new screen. So far only `tpp.dart` exists.
- **Texts** (`assets/i18n/de.json`, `en.json`): a ModuleSpec contains only message keys such as `field.supply` or `module.tpp`. Missing texts fall back to English.
- **Backends** (`lib/backend/`): `backend_local_io.dart` (desktop) and `backend_remote.dart` (desktop and web) behind one interface. A conditional import keeps the local backend out of the web build.

The visual design follows the design canvas of the project: flat and plain, touch targets of at least 44 px.

## Running

```sh
flutter pub get
flutter run -d macos          # or windows, linux, chrome
```

Local computing needs the program of the core. Set it under *Settings → Computing*, or start the app with environment variables, e.g. with the sources of pyLogisticsLab:

```sh
LOGLAB_STDIO=python LOGLAB_STDIO_ARGS="-m logisticsLabCore.stdio" LOGLAB_STDIO_DIR=../pyLogisticsLab flutter run -d macos
```

*Open example* (menu `…` in the header) loads a scenario with problems around Berlin.

## Distribution

`dist/buildDist.py` builds the desktop app for the own system with the local core `logisticsLabStdio` inside (no Python, with CMPL and HiGHS): `LogisticsLab Studio.app` (macOS, signed ad hoc or with a Developer ID, `.dmg`, notarisation), a folder `LogisticsLabStudio/` on Windows and Linux. The app finds the core there by itself. See [dist/README.md](dist/README.md).

```sh
python3 dist/buildDist.py --build-stdio --stdio-python /opt/anaconda3/envs/nuitka/bin/python --dmg
```

## Tests

`test/screenshot_test.dart` opens the example, solves the TPP with the local core and writes pictures of the app (without map tiles):

```sh
LOGLAB_STDIO=python LOGLAB_STDIO_ARGS="-m logisticsLabCore.stdio" LOGLAB_STDIO_DIR=../pyLogisticsLab \
LOGLAB_SHOTS=/tmp/shots flutter test test/screenshot_test.dart
```

## Notes

- The map uses the public OpenStreetMap tile server, which is fine for a prototype. A release needs its own tile server or a provider, following the [OSM Tile Usage Policy](https://operations.osmfoundation.org/policies/tiles).
- On macOS the app runs without sandbox, because it starts the local core as child process.
- Not done yet: the other problem types, editing edges, geocoding of addresses.
