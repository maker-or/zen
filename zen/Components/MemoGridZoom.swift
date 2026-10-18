import Foundation

enum MemoGridZoom {
    static let sizes: [CGFloat] = [60, 100, 170, 280]
    static let spacing: CGFloat = 12
    static let padding: CGFloat = 16

    static func previewScale(magnification: CGFloat, from index: Int) -> CGFloat {
        let size = sizes[index]
        return min(max(size * magnification, sizes[0]), sizes[sizes.count - 1]) / size
    }

    static func presetIndex(magnification: CGFloat, from index: Int) -> Int {
        let proposedSize = sizes[index] * max(magnification, 0.01)
        // Logarithmic distance makes zooming in and out equally sensitive.
        return sizes.indices.min {
            abs(log(sizes[$0] / proposedSize)) < abs(log(sizes[$1] / proposedSize))
        } ?? index
    }

    static func columnCount(width: CGFloat, size: CGFloat) -> Int {
        let usableWidth = max(0, width - padding * 2)
        return min(max(Int((usableWidth + spacing) / (size + spacing)), 3), 12)
    }
}
