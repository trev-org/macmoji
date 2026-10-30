public enum ToolBackNavigationPolicy {
    /// A missing query represents a tool with no text field.
    public static func shouldReturnToLauncher(
        hasLauncherDestination: Bool,
        query: String?,
        isPlainBackspace: Bool
    ) -> Bool {
        hasLauncherDestination
            && isPlainBackspace
            && (query?.isEmpty ?? true)
    }
}
