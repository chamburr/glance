# Developer previews

This change extends Glance as a single Quick Look provider for code, documents and data. Existing archive and notebook previews remain available.

## Added behavior

- WKWebView replaces the deprecated WebView. Bundled CSS, scripts and fonts use a restricted resource scheme; previews cannot fetch network resources. The network-client entitlement is required for WebKit’s sandboxed content process to start, even for local resources; the content security policy still blocks network access.
- Web previews include Find/Next, Copy, font size, wrapping, System/Light/Dark appearance and a heading-based Contents sidebar. Display settings persist separately in the app and extension sandboxes. Copy returns the source when available, otherwise the preview's text.
- Markdown renders GitHub-style Note/Tip/Important/Warning/Caution callouts and offers bounded zoom/reset controls for Mermaid diagrams. Code blocks retain literal alert markers.
- Markdown renders Mermaid diagrams and LaTeX math using bundled libraries. Mermaid uses strict mode, bounded graph size and serialized redraws when appearance changes. No CDN is required.
- Readable raster images within the Markdown document's directory are validated and embedded. Each image is limited to 5 MB and 20 million pixels, with a combined 20 MB budget. Symlinks cannot escape the directory. Quick Look only grants access to the selected file, so sibling images may still be unavailable in Finder; no sandbox bypass or broad disk permission is added.
- Standalone and Quick Look previews refresh after stable file changes, including atomic editor saves. During refresh, web previews preserve scroll position, Contents visibility and Find text. Transient read failures keep the last good preview. Observation stops when the preview closes or the extension view disappears; only the selected path is observed, not every child of a folder. Standalone windows remember their size. Reading position is preserved during refresh, not persisted across closing/reopening a file.
- Unified `.diff`/`.patch` previews show colored changes, paired old/new line numbers and navigation between files. Malformed and combined hunks remain readable without invented line numbers. Rendered output is bounded to 200 files, 12,000 rows, 2,000 characters per row and approximately 4 MB; Copy retains the full accepted source.
- JSON is pretty-printed, binary property lists are converted to XML, and XML without a DTD is formatted without external entity loading. Invalid JSON/XML remains readable as source.
- Canonical TypeScript/TSX, YAML/TOML, XML/property-list, CSV, folder and SQLite content types are registered. MPEG-2 transport stream types are deliberately not claimed. macOS file associations still determine which extension Finder invokes.
- CSV and TSV use the existing SwiftCSV dependency. Quoted fields, duplicate headers and short rows are preserved, with at most 5,000 data rows. Cells support text selection, clickable column sorting and 100-row pages. Numeric values sort numerically, equal values retain source order, and blank/missing values stay last in both directions. Sorting applies across all loaded rows and returns to the first page. The 5,000-row preview cap still applies; pagination is not streaming.
- Folder previews show expandable directory trees, limited to four levels and 2,000 entries. Hidden files, app packages and symbolic-link traversal are excluded.
- SQLite previews open databases read-only, with query-only/trusted-schema restrictions, a two-second query budget and bounded output. Ordinary tables show at most 200 rows, 200 columns and 2,000 characters per cell; at most 50 tables appear. Virtual tables and user-supplied queries are not executed. A table picker selects the visible table, declared column types appear in header tooltips, and 50-row pages navigate the loaded preview rows. This is a preview, not a database editor or an unbounded database browser.
- The Swift-to-Go renderer releases returned C strings and propagates renderer errors correctly.

## Build

Requirements: full Xcode, Go and the existing Swift package dependencies resolved by Xcode. There is no new application background service. Go is needed for Glance's existing Chroma/Goldmark renderer; the only added rendering dependency is bundled Mermaid.

```sh
scripts/build-local.sh
```

The script builds a universal Release app into a temporary directory. An Xcode build phase compiles the universal CLI into the app's Resources directory. The helper then ad-hoc signs the extension and app for local use. It prints the resulting app path. Set `GLANCE_BUILD_DIR` to reuse derived data. It does not install the app, restart Finder or remove other preview providers.

Developer ID signing and notarization remain release-maintainer responsibilities. Local ad-hoc signing is not notarization.

## CLI

The build bundles a native preview launcher at `Glance.app/Contents/Resources/glance`. A symlink in a directory on PATH exposes it without a second installed application:

```sh
ln -s /Applications/Glance.app/Contents/Resources/glance ~/.local/bin/glance
glance README.md
glance --version
glance --check README.md example.py
glance --quick-look README.md
```

By default the launcher opens Glance's standalone preview window, reusing the same controllers as the Quick Look extension. This previews CSV and TypeScript source even when Finder chooses a native provider. `--quick-look` explicitly uses QLPreviewPanel and the system's installed providers instead. Neither mode shells out to `qlmanage` or exports HTML.

Images, PDFs and media retain Apple's native preview inside the standalone window. Unknown binary documents also fall back to the system preview.

The standalone Markdown window offers **Allow image folder…**. Choosing the document/project folder grants read-only sandbox access while that window is open. Relative image paths may then reach parent/sibling directories within the selected root. No permanent disk-wide permission or background helper is required. Image validation and size limits still apply.

Finder retains its built-in CSV preview on this Mac. Use `glance file.csv` for the table preview. TypeScript `.ts` may likewise be classified as video by macOS; the standalone window handles source directly without claiming video types.

## Validation

```sh
(cd HTMLConverter && go test ./... && golangci-lint run)
swiftlint lint --quiet --strict
# Use the version in Mintfile (0.58.6), not a different Homebrew version.
swiftformat --lint .
scripts/test-previews.sh /path/to/built/Glance.app
```

The preview checks compile the actual renderer/controllers, load bundled resources in an off-screen WebKit view, check Mermaid/math/Contents and script handling, exercise CSV/JSON/property-list/folder/SQLite paths, verify the database bytes remain unchanged, exercise standalone CSV/TypeScript and explicit image-root handling, verify CSP blocks actual fetches, check diff parsing/escaping/limits, native table sorting/page boundaries, database table selection/paging, live atomic-save refresh and scroll preservation, and generate Markdown, diff and table PNGs for visual inspection. They never activate or order a window to the front. The installed-extension check uses an actual Quick Look service in its own off-screen window and verifies completion logs for each supported fixture:

```sh
scripts/test-installed.sh
```

Run it after installing/enabling this build and disabling competing providers. It never activates a window or changes other providers itself. Native file routing is tested separately from standalone rendering. The folder-permission panel remains a user action, not an automated grant.

## Bundled assets

Mermaid 11.17.2 is MIT-licensed; its license is included beside the bundle. `scripts/update-mermaid.py` fetches the exact npm archive and verifies its pinned SHA-512 integrity before updating the two bundled files. KaTeX and its fonts reuse Glance's existing notebook assets.

## Remaining feature gaps

This build does not claim full Looq parity. It does not provide persistent reading-position memory, code folding/sticky scope headers, a broad selectable theme/font catalog, emoji shortcodes, CSS/SQL auto-formatting, streaming huge files, full database pagination beyond the preview cap, rich folder grouping/icons, installer-signature metadata, or a recent/agent-files menu bar. Existing size limits remain intentional.
