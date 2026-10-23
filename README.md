# Recast

A native macOS menu bar app that converts images in a single drag.

Start dragging an image in any app, hold your shortcut key, and drop the image on the format you want. Conversion happens on your Mac with Apple's own image frameworks. Nothing is uploaded.

## How to use it

1. **Start dragging an image.** For example, a picture on a website in Safari, Chrome or Firefox, a file in Finder, or an attachment in Mail.
2. **While dragging, hold your shortcut key.** The default is ⌃ Control. You can switch to ⌥ Option, ⌘ Command, ⇧ Shift, ⌃⌥ or ⌃⇧ in Settings. Press the key *after* the drag has started. Browsers treat a modifier held while clicking as something else, such as ⌃-click opening the context menu.
3. **Drop the image on a format.** The format bar appears just above the cursor and stays until you let go of the mouse, so you can release the key once it's showing. If you drop somewhere else, the drag works as usual and nothing is converted.

A small confirmation then shows the new file. You can drag its thumbnail into another app, double-click it to open the file, or click **Show in Finder**. It stays until you click somewhere else or press Esc.

### From the menu bar

- **Convert Images To ›** picks image files and converts them all to the chosen format.
- **Convert Clipboard Image To ›** converts an image you copied, for example with "Copy Image" in a browser.
- **Drag to Convert** turns the shortcut on or off.

## Where converted files go

Choose this in **Settings › General › Save converted images to**:

| Setting | Files dragged from Finder, Mail, … | Images from a browser or the clipboard |
| --- | --- | --- |
| Next to the Original (default) | Same folder as the original | Downloads |
| Downloads, Desktop or Other Folder… | That folder | That folder |

If the original's folder can't be written to, the file goes to Downloads instead. Recast never overwrites anything: if `photo.jpg` already exists, the new file is called `photo 2.jpg`.

## Formats

| Format | Convert to | Convert from |
| --- | --- | --- |
| PNG | ✓ | ✓ |
| JPEG | ✓ | ✓ |
| HEIC | ✓ | ✓ |
| AVIF | ✓ | ✓ |
| TIFF | ✓ | ✓ |
| GIF | ✓ | ✓ |
| BMP | ✓ | ✓ |
| PDF | ✓ | – |
| SVG | – | ✓ |
| WebP, JPEG XL, camera RAW, PSD, ICO and more | – | ✓ |

By default the format bar shows PNG, JPEG, HEIC, AVIF, TIFF and PDF. GIF and BMP can be turned on in **Settings › Formats**. A format your Mac can't write (HEIC and AVIF encoding depend on the macOS version) doesn't appear. macOS can read WebP but has no WebP encoder, so WebP only works as a source.

While converting, Recast:

- rotates photos upright, so apps that ignore the EXIF orientation still show them the right way up
- puts transparent areas on white for JPEG and BMP, which have no transparency, instead of the usual black
- keeps the color profile, and keeps camera, date and location metadata unless **Keep metadata** is off
- uses the main image of files that contain several images, and only the first frame of an animated GIF
- applies the **Quality** setting (default 85 %) to JPEG, HEIC and AVIF
- makes each PDF a single page sized from the image's resolution (72 dpi if the image doesn't say)
- draws SVGs at twice their size, and small icons at 1024 pixels on the long side. Converting an SVG to PDF keeps it as sharp vector graphics

## Settings

**General**

| Setting | What it does |
| --- | --- |
| Drag to convert | Turns the shortcut on or off (also in the menu bar) |
| Hold while dragging | The shortcut key: ⌃, ⌥, ⌘, ⇧, ⌃⌥ or ⌃⇧ |
| Save converted images to | See [Where converted files go](#where-converted-files-go) |
| Show in Finder after converting | Opens a Finder window with the new file selected |
| Copy converted image to clipboard | Puts the new file on the clipboard, ready to paste into Finder, chat apps and so on |
| Download the original when a browser only provides a link | See [Privacy](#privacy-and-permissions) |
| Show in menu bar | Hides the menu bar icon. To get to Settings, open Recast again from Applications or Spotlight |
| Open Recast at login | Starts Recast automatically |

**Formats**: which formats appear in the format bar, the quality for JPEG, HEIC and AVIF, and whether to keep metadata.

## Privacy and permissions

- All conversion happens on your Mac. Recast never uploads images.
- Recast only goes online in one case: when a browser hands over just a link instead of the image. It then downloads the image from that link, the same as opening it in the browser. You can turn this off in Settings.
- No Accessibility, Input Monitoring or Screen Recording permission is needed.
- The first time Recast saves to Downloads, Desktop or Documents, macOS asks for access to that folder.

## Build and install

You need macOS 14 or later and the Xcode Command Line Tools (`xcode-select --install`). The full Xcode app isn't required.

```sh
make install   # build, quit a running Recast, replace /Applications/Recast.app and launch it
make run       # build and launch from ./build
make test      # run the conversion tests
make icon      # regenerate Resources/AppIcon.icns
```

Builds are signed ad hoc, so macOS treats every new build as a different app and may ask for folder access again after you rebuild. To avoid that, sign with your own certificate, for example `SIGNING_IDENTITY="Apple Development: …" make install`.

## Project structure

- `Sources/RecastCore`: the conversion engine. It has no UI and is covered by `swift test`.
  - `ImageConverter` reads, rotates, flattens and encodes images with ImageIO.
  - `ImageIntake` turns whatever a drag or the clipboard provides into image files. That can be files from Finder, file promises or raw image data from browsers, or a link as a last resort.
- `Sources/Recast`: the app.
  - `DragMonitor` notices a drag with the shortcut held. A global mouse-down monitor starts it; while the button is down it checks the drag pasteboard and the modifier keys. That's why it doesn't need Accessibility permission.
  - `OverlayController` and `OverlayView` are the format bar and the confirmation: a floating panel that doesn't take focus from the app you're dragging from. On macOS 26 and later it uses Liquid Glass.
  - `StatusMenu`, `SettingsView`, `WelcomeView` and `WindowManager` handle the menu bar, settings and welcome window.
- `Tests/RecastCoreTests`: conversion and drop-handling tests.
- `scripts`: `build.sh` packages the app, and `make-icon.sh` with `make-icon.swift` draws the icon.

Debug builds can draw every window to PNG files and send sample drops through the format bar, which is handy for checking layout without screen recording:

```sh
scripts/build.sh debug
build/Recast.app/Contents/MacOS/Recast --snapshot /tmp/recast-snapshots
```

## License

MIT. See [LICENSE](LICENSE).
