# Developer source content types

Register TypeScript/TSX and canonical YAML/TOML type identifiers and map TypeScript, TSX, JSON Lines and dotenv extensions to existing Chroma lexers. MPEG transport-stream identifiers are not claimed; Finder routing can still select a native provider for .ts files.

This patch applies directly to upstream main. Verification checks the registered identifiers and compiles the existing renderer routing; it does not claim Finder has switched providers.
