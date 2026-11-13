public enum PreviewInteractionPolicy {
    public static func preservesClick(mousePressed: Bool, pointerInPanel: Bool, panelVisible: Bool) -> Bool {
        mousePressed && pointerInPanel && panelVisible
    }
}

public enum PreviewFocusPolicy {
    public enum Decision: Equatable { case cancelled, expired, wait, focus, confirmed }

    public static func decide(elapsed: Double, unchangedInput: Bool, targetExists: Bool,
                              minimized: Bool?, frontmost: Bool, focused: Bool, focusRequests: Int,
                              timeout: Double = 1.5) -> Decision {
        guard unchangedInput, targetExists else { return .cancelled }
        guard elapsed >= 0, elapsed < timeout else { return .expired }
        guard minimized == false, frontmost else { return .wait }
        if focused && focusRequests > 0 { return .confirmed }
        return focusRequests < 3 ? .focus : .wait
    }
}
