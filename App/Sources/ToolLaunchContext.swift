#if os(macOS)
/// Present only while a tool was opened from the Tools launcher.
struct ToolLaunchContext {
    let returnToLauncher: () -> Void
}
#endif
