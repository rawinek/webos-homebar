# Experiments

Things tried on the test TVs that are not part of the release. Each has its
own script; none is run by the installer.

## The LG Home stand-in as a package (overlay)

The overlay puts the black stand-in in LG Home's place with a bind mount at
every boot. The Homebrew Channel runs the boot hooks some 35 s after
power-on, and a HOME before that opens LG's own Home once
([Troubleshooting](troubleshooting.md#home-right-after-a-boot-opens-lgs-home-overlay)).

LG updates its built-in apps by installing a higher version of the same id
outside the firmware, and the app manager takes that copy over the one in
the firmware. If it does the same for `com.webos.app.home` from a developer
install, the stand-in as a package with version `99.0.0` is LG's Home from
the first second of a boot, with nothing to mount.

```sh
python3 tools/build-home-override.py          # dist/home-override/: the IPK and the script
scp dist/home-override/* root@<tv-ip>:/tmp/ovr/
ssh root@<tv-ip> sh /tmp/ovr/home-override.sh install   # or status, remove
```

`install` prints what the app manager reports for Home before and after
(where it reads it from, its type and version) and a verdict. `remove` takes
the package away; LG's Home is as before. The launcher's own install is not
touched; `takeover.sh restore` and a `keep-lg-home` file in
`/var/lib/webosbrew/rawin-launcher-home/` keep the bind mount out of the
way for a clean look.

What a HOME before the hooks would then show is the black page, until the
helper comes up and switches to the input: black for up to 15 s instead of
LG's Home for as long.

Result, B4 (webOS 10.3.1): **refused**. The developer installer parses the
package, closes the running Home, then fails with error -15, *Cannnot
install privileged app on developer mode*; nothing is written. An id under
`com.webos.` is privileged, and the developer installer will not take one.

### The copy by hand

The refusal is the developer installer's, not the app manager's. LG's own
updates of built-in apps go to `/media/cryptofs/apps/usr/palm/applications/`
(the store apps area), which the app manager reads at boot. `place` copies
the same files there by hand, as root; a reboot then shows whether the app
manager takes a higher version of Home from that area. `remove` deletes the
copy; it is gone from the app manager at the next boot.

Result, B4 (webOS 10.3.1): **works**. After a reboot the app manager reads
Home from the copy (`folderPath` in the store area, version 99.0.0, type
web), and a HOME before the hooks run launches the stand-in, which shows
nothing (the input stays on screen; a system "wait" toast on the first
press); LG's Home did not appear in three boots. The bind mount of the boot
hook goes on top without error.

Not taken into the release: it only matters in the first 40 s after a cold
boot, which a TV woken from standby never sees, and it would need its own
uninstall (the copy has to be removed, and the TV rebooted, before LG's
Home is back) and watching over LG's store and firmware updates. A TV
that tried it keeps the copy until `home-override.sh remove` and a reboot.

## Direct system Home

Now part of the release (see [How it works](how-it-works.md#system-home-webos-10-and-11)
and [Launch method](using.md#launch-method-overlay-builds)). Notes from the
test TVs:

- **Tested:** an LG B4 on webOS 10.3.1: install, update, switching between
  System HOME and the additional overlay in both directions, reboots in each
  method, uninstall and a clean install. webOS 11 and other TVs are untested;
  webOS 6 to 9 have the opt-in trial (`--try-native-home`,
  [install](install.md#trying-system-home-on-webos-6-to-9)); it worked on an LG C1 with webOS 6.5.3, where
  it replaces LG Home's program instead of its manifest.
- **It is not a new renderer.** The firmware's QML runner hosts the same panel
  under LG Home's id with lifecycle v2; a shorter HOME path may help startup and
  keeping the process, but not the QML rendering cost. Compare physical HOME,
  arrow animation, pointer use, app switching and a cold boot before calling it
  faster.
- **Switching is a journalled change** (`mode-switch.sh`): a failure or a power
  loss rolls back, Homebar's databases are copied between the two hosts, and the
  card that was in front is brought back, because the Home host first opens as a
  card of its own and LG would otherwise fall back to Live TV.
- **The app manager keeps what it read about Home.** A Home identity with a
  launch point of its own (`visible: true`) cannot be blocked and reread, so the
  staged manifest keeps `visible: false`; a restart of the TV clears a wrong
  state.
- **Magic Mapper and Input Hook:** recognised Homebar rules are backed up and
  removed when switching to System HOME and restored for the additional
  overlay only where you did not change them since; other actions stay.

From the unpacked release: `sh rawin-launcher/install.sh --native-home`. To
return to the overlay: *Launcher settings → Launch method*, or
`sh /var/lib/webosbrew/rawin-launcher-home/native-home.sh disable`; `status`
shows the state.
