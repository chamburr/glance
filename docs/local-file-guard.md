# Reject non-file preview URLs

Check the URL scheme before translating a preview URL into a filesystem path. A remote URL whose path happens to match a readable local file must fail before local file metadata or content is read.

This patch applies directly to upstream main. The focused harness exercises a local file, a remote URL with the same local path and a missing file.
