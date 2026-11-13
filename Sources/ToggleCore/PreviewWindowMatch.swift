import Foundation

public struct PreviewWindowMatch {
    public let title: String
    public let frame: CGRect?

    public init(title: String, frame: CGRect?) {
        self.title = title
        self.frame = frame
    }

    public static func captureIndex(for index: Int, windows: [Self], captures: [Self], displays: [CGRect]) -> Int? {
        guard windows.indices.contains(index) else { return nil }
        let target = windows[index]
        let rules: [(Self, Self) -> Bool] = [
            { source, capture in
                guard let frame = source.frame, let other = capture.frame else { return false }
                return sameSize(frame, other) && abs(frame.minX - other.minX) < 2
                    && abs(frame.minY - other.minY) < 2 && compatibleTitles(source, capture)
            },
            { source, capture in !source.title.isEmpty && source.title == capture.title },
            { source, capture in
                guard let frame = source.frame, let other = capture.frame,
                      isDisplaySized(frame, displays: displays) else { return false }
                return sameSize(frame, other) && compatibleTitles(source, capture)
            }
        ]
        for matches in rules {
            let candidates = captures.indices.filter { matches(target, captures[$0]) }
            guard candidates.count == 1, let candidate = candidates.first else { continue }
            if windows.filter({ matches($0, captures[candidate]) }).count == 1 { return candidate }
        }
        return nil
    }

    public static func isDisplaySized(_ frame: CGRect, displays: [CGRect]) -> Bool {
        displays.contains {
            abs(frame.width - $0.width) < 2 && frame.height >= $0.height - 80 && frame.height <= $0.height + 2
        }
    }

    private static func sameSize(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.width - rhs.width) < 2 && abs(lhs.height - rhs.height) < 2
    }

    private static func compatibleTitles(_ lhs: Self, _ rhs: Self) -> Bool {
        lhs.title.isEmpty || rhs.title.isEmpty || lhs.title == rhs.title
    }
}
