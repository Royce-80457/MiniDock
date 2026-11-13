import Foundation

public struct PreviewLayout {
    public let usesList: Bool
    public let size: CGSize
    public let itemWidth: CGFloat
    public let itemHeight: CGFloat

    public init(count: Int, available: CGSize) {
        let width = max(1, available.width - 16)
        let height = max(1, available.height - 16)
        usesList = CGFloat(count) * 224 + 16 > width || height < 190
        itemWidth = usesList ? min(340, max(1, width - 16)) : 216
        itemHeight = usesList ? 38 : 166
        size = CGSize(width: usesList ? min(width, itemWidth + 16) : CGFloat(count) * 224 + 16,
                      height: usesList ? min(height, CGFloat(count) * itemHeight + 16) : 182)
    }

    public static func frame(size: CGSize, anchor: CGRect, screen: CGRect, visible: CGRect) -> CGRect {
        var origin = CGPoint(x: anchor.midX - size.width / 2, y: anchor.maxY + 10)
        // A vertical Dock gets a preview on its inward-facing side.
        let bottomDistance = anchor.midY - screen.minY
        let leftDistance = anchor.midX - screen.minX
        let rightDistance = screen.maxX - anchor.midX
        let bottomDock = visible.minY > screen.minY + 4
        let leftDock = visible.minX > screen.minX + 4
        let rightDock = visible.maxX < screen.maxX - 4
        if leftDock || (!bottomDock && leftDistance < bottomDistance && leftDistance < rightDistance) {
            origin = CGPoint(x: anchor.maxX + 10, y: anchor.midY - size.height / 2)
        } else if rightDock || (!bottomDock && rightDistance < bottomDistance && rightDistance < leftDistance) {
            origin = CGPoint(x: anchor.minX - size.width - 10, y: anchor.midY - size.height / 2)
        } else if anchor.midY > screen.midY {
            origin.y = anchor.minY - size.height - 10
        }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        return CGRect(origin: origin, size: size)
    }
}
