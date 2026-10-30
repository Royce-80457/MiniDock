public enum FocusPolicy {
    /// Direct per-application evidence, independent of global AX focus support.
    public static func allowsAppSnapshot(target: Int32, workspace: Int32?, appFrontmost: Bool?) -> Bool {
        workspace == target && appFrontmost == true
    }
    public static func allows(target: Int32, workspace: Int32?, system: Int32?, appFrontmost: Bool?) -> Bool {
        guard workspace == target else { return false }
        // Positive evidence of a different focused app always wins.
        if let system { return system == target }
        // Missing global AX focus is not evidence of a different focused app.
        // Require affirmative per-application AX evidence in that case.
        return appFrontmost == true
    }
}
