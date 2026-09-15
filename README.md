# NetHog

A tiny macOS menu bar app that shows which apps are using your network right now,
with live download and upload speeds for each one.

## Build and run

```bash
./build.sh            # builds build/NetHog.app
./build.sh install    # also copies it to /Applications and launches it
```

To make a universal `build/NetHog-<version>.dmg`, run `./release.sh`. Set
`SIGN_IDENTITY` and `NOTARY_PROFILE` to sign and notarize it for public download
(see the top of `release.sh`).

Requires macOS 13+ and the Xcode command line tools. Regenerate the icon with
`swift Scripts/make_icon.swift`.

## How it works

Every second NetHog runs the built-in `/usr/bin/nettop` (no root needed), reads each
process's cumulative bytes in/out, and turns the differences into per-second rates.
Loopback (localhost) traffic is excluded.

Helper processes are merged into their app (Chrome Helper → Google Chrome), and XPC
services are attributed to the app that launched them (WebKit networking → Safari).
Turn off "Group" to see individual processes.

- **Live**: what's transferring now (idle apps fade out after 5 seconds).
- **Since Launch**: total data per app since NetHog started.
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
build/NetHog.app/Contents/MacOS/NetHog --dump [--no-group]   # print current hogs to the terminal
build/NetHog.app/Contents/MacOS/NetHog --snapshot ui.png     # render the popover to an image
```
