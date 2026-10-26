# Table truncation validation, 26 October 2026

The original parser limit of 5001 includes the header, so the existing display cap is 5000 data rows. A focused actual-native-footer reproduction failed before the fix. The fixed path retains that cap, probes one extra data row, derives truncation from the supplied rows and displays the limit without implying a complete file count.

Universal Release build passed for arm64 and x86_64. All 25 headless checks passed, including over-limit notice, exact-limit absence of notice, bounded page count, positional parsing, stable sorting and actual native table views. Full strict SwiftLint and pinned SwiftFormat 0.58.6 passed. The task-fixture screenshot was inspected. No windows were shown, and the installed app/services were untouched.

Full logs are in the scratch directory pointed to by the repository's private `.git/glance-split-scratch`: `table-cap-red.log`, `table-cap-build.log`, `table-cap-tests.log`, `table-cap-lint.log` and `table-cap-format.log`.
