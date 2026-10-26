# Offline WKWebView previews

Replace deprecated WebView with WKWebView while keeping existing preview factories and renderers. Serve bundled styles/scripts/fonts through a restricted scheme, use a nonpersistent data store and block document network fetches with CSP. External HTTP/HTTPS/mail links open only on a user click; fragment navigation stays in the preview.

The extension network-client entitlement is required for the sandboxed WebKit content process even for local bundled resources. CSP blocks document connections. This patch applies directly to upstream main and adds no toolbar, Markdown rendering libraries or refresh observer.
