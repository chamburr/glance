# diff-preview

Adds bounded, escaped unified diff rendering and diff/patch routing using the existing web renderer. No toolbar or web renderer rewrite. Complete-source copy requires the separate web-controls contribution; truncation directs users to open the original file.

Validation: isolated Release Xcode build; headless production routing/data checks; strict SwiftLint and SwiftFormat 0.58.6; unchanged Go converter tests and lint. Actual production controllers were rendered in unshown offscreen windows, with native table/legacy WebView assertions and inspected PNG captures. No windows were shown.
