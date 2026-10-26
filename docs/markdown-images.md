# Markdown images

Independent contribution against upstream c6225d8, using the existing WebView, Script and Stylesheet APIs. No toolbar, launcher or web-controller modernization dependency.

Embeds genuine decodable images under the resolved document directory only when sandbox access permits. Caps individual files at 5 MB, total at 20 MB and decoded pixels at 20 million. Traversal and symlink escapes remain unchanged. No folder permission prompt or broader grant.

Run scripts/test-markdown-images.sh for headless rendering checks. No application activation or window ordering. Build using xcodebuild with a disposable derivedDataPath; never make all.

Validation on 26 October 2026: universal Release Xcode build passed (arm64 and x86_64, signing disabled, macOS 12 target); seven focused image checks passed by compiling the actual MarkdownPreview with minimal unrelated type stubs; strict SwiftLint and pinned SwiftFormat 0.58.6 lint passed. Existing renamed-rule warnings remain. No app activation, window ordering, installation, commits or publication.

Integration: combine the getHTML edit with other Markdown slices. A standalone folder grant remains a launcher concern and is not included here.

The byte limits are checked again after reading to reject a file that grew after its metadata check; the aggregate-budget test uses decodable padded images.
