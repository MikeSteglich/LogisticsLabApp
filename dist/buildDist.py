#!/usr/bin/env python3
#
# Baut die Desktop-Distribution von LogisticsLab Studio (Repository LogisticsLabApp) fuer das System, auf dem das Skript laeuft
# (macOS, Windows, Linux) - mit dem lokalen Rechenkern logisticsLabStdio von pyLogisticsLab
# (ohne Python, mit CMPL und HiGHS), den die App als Kindprozess startet.
#
#   1. logisticsLabStdio bereitstellen: fertige Distribution aus pyLogisticsLab
#      (dist/build/<os>-<arch>/logisticsLabStdio) oder mit --build-stdio neu bauen
#      (pyLogisticsLab/dist/buildStdio.py, Nuitka)
#   2. die App mit flutter build <os> --release bauen
#   3. logisticsLabStdio in die App legen - dort sucht die App ihn (lib/backend/backend_local_io.dart):
#        macOS    LogisticsLab Studio.app/Contents/Resources/logisticsLabStdio/
#        Windows  LogisticsLabStudio/logisticsLabStdio/  (neben LogisticsLabStudio.exe)
#        Linux    LogisticsLabStudio/logisticsLabStdio/  (neben dem Programm logisticslab-studio)
#   4. testen: der Rechenkern in der App loest ein Szenario ueber JSON-RPC (solveScenario), die fertige App
#      startet (kurz ein Fenster), mit --app-test loest die App selbst mit diesem Rechenkern (Flutter-Test)
#   5. (macOS) signieren - ohne --sign ad hoc, damit die geaenderte App startet -, .dmg, notarisieren
#   6. packen: dist/out/LogisticsLabStudio-<version>-<os>-<arch>.zip (.dmg, .tar.gz)
#
# Ergebnis: dist/build/<os>-<arch>/LogisticsLabApp/
#             macOS:          LogisticsLab Studio.app
#             Windows, Linux: LogisticsLabStudio/ mit dem Programm, seinen Bibliotheken, data/ und logisticsLabStdio/
#
# Aufruf:  python3 dist/buildDist.py [Optionen]      (Optionen: --help)

import argparse
import json
import os
import platform
import re
import shutil
import stat
import subprocess
import sys
import tarfile
from pathlib import Path

DISTDIR = Path(__file__).resolve().parent
PROJECT = DISTDIR.parent
PROJECTS = PROJECT.parent
RESOURCES = DISTDIR / "resources"

APP_NAME = "LogisticsLab Studio"        # Name der App (macOS: LogisticsLab Studio.app, Volume des .dmg)
DIST_NAME = "LogisticsLabStudio"        # Archive und Ordner unter Windows/Linux - ohne Leerzeichen
# Programm in der App bzw. im Ordner (Windows, Linux: BINARY_NAME in CMakeLists.txt)
PROGRAM = {"macos": "LogisticsLab Studio", "windows": "LogisticsLabStudio.exe", "linux": "logisticslab-studio"}
STDIO = "logisticsLabStdio"
EXAMPLE = PROJECT / "assets/examples/brandenburg.llab"
OLD_FILE = PROJECT / "test/fixtures/Baukies-angebotsueberschuss.TPPX"     # import of old LogisticsLab files


class BuildError(Exception):
    pass


# ---------------------------------------------------------------- Hilfen

def log(msg):
    print("\n==> " + msg, flush=True)


def run(cmd, cwd=None, env=None, capture=False, input=None):
    print("    $ " + " ".join(str(c) for c in cmd), flush=True)
    try:
        res = subprocess.run([str(c) for c in cmd], cwd=cwd, env=env, text=True, input=input,
                             stdout=subprocess.PIPE if capture else None,
                             stderr=subprocess.STDOUT if capture else None)
    except FileNotFoundError:
        raise BuildError(f"Programm nicht gefunden: {cmd[0]}")
    if res.returncode != 0:
        if capture:
            print(res.stdout)
        raise BuildError(f"Fehlgeschlagen ({res.returncode}): {' '.join(str(c) for c in cmd)}")
    return res.stdout if capture else None


class Target:
    """Betriebssystem und Architektur, fuer die gebaut wird (= das eigene)."""

    def __init__(self):
        s = platform.system()
        self.os = {"Darwin": "macos", "Windows": "windows", "Linux": "linux"}.get(s)
        if not self.os:
            raise BuildError(f"Nicht unterstuetztes System: {s}")
        m = platform.machine().lower()
        self.arch = {"amd64": "x86_64", "x64": "x86_64", "aarch64": "arm64"}.get(m, m)

    is_win = property(lambda self: self.os == "windows")
    is_mac = property(lambda self: self.os == "macos")

    def __str__(self):
        return f"{self.os}-{self.arch}"


def app_version():
    m = re.search(r"^version:\s*([0-9][^+\s]*)", (PROJECT / "pubspec.yaml").read_text(), re.M)
    if not m:
        raise BuildError("pubspec.yaml: version fehlt")
    return m.group(1)


def find_flutter(arg):
    for cand in (arg, shutil.which("flutter"), str(Path.home() / "opt/flutter/bin/flutter")):
        if cand and Path(cand).exists():
            return cand
        if cand and shutil.which(cand):
            return shutil.which(cand)
    raise BuildError("flutter nicht gefunden (--flutter)")


# ---------------------------------------------------------------- Rechenkern

def stdio_dir(t, args):
    """Verzeichnis der Distribution logisticsLabStdio (bin/, confs/, README.md)."""
    pll = Path(args.pylogisticslab).resolve()
    default = pll / "dist" / "build" / str(t) / STDIO
    if args.build_stdio:
        script = pll / "dist" / "buildStdio.py"
        if not script.exists():
            raise BuildError(f"{script} nicht gefunden (--pylogisticslab)")
        log(f"{STDIO} bauen (pyLogisticsLab, Nuitka)")
        cmd = [args.stdio_python, script, "--no-archive"]
        if args.clean:
            cmd.append("--clean")
        run(cmd, cwd=pll)
        return default
    d = Path(args.stdio).resolve() if args.stdio else default
    exe = d / "bin" / (STDIO + (".exe" if t.is_win else ""))
    if not exe.exists():
        raise BuildError(f"{STDIO} nicht gefunden: {exe}\n"
                         f"    mit --build-stdio bauen oder mit --stdio DIR angeben")
    return d


def stdio_place(t, app):
    """Ort des Rechenkerns in der gebauten App."""
    return app / "Contents" / "Resources" / STDIO if t.is_mac else app / STDIO


def show_logs(files):
    """bei einem Fehler: Fehlerausgabe und das Ende der Logs des Rechenkerns - auch im Protokoll einer CI zu sehen"""
    for f in files:
        try:
            lines = Path(f).read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            continue
        if lines:
            print(f"\n    ---- {f} (letzte {min(len(lines), 60)} von {len(lines)} Zeilen)")
            for line in lines[-60:]:
                print("    " + line[:400])


def stdio_test(exe, tdir):
    """JSON-RPC wie die App: convert (Import einer alten Datei), solveScenario mit dem Beispiel (Luftlinie - ohne
    Netz), dann result - ein Rechenkern, der aelter als die App ist, faellt hier auf."""
    log("Test: Rechenkern der App wandelt eine alte Datei um (convert) und loest ein Szenario (solveScenario)")
    scen = json.loads(EXAMPLE.read_text(encoding="utf-8"))
    scen["matrix"]["matrixSource"] = "beeline"
    problem = next(p["name"] for p in scen["problems"] if p["type"] == "tpp")
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(("LOGLAB_", "CMPL", "PYTHON", "CONDA", "VIRTUAL_ENV"))}
    env["LOGLAB_LOG_DIR"] = str(tdir / "logs")
    env["PATH"] = os.pathsep.join(p for p in env.get("PATH", "").split(os.pathsep)
                                  if "conda" not in p.lower() and "python" not in p.lower())
    stderrFile = tdir / "stdio-stderr.txt"
    with open(stderrFile, "w", encoding="utf-8") as err:
        proc = subprocess.Popen([str(exe), "--logPath", str(tdir / "logs")], stdin=subprocess.PIPE,
                                stdout=subprocess.PIPE, stderr=err, text=True, encoding="utf-8",
                                bufsize=1, cwd=tdir, env=env)

    def send(id, method, params):
        proc.stdin.write(json.dumps({"jsonrpc": "2.0", "id": id, "method": method, "params": params}) + "\n")
        proc.stdin.flush()

    result = None
    job = None
    readies = 0                 # more than one: a solver process has started the interface again (spawn)
    try:
        for line in proc.stdout:
            msg = json.loads(line)
            if msg.get("method") == "ready":
                readies += 1
                if readies > 1:
                    print(f"    noch einmal 'ready' ({readies}) - ein Solver-Prozess startet die Schnittstelle neu")
                    continue
                print(f"    bereit: Version {msg['params'].get('version')}")
                raw = OLD_FILE.read_bytes()
                try:
                    content = raw.decode("utf-8")
                except UnicodeDecodeError:
                    content = raw.decode("latin-1")         # the old files are UTF-8 or Latin-1
                send(0, "convert", {"fileName": OLD_FILE.name, "content": content})
            elif msg.get("id") == 0:
                if "error" in msg:
                    raise BuildError(f"convert: {msg['error']}")
                conv = msg["result"]
                print(f"    {OLD_FILE.name} -> {conv['fileName']}: {len(conv['scenario']['nodes'])} Knoten")
                send(1, "solveScenario", {"scenario": scen, "problem": problem})
            elif msg.get("id") == 1:
                if "error" in msg:
                    raise BuildError(f"solveScenario: {msg['error']}")
                job = msg["result"]["id"]
            elif msg.get("method") == "jobStatus" and msg["params"]["id"] == job \
                    and msg["params"]["status"] in ("solution", "noSolution", "error", "cancelled"):
                send(2, "result", {"id": job})
            elif msg.get("id") == 2:
                result = msg.get("result")
                send(3, "shutdown", {})
            elif msg.get("id") == 3:
                break
    finally:
        try:
            proc.stdin.close()
            proc.wait(timeout=20)
        except Exception:
            proc.kill()
    sol = (result or {}).get("solution") or {}
    if sol.get("status") != "solution":
        show_logs([stderrFile, *sorted((tdir / "logs").rglob("*.log"))])
        raise BuildError(f"keine Loesung: {result}")
    print(f"    {problem}: {sol['status']}, Zielwert {sol['results']['objVal']}")
    print("    ok")


def launch_test(t, app, seconds=8):
    """Startet die fertige App und prueft, dass sie nach einigen Sekunden noch laeuft - findet Fehler beim Laden
    (Signatur, fehlende Bibliotheken), die die Flutter-Tests nicht sehen. Oeffnet kurz ein Fenster."""
    log("Test: die fertige App startet")
    if t.is_mac:
        exe = app / "Contents" / "MacOS" / PROGRAM[t.os]
    else:
        exe = app / PROGRAM[t.os]
    proc = subprocess.Popen([str(exe)], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    try:
        code = proc.wait(timeout=seconds)
    except subprocess.TimeoutExpired:
        proc.terminate()
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()
        print(f"    laeuft nach {seconds} s - ok")
        return
    err = (proc.stderr.read() or "").strip().splitlines()[-10:]
    raise BuildError(f"die App ist beim Start beendet worden ({code}):\n    " + "\n    ".join(err))


def app_test(flutter, exe, tdir):
    """Die App (Flutter-Test, ohne Fenster) loest mit dem Rechenkern aus der App - braucht Netz (OSM)."""
    log("Test: App mit dem Rechenkern aus der App (test/screenshot_test.dart)")
    env = dict(os.environ, LOGLAB_STDIO=str(exe), LOGLAB_SHOTS=str(tdir / "shots"))
    env.pop("LOGLAB_STDIO_ARGS", None)
    env.pop("LOGLAB_STDIO_DIR", None)
    run([flutter, "test", "test/screenshot_test.dart"], cwd=PROJECT, env=env)
    print(f"    Bilder: {tdir / 'shots'}")


# ---------------------------------------------------------------- macOS: signieren, dmg, notarisieren

def is_macho(path):
    try:
        with open(path, "rb") as f:
            magic = f.read(4)
    except OSError:
        return False
    return magic in (b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe", b"\xca\xfe\xba\xbe",
                     b"\xfe\xed\xfa\xcf", b"\xfe\xed\xfa\xce")


def codesign_file(opts, f):
    # codesign meldet gelegentlich "internal error in Code Signing subsystem" - ein zweiter Versuch klappt
    for attempt in range(3):
        try:
            return run(["codesign", *opts, f], capture=True)
        except BuildError:
            if attempt == 2:
                raise


def codesign_app(app, identity):
    """Signiert von innen nach aussen: die Binaries des Rechenkerns (Resources), die Frameworks, dann die App.

    identity "-" signiert ad hoc - noetig, weil das Hinzufuegen des Rechenkerns die Signatur von flutter build
    ungueltig macht. Ad hoc ohne Hardened Runtime: deren Library Validation verlangt dieselbe Team ID fuer die App
    und ihre Frameworks, Ad-hoc-Signaturen haben keine - dyld laedt FlutterMacOS.framework dann nicht.
    Mit einer Developer ID: Hardened Runtime und Zeitstempel (Voraussetzung fuers Notarisieren).
    """
    adhoc = identity == "-"
    log("Signieren " + ("(ad hoc - nur fuer diesen Rechner)" if adhoc else f"(Identitaet: {identity})"))
    base = ["--force", "--sign", identity] + ([] if adhoc else ["--options", "runtime", "--timestamp"])

    # Rechenkern: Python-Erweiterungen laden andere Bibliotheken (disable-library-validation)
    stdio = stdio_place(Target(), app)
    files = [f for f in sorted(stdio.rglob("*")) if f.is_file() and not f.is_symlink() and is_macho(f)]
    for f in files:
        codesign_file(base + ["--entitlements", RESOURCES / "stdio.entitlements"], f)
    print(f"    Rechenkern: {len(files)} Dateien")

    # Frameworks von Flutter und den Plugins (FlutterMacOS.framework, App.framework, ...)
    fw = sorted((app / "Contents" / "Frameworks").glob("*.framework")) + \
        sorted((app / "Contents" / "Frameworks").glob("*.dylib"))
    for f in fw:
        codesign_file(base, f)
    print(f"    Frameworks: {len(fw)}")

    codesign_file(base + ["--entitlements", PROJECT / "macos/Runner/Release.entitlements"], app)
    run(["codesign", "--verify", "--deep", "--strict", "--verbose=1", app], capture=True)
    print(f"    {app.name}: Signatur gueltig")


def notarize(path, profile):
    """Schickt path (.zip, .dmg) an den Notarisierungsdienst von Apple und wartet auf das Ergebnis."""
    log(f"Notarisieren: {path.name} (Profil {profile})")
    out = run(["xcrun", "notarytool", "submit", path, "--keychain-profile", profile, "--wait"], capture=True)
    print("    " + "\n    ".join(out.strip().splitlines()[-4:]))
    if not re.search(r"status:\s*Accepted", out):
        m = re.search(r"id:\s*([0-9a-f-]{36})", out)
        details = ""
        if m:
            details = subprocess.run(["xcrun", "notarytool", "log", m.group(1), "--keychain-profile", profile],
                                     capture_output=True, text=True).stdout
        raise BuildError(f"Notarisierung abgelehnt: {path.name}\n{out}\n{details}")


def staple(path):
    """Heftet das Ticket an (.app, .dmg) - Gatekeeper braucht dann kein Netz."""
    run(["xcrun", "stapler", "staple", path], capture=True)
    run(["xcrun", "stapler", "validate", path], capture=True)
    print(f"    Ticket angeheftet: {path.name}")


def make_dmg(app, dmg, identity, work):
    """Disk-Image (LZMA, ab macOS 10.15) mit der App und einem Verweis auf /Applications."""
    src = work / "dmg"
    if src.exists():
        shutil.rmtree(src)
    src.mkdir(parents=True)
    run(["ditto", app, src / app.name])
    (src / "Applications").symlink_to("/Applications")
    if dmg.exists():
        dmg.unlink()
    run(["hdiutil", "create", "-volname", APP_NAME, "-srcfolder", src, "-ov", "-format", "ULMO", dmg], capture=True)
    if identity and identity != "-":
        codesign_file(["--force", "--timestamp", "--sign", identity], dmg)
    shutil.rmtree(src)
    return dmg


# ---------------------------------------------------------------- packen

def pack(t, app, name, args, work):
    outdir = DISTDIR / "out"
    outdir.mkdir(exist_ok=True)
    log("Archiv packen")
    archives = []
    if t.is_mac:
        # ditto erhaelt Rechte, Symlinks der Frameworks und Signaturen
        archive = outdir / f"{name}.zip"
        if archive.exists():
            archive.unlink()
        run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", app, archive])
        archives.append(archive)
        if args.dmg:
            dmg = make_dmg(app, outdir / f"{name}.dmg", args.sign, work)
            if args.notarize:
                notarize(dmg, args.notarize)
                staple(dmg)
            archives.append(dmg)
    elif t.os == "linux":
        archive = outdir / f"{name}.tar.gz"
        with tarfile.open(archive, "w:gz") as tf:
            tf.add(app, arcname=app.name)
        archives.append(archive)
    else:
        archives.append(Path(shutil.make_archive(str(outdir / name), "zip", app.parent, app.name)))
    for a in archives:
        print(f"    {a}  ({a.stat().st_size / 1e6:.1f} MB)")
    return archives


# ---------------------------------------------------------------- main

def flutter_output(t):
    """Ergebnis von flutter build <os> --release."""
    if t.is_mac:
        return PROJECT / "build/macos/Build/Products/Release" / f"{APP_NAME}.app"
    arch = "arm64" if t.arch == "arm64" else "x64"
    if t.is_win:
        return PROJECT / "build/windows" / arch / "runner/Release"
    return PROJECT / "build/linux" / arch / "release/bundle"


def main():
    ap = argparse.ArgumentParser(
        description="Baut die Desktop-Distribution von LogisticsLabApp mit dem lokalen Rechenkern logisticsLabStdio.")
    ap.add_argument("--flutter", metavar="PATH", help="flutter (Default: aus PATH oder ~/opt/flutter/bin/flutter)")
    ap.add_argument("--pylogisticslab", default=str(PROJECTS / "pyLogisticsLab"), metavar="DIR",
                    help="pyLogisticsLab-Repository (Default: %(default)s)")
    ap.add_argument("--stdio", metavar="DIR",
                    help=f"fertige Distribution {STDIO} (Default: <pyLogisticsLab>/dist/build/<os>-<arch>/{STDIO})")
    ap.add_argument("--build-stdio", action="store_true",
                    help=f"{STDIO} vorher mit pyLogisticsLab/dist/buildStdio.py neu bauen")
    ap.add_argument("--stdio-python", default=sys.executable, metavar="PYTHON",
                    help="Python fuer buildStdio.py - Basis seiner Build-Umgebung (Default: dieses Python)")
    ap.add_argument("--clean", action="store_true", help="flutter clean, mit --build-stdio auch dessen Build-Umgebung")
    ap.add_argument("--sign", metavar="IDENTITY",
                    help="macOS: mit dieser Identitaet signieren (Developer ID Application: ...) - sonst ad hoc")
    ap.add_argument("--dmg", action="store_true", help="macOS: zusaetzlich ein .dmg")
    ap.add_argument("--notarize", metavar="PROFILE",
                    help="macOS: .dmg notarisieren und das Ticket anheften (braucht --sign, setzt --dmg)")
    ap.add_argument("--app-test", action="store_true",
                    help="zusaetzlich die App mit dem Rechenkern aus der App testen (Flutter-Test, braucht Netz)")
    ap.add_argument("--no-launch-test", action="store_true",
                    help="die fertige App nicht starten (z.B. ohne Bildschirm, in einer CI)")
    ap.add_argument("--no-test", action="store_true", help="keine Tests")
    ap.add_argument("--no-archive", action="store_true", help="kein Archiv in dist/out")
    args = ap.parse_args()
    if args.notarize and not args.sign:
        ap.error("--notarize braucht --sign")
    if args.notarize:
        args.dmg = True

    t = Target()
    if t.is_mac and not args.sign:
        args.sign = "-"
    version = app_version()
    flutter = find_flutter(args.flutter)
    base = DISTDIR / "build" / str(t)
    stage = base / DIST_NAME
    work = base / "work"
    print(f"{DIST_NAME} {version} fuer {t}")

    stdio = stdio_dir(t, args)
    print(f"    Rechenkern: {stdio}")

    log(f"App bauen (flutter build {t.os} --release)")
    if args.clean:
        run([flutter, "clean"], cwd=PROJECT)
    run([flutter, "pub", "get"], cwd=PROJECT)
    run([flutter, "build", t.os, "--release", f"--build-name={version}"], cwd=PROJECT)
    out = flutter_output(t)
    if not out.exists():
        raise BuildError(f"flutter build hat {out} nicht erzeugt")

    log(f"Zusammenstellen: {stage}")
    if stage.exists():
        shutil.rmtree(stage)
    stage.mkdir(parents=True)
    app = stage / (out.name if t.is_mac else DIST_NAME)
    if t.is_mac:
        run(["ditto", out, app])                      # erhaelt die Symlinks der Frameworks
    else:
        shutil.copytree(out, app, symlinks=True)
    target = stdio_place(t, app)
    shutil.copytree(stdio, target, symlinks=True)
    for junk in list(app.rglob(".DS_Store")):
        junk.unlink()
    exe = target / "bin" / (STDIO + (".exe" if t.is_win else ""))
    exe.chmod(exe.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    size = sum(f.stat().st_size for f in target.rglob("*") if f.is_file()) / 1e6
    print(f"    {target.relative_to(stage)}  ({size:.0f} MB)")

    if t.is_mac:
        codesign_app(app, args.sign)

    if not args.no_test:
        tdir = work / "test"
        if tdir.exists():
            shutil.rmtree(tdir)
        tdir.mkdir(parents=True)
        stdio_test(exe, tdir)
        if not args.no_launch_test:
            launch_test(t, app)
        if args.app_test:
            app_test(flutter, exe, tdir)

    if not args.no_archive:
        pack(t, app, f"{DIST_NAME}-{version}-{t}", args, work)
    size = sum(f.stat().st_size for f in app.rglob("*") if f.is_file()) / 1e6
    log(f"Fertig: {app}  ({size:.0f} MB)")


if __name__ == "__main__":
    try:
        main()
    except BuildError as e:
        print(f"\nFEHLER: {e}", file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        sys.exit(130)
