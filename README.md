# PeepHole

A tiny macOS menu bar app that shows which apps are using your network right now,
with live download and upload speeds for each one.

## Install

Download the latest `PeepHole-<version>.dmg` from
[Releases](https://github.com/ABDe3N/PeepHole/releases), open it, and drag PeepHole into
Applications. Open it from Applications, not from the disk image, or Launch at login
and updates won't work (PeepHole will remind you).

PeepHole checks for updates with [Sparkle](https://sparkle-project.org). You can also
check by hand from the gear menu.

## Privacy

PeepHole never sends anything anywhere. It has no analytics, no account, and needs no
admin password or special permissions. The only network request it makes is the update
check against this repository's releases.

## Build and run

```bash
./build.sh            # builds build/PeepHole.app
./build.sh install    # also copies it to /Applications and launches it
```

To make a universal `build/PeepHole-<version>.dmg`, run `./release.sh`. Set
`SIGN_IDENTITY` and `NOTARY_PROFILE` to sign and notarize it for public download
(see the top of `release.sh`).

Run the tests with `swift test`.

Requires macOS 13+ and the Xcode command line tools. Regenerate the icon with
`swift Scripts/make_icon.swift`.

## How it works

Every second PeepHole runs the built-in `/usr/bin/nettop` (no root needed), reads each
process's cumulative bytes in/out, and turns the differences into per-second rates.
Loopback (localhost) traffic is excluded.

Helper processes are merged into their app (Chrome Helper → Google Chrome), and XPC
services are attributed to the app that launched them (WebKit networking → Safari).
Turn off "Group" to see individual processes.

The XPC attribution uses `responsibility_get_pid_responsible_for_pid`, a private macOS
function that Activity Monitor also relies on. It is looked up at runtime, so if a future
macOS removes it, those services just show under their own names. (Private API use is
also why PeepHole can't be on the Mac App Store.)

- **Live**: what's transferring now (idle apps fade out after 5 seconds).
- **Since Launch**: total data per app since PeepHole started.
- Apps only get a row once they stay above 50 KB/s for 2 seconds (or burst past
  10× that). Adjustable to 20/50/100 KB/s under the gear menu. Header and menu bar
  totals still count everything.
- Arrows (in the menu bar and the list) turn green above a threshold (100 KB/s by
  default, adjustable under the gear menu).
- Sorted by name by default so rows stay put; switch to "Traffic" to sort by a
  5 second average instead.
- Right-click a row to quit the app or show it in Finder.

## Debug flags

```bash
build/PeepHole.app/Contents/MacOS/PeepHole --dump [--no-group]   # print current network users to the terminal
build/PeepHole.app/Contents/MacOS/PeepHole --snapshot ui.png     # render the popover to an image
```

## License

MIT. See [LICENSE](LICENSE).
