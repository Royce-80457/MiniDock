import CoreGraphics

/// Counts only, never key codes or event contents. Unlike the tap callback,
/// these counters can also notice input waiting while AX is being queried.
struct InputStamp: Equatable {
    let counts: [UInt32]
    static func capture() -> InputStamp {
        let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .rightMouseDown,
            .otherMouseDown, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            .flagsChanged, .keyDown, .scrollWheel]
        return InputStamp(counts: types.map {
            CGEventSource.counterForEventType(.combinedSessionState, eventType: $0)
        })
    }
}
