# Markdown callouts

Independent contribution against upstream c6225d8, using the existing WebView, Script and Stylesheet APIs. No toolbar, launcher or web-controller modernization dependency.

Transforms only the five recognized GitHub blockquote markers into accessible notes. Ordinary blockquotes, code and unknown markers remain untouched.

Run scripts/test-markdown-callouts.sh for headless rendering checks. No application activation or window ordering. Build using xcodebuild with a disposable derivedDataPath; never make all.

Validation on 26 October 2026: universal Release Xcode build passed (arm64 and x86_64, signing disabled, macOS 12 deployment target); 2 focused headless checks passed using the existing legacy WebView (image checks compile the actual MarkdownPreview with minimal unrelated type stubs); strict SwiftLint and pinned SwiftFormat 0.58.6 lint passed. Existing SwiftLint renamed-rule warnings and WebView deprecation warnings remain. No app activation, window ordering, installed-app changes, Finder registration, commits or publication.

Integration: combine the focused MarkdownPreview edits when stacking these independent patches; math and Mermaid share no feature code. The modernization slice must retain .markdown-body as the content root and permit the bundled JS/CSS/font resources. Standalone folder-grant support and live refresh belong to their own contributions.
