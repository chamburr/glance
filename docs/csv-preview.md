# csv-preview

Adds comma-delimited CSV routing and positional CSV/TSV rows to the existing native table. Duplicate headers, quoted values and ragged rows retain their positions. Parsing displays at most 5,000 data rows. No sorting or pagination. Finder may retain its built-in CSV handler; the extension advertises the standard CSV type.

Validation: isolated Release Xcode build; headless production routing/data checks; strict SwiftLint and SwiftFormat 0.58.6; unchanged Go converter tests and lint. Actual production controllers were rendered in unshown offscreen windows, with native table/legacy WebView assertions and inspected PNG captures. No windows were shown.
