# SQLite preview

Independent of all other slices, based on origin/main. Adds read-only SQLite previews with table selection and paging through at most 200 sampled rows per table and 50 tables. Guards include a two-second query deadline, read-only connection, trusted_schema disabled, bounded columns, cell text and HTML. Registers SQLite UTI in the host and extension; exempts databases from the generic size limit. No standalone or refresh changes.

Table navigation remains in this coherent database feature, with no shared renderer changes.

Validation: universal arm64/x86_64 Release build, strict SwiftLint, SwiftFormat 0.58.6 lint and `sh scripts/test-sqlite-preview.sh` pass. Tests compile production preview source with lightweight view stubs, without displaying or installing an app. Go source is unchanged. Finder delivery, older macOS and Intel runtime are untested.

Actual renderer check: `sh scripts/test-sqlite-preview-renderer.sh BUILT_GLANCE_APP OUTPUT_DIRECTORY` compiles the production WebPreviewVC and renderer, loads built extension resources, verifies actual DOM and saves an offscreen PNG. No window is shown or ordered. The PNG was inspected. SQLite checks cover real picker and next-page actions; folder checks expand real details; structured-data checks highlighted JSON.
