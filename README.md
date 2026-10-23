# Recast

A small, native macOS menu bar app for converting images by drag and drop.

Start dragging an image anywhere — a picture in Safari or Chrome, a file in Finder, an attachment in Mail — then hold **⌃ Control**. A format bar pops up above your cursor. Drop the image on a format and the converted copy is saved: next to the original for files, or in Downloads for images from the web.

Everything runs locally with Apple's ImageIO. Nothing is uploaded.

## Formats

| Format | Read | Write |
| --- | --- | --- |
| HEIC / HEIF | ✓ | ✓ |
| JPEG | ✓ | ✓ |
| PNG | ✓ | ✓ |
| AVIF | ✓ | ✓ (when macOS can encode it) |
| TIFF | ✓ | ✓ |
| GIF | ✓ | ✓ |
| BMP | ✓ | ✓ |
| PDF | – | ✓ (one page, sized from the image's DPI) |
| WebP, JPEG XL, camera RAW, PSD, … | ✓ | – |

When converting, Recast:

- rotates photos upright, so EXIF orientation never trips up other apps
- puts transparent areas on white for JPEG and BMP instead of black
- keeps color profiles, and keeps camera, date and location metadata unless you turn that off
- never overwrites anything: `photo.jpg` becomes `photo 2.jpg` if needed

## Using it

- **Drag and hold:** start a drag, then hold the shortcut (⌃ Control by default; change it in Settings). The bar stays up until you let go of the mouse.
- **Menu bar:** *Convert Images To* converts files you pick, and *Convert Clipboard Image To* converts whatever you copied with "Copy Image".
- **After converting:** drag the thumbnail into another app, double-click it to open, or click *Show in Finder*.

Settings let you choose which formats appear in the bar, JPEG/HEIC/AVIF quality, where files are saved, whether to keep metadata, and whether Recast opens at login.

No Accessibility or Screen Recording permission is needed. The first time Recast saves into Downloads, Desktop or Documents, macOS asks for permission to use that folder.

## Build and install

You need macOS 14 or later and the Xcode Command Line Tools (`xcode-select --install`). The full Xcode app isn't required.

```sh
make install   # builds Recast.app, copies it to /Applications and launches it
make run       # builds and launches from ./build
make test      # runs the conversion tests
make icon      # regenerates Resources/AppIcon.icns
```

The app is signed ad hoc. To sign with your own certificate, set `SIGNING_IDENTITY="Developer ID Application: …"` before running `scripts/build.sh`.

## How it works

- `Sources/RecastCore`: the conversion engine (`ImageConverter`) and `ImageIntake`, which turns whatever a drag provides into image files. That covers file URLs from Finder, file promises and raw image data from browsers, and image links as a last resort. Covered by `swift test`.
- `Sources/Recast`: the app itself.
  - `DragMonitor` watches for drags with a global mouse-down monitor. While the button is held, it polls the drag pasteboard and the modifier keys, so it doesn't need Accessibility permission.
  - `OverlayController` shows a non-activating floating panel (Liquid Glass on macOS 26+) whose drop view hit-tests the format tiles.
  - The rest is the menu bar menu, settings and the welcome window.

Debug builds can render every window to PNGs and push sample drops through the format bar, which is useful for checking layout:

```sh
scripts/build.sh debug
build/Recast.app/Contents/MacOS/Recast --snapshot /tmp/recast-snapshots
```
