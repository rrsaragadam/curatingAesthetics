# Wardrobe

SwiftPM macOS app (macOS 14+). No Xcode project.

## Build

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build
```

`DEVELOPER_DIR` is only needed when `xcode-select` points at the Command Line Tools.

## Snapshots

Walks every screen in light and dark mode against a throwaway library in
/tmp (never the real one), saves one PNG per screen and mode, then quits:

```bash
WARDROBE_SNAPSHOT=/tmp/Wardrobe-shots caffeinate -dimsu .build/debug/Wardrobe
```

`caffeinate` keeps the display awake; a sleeping display makes every capture
fail with "could not create image from window". Screens are listed in
`Sources/Wardrobe/App/SnapshotMode.swift`. Delete saved split view widths
first with `defaults delete Wardrobe` when checking first-launch layout.

Add `WARDROBE_SNAPSHOT_LINK=<product url>` to also capture that page imported
in the Add from link sheet (needs the network). A good test is a Uniqlo page,
where every photo of the chosen color has a model in it:
`https://www.uniqlo.com/ca/en/products/E471809-000/00?colorDisplayCode=09`
