# Swift-to-Go result handling

Fix the renderer error prefix so invalid notebook JSON throws through the Swift bridge. Release each malloc-owned result returned by Go after conversion, including errors. The existing renderer and output format are unchanged.

This patch applies directly to upstream main. Its focused harness calls the real Go archive, checks valid code/Markdown and invalid notebook input, and repeats rendering. It does not claim a leak-instrumentation measurement.
