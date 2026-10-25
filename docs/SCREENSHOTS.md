# Screenshot provenance

The PNGs in `docs/images` capture the actual Aster SwiftUI/AppKit views from the source in this repository. An isolated native documentation harness hosted `ContentView` and the normal `AppState`, scanned a controlled filesystem folder through `DiskScanner`, then captured the rendered content view using AppKit's bitmap display capture. The UI layout and values were not painted into a mockup or edited over a personal screenshot.

The harness is separate from the shipping executable. It did not modify production startup behavior, inject fabricated scan results, execute cleanup, or capture the desktop behind the app.

| Image | View shown |
| --- | --- |
| `overview-dark.png` | Storage overview and map, dark appearance. |
| `overview-light.png` | The same scanned folder in light appearance. |
| `large-files-dark.png` | Large-file listing and selected-file inspector. |
| `cleanup-dark.png` | Two explicitly selected sample items in the cleanup queue, before review/execution. |

The root is named **Aster Documentation Sample**. Its folders contain sparse placeholder files with descriptive names, such as a movie, archives, build outputs and documents. Extensions demonstrate categorization; these files are not actual videos, archives or customer documents. Their logical sizes were set on disk and read by the normal scanner. The low allocated sizes and short scan times are consequences of these sparse fixtures and must not be presented as a storage-recovery or performance benchmark.

## Reproduce a privacy-safe view

Build locally and create a fresh sample directory, for example:

```sh
mkdir -p /private/tmp/Aster-Screenshot-Sample/Documents
printf 'Documentation example only.\n' > /private/tmp/Aster-Screenshot-Sample/Documents/Readme.txt
open -n dist/Aster.app --args --scan /private/tmp/Aster-Screenshot-Sample
```

Add only deliberately created sample files if you need a richer map. Wait for scanning to finish, choose the appearance, and capture only the app window/content. Never confirm a Trash move merely to take a screenshot.

Before committing screenshots:

- Inspect every image for home paths, account names, app inventories, private documents, signing identities, license keys or notifications.
- Check PNG metadata as well as visible text.
- Keep the sample-data explanation next to the images.
- Do not commit private previews, full desktop captures, fixture disk images or generated application binaries.

The normal app starts with a real scan of the user's selected folder/home directory. These documentation fixtures are not shipped as app data.
