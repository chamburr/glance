import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {
	func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool { true }
}
