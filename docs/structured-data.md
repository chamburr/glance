# structured-data

Formats JSON, XML without DOCTYPE, and binary/XML plist in CodePreview; malformed JSON/XML retain raw source. Registers XML and property-list UTIs in the extension. No routing or renderer UI changes.

Independent patch based on origin/main; no other slice required. No standalone launcher, refresh, or web-renderer changes.

Build: `xcodebuild -scheme Glance -configuration Release -derivedDataPath "$BUILD_DIR" CODE_SIGNING_ALLOWED=NO MACOSX_DEPLOYMENT_TARGET=12.0 ONLY_ACTIVE_ARCH=NO "ARCHS=arm64 x86_64" build`. Does not install or register the app.

Validation: universal arm64/x86_64 Release build, strict SwiftLint, SwiftFormat 0.58.6 lint and `sh scripts/test-structured-data.sh` pass. Tests compile production preview source with lightweight view stubs, without displaying or installing an app. Go source is unchanged. Finder delivery, older macOS and Intel runtime are untested.

Actual renderer check: `sh scripts/test-structured-data-renderer.sh BUILT_GLANCE_APP OUTPUT_DIRECTORY` compiles the production WebPreviewVC and renderer, loads built extension resources, verifies actual DOM and saves an offscreen PNG. No window is shown or ordered. The PNG was inspected. SQLite checks cover real picker and next-page actions; folder checks expand real details; structured-data checks highlighted JSON.
