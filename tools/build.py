#!/usr/bin/env python3
"""Build a rawin-launcher release: dist/rawin-launcher.tar.gz.

The archive unpacks to rawin-launcher/ (the version is in its VERSION file),
so the same commands install any release. Its install.sh picks the variant
the TV has the makings for:
  webos4/   the Home panel: the panel inside LG's QML Home (patch + boot
            hook), files from ui/
  webos10/  the overlay: org.rawin.launcher_<version>_all.ipk (overlay app +
            root helper), LG Home stand-in, boot hook, Input Hook binding
Both use the same panel, ui/Launcher.qml, and the same setup server for the
weather, shared/. For the overlay it becomes Panel.qml:
the Luna Service elements are swapped for webos10/panel-bridge.qml (HTTP to the
helper) and fonts come from the package.

Usage: tools/build.py [--config config/launcher.json] [--out dist]
Needs only Python 3.
"""
import argparse
import io
import json
import tarfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = "org.rawin.launcher"
SERVICE = APP + ".service"
WEBOS4_FONTS = "file:///var/lib/webosbrew/rawin-launcher/current/fonts/"


def tgz(files, prefix="./"):
    """A gzip tar of (path, bytes[, mode]) in memory, directories included."""
    buf = io.BytesIO()
    now = int(time.time())
    with tarfile.open(fileobj=buf, mode="w:gz", format=tarfile.GNU_FORMAT) as tar:
        dirs = set()
        for entry in files:
            name, data = entry[0], entry[1]
            mode = entry[2] if len(entry) > 2 else 0o644
            parts = name.split("/")[:-1]
            for i in range(1, len(parts) + 1):
                d = "/".join(parts[:i])
                if d not in dirs:
                    dirs.add(d)
                    info = tarfile.TarInfo(prefix + d)
                    info.type, info.mode, info.mtime = tarfile.DIRTYPE, 0o755, now
                    tar.addfile(info)
            info = tarfile.TarInfo(prefix + name)
            info.size, info.mode, info.mtime = len(data), mode, now
            tar.addfile(info, io.BytesIO(data))
    return buf.getvalue()


def ar(members):
    """An ar archive (the IPK container) of (name, bytes)."""
    out = b"!<arch>\n"
    for name, data in members:
        header = name.ljust(16) + "0".ljust(12) + "0".ljust(6) + "0".ljust(6) + "100644".ljust(8) + str(len(data)).ljust(10) + "`\n"
        out += header.encode() + data + (b"\n" if len(data) % 2 else b"")
    return out


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise SystemExit("ui/Launcher.qml changed; cannot find exactly one: " + old.splitlines()[0][:80])
    return text.replace(old, new)


def config_js(spec, version, platform, extra=()):
    """Config.js read by Launcher.qml (a QML JavaScript library). platform is
    the variant's name for the panel's corner; webos, the TV's version, is
    filled in there by the installer."""
    inputs = [{"id": "com.webos.app.hdmi%d" % i, "title": "HDMI %d" % i, "detail": "", "present": True} for i in range(1, 5)]
    values = [("version", version), ("platform", platform), ("webos", ""), ("apps", []),
              ("favourites", spec["favourites"][:7]), ("styles", spec.get("styles", {})),
              ("inputs", inputs), ("excluded", spec.get("excluded", []) + [APP])] + list(extra)
    return (".pragma library\n" + "\n".join(
        "var %s = %s;" % (name, json.dumps(value, ensure_ascii=False)) for name, value in values) + "\n").encode()


def panel_qml():
    q = (ROOT / "ui/Launcher.qml").read_text()
    q = replace_once(q, "import WebOSServices 1.0\n", "")
    q = replace_once(q, 'source: "%sInter-Regular.ttf"' % WEBOS4_FONTS, 'source: "fonts/Inter-Regular.ttf"')
    q = replace_once(q, 'source: "%sInter-Bold.ttf"' % WEBOS4_FONTS, 'source: "fonts/Inter-Bold.ttf"')
    bridge = "".join(line for line in (ROOT / "webos10/panel-bridge.qml").read_text().splitlines(True)
                     if not line.startswith("//"))
    start = q.index("    Service {\n        id: launchService")
    end = q.index("    Timer { id: launchTimeout;")
    return q[:start] + bridge + q[end:]


def input_icon_files():
    return sorted((ROOT / "ui/input-icons").iterdir())


def shared_files():
    """The setup server (weather, the place page, its QR code), run by the
    overlay's helper and by the Home panel's boot hook alike."""
    return [ROOT / "shared" / name for name in ("setup.js", "qr.js", "guard.js", "stats.js", "setup.html")]


def webos10_ipk(spec, version):
    # webOS takes only x.y.z as a package version; a test build's suffix
    # ("0.11.0-test1") shows in the panel, from Config.js.
    package_version = version.split("-")[0]
    appinfo = json.loads((ROOT / "webos10/app/appinfo.json").read_text())
    appinfo["version"] = package_version
    app_dir = "usr/palm/applications/%s/" % APP
    svc_dir = "usr/palm/services/%s/" % SERVICE
    config = config_js(spec, version, "overlay", [("stockHome", False), ("exitTarget", True)])
    files = [
        (app_dir + "appinfo.json", json.dumps(appinfo, indent=2).encode()),
        (app_dir + "main.qml", (ROOT / "webos10/app/main.qml").read_bytes()),
        (app_dir + "Panel.qml", panel_qml().encode()),
        (app_dir + "Config.js", config),
        (app_dir + "FavouriteStore.qml", (ROOT / "ui/FavouriteStore.qml").read_bytes()),
        (app_dir + "Strings.js", (ROOT / "ui/Strings.js").read_bytes()),
        (app_dir + "Themes.js", (ROOT / "ui/Themes.js").read_bytes()),
        (app_dir + "About.js", (ROOT / "ui/About.js").read_bytes()),
        (app_dir + "icon.png", (ROOT / "ui/icon.png").read_bytes()),
    ]
    files += [(app_dir + name, (ROOT / "ui" / name).read_bytes()) for name in ("DeviceIcons.js", "DeviceIcon.qml")]
    files += [(app_dir + "input-icons/" + p.name, p.read_bytes()) for p in input_icon_files()]
    files += [(app_dir + "fonts/" + p.name, p.read_bytes()) for p in sorted((ROOT / "ui/fonts").iterdir())]
    files += [(svc_dir + p.name, p.read_bytes()) for p in sorted((ROOT / "webos10/helper").glob("*.js"))]
    # One copy of the launch-ownership module: the installer's, also the helper's.
    files.append((svc_dir + "integration.js", (ROOT / "webos10/integration.js").read_bytes()))
    files += [(svc_dir + p.name, p.read_bytes()) for p in shared_files()]
    files += [
        (svc_dir + "package.json", json.dumps({"name": SERVICE, "version": package_version, "main": "service.js"}, indent=1).encode()),
        (svc_dir + "services.json", json.dumps({"id": SERVICE, "description": "Homebar helper",
                                                "services": [{"name": SERVICE}]}, indent=1).encode()),
        ("usr/palm/packages/%s/packageinfo.json" % APP, json.dumps(
            {"id": APP, "version": package_version, "vendor": "rawin", "app": APP, "services": [SERVICE],
             "loc_name": "Homebar", "package_format_version": 2}, indent=1).encode()),
    ]
    control = ("Package: %s\nVersion: %s\nSection: misc\nPriority: optional\nArchitecture: all\n"
               "Maintainer: rawinek\nDescription: Homebar, a home screen bar for webOS 10\n"
               % (APP, package_version)).encode()
    return ar([("debian-binary", b"2.0\n"), ("control.tar.gz", tgz([("control", control)])),
               ("data.tar.gz", tgz(files))])


def release_files(spec, version):
    """(path in the archive, bytes, mode) for every file of the release."""
    exe = 0o755
    files = [
        ("install.sh", (ROOT / "install.sh").read_bytes(), exe),
        ("probe.sh", (ROOT / "probe.sh").read_bytes(), exe),
        ("uninstall.sh", (ROOT / "uninstall.sh").read_bytes(), exe),
        ("update.sh", (ROOT / "update.sh").read_bytes(), exe),
        ("diagnose.sh", (ROOT / "diagnose.sh").read_bytes(), exe),
        ("VERSION", (version + "\n").encode()),
        ("LICENSE", (ROOT / "LICENSE").read_bytes()),
        ("README.md", (ROOT / "README.md").read_bytes()),
    ]
    for name in ("Launcher.qml", "FavouriteStore.qml", "Strings.js", "Themes.js", "About.js", "icon.png"):
        files.append(("ui/" + name, (ROOT / "ui" / name).read_bytes()))
    files += [("ui/" + name, (ROOT / "ui" / name).read_bytes()) for name in ("DeviceIcons.js", "DeviceIcon.qml")]
    files += [("ui/input-icons/" + p.name, p.read_bytes()) for p in input_icon_files()]
    files += [("ui/fonts/" + p.name, p.read_bytes()) for p in sorted((ROOT / "ui/fonts").iterdir())]
    for name in ("install.sh", "uninstall.sh", "apply.sh"):
        files.append(("webos4/" + name, (ROOT / "webos4" / name).read_bytes(), exe))
    files.append(("webos4/patch-home.js", (ROOT / "webos4/patch-home.js").read_bytes()))
    files += [("shared/" + p.name, p.read_bytes()) for p in shared_files()]
    files.append(("webos4/Config.js", config_js(spec, version, "Home panel")))
    for name in ("install.sh", "uninstall.sh", "home-takeover.sh", "boot-hook.sh", "native-home.sh", "native-trial.sh", "mode-switch.sh"):
        files.append(("webos10/" + name, (ROOT / "webos10" / name).read_bytes(), exe))
    files.append(("webos10/native-stage.js", (ROOT / "webos10/native-stage.js").read_bytes()))
    files.append(("webos10/integration.js", (ROOT / "webos10/integration.js").read_bytes()))
    files += [("webos10/home-stub/" + p.name, p.read_bytes()) for p in sorted((ROOT / "webos10/home-stub").iterdir())]
    files.append(("webos10/%s_%s_all.ipk" % (APP, version), webos10_ipk(spec, version)))
    return files


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--config", default=str(ROOT / "config/launcher.json"),
                        help="favourites, colours and hidden apps (default: config/launcher.json)")
    parser.add_argument("--out", default=str(ROOT / "dist"), help="output directory (default: dist)")
    args = parser.parse_args()
    version = (ROOT / "VERSION").read_text().strip()
    spec = json.loads(Path(args.config).read_text())
    name = "rawin-launcher"
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    target = out / (name + ".tar.gz")
    target.write_bytes(tgz(release_files(spec, version), prefix=name + "/"))
    print(target)


if __name__ == "__main__":
    main()
