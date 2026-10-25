import Foundation
import CoreGraphics

/// An input to the layout engine. Weights may be bytes, counts, or any positive quantity.
public struct TreemapItem: Equatable, Sendable {
    public let id: String
    public let weight: Double

    public init(id: String, weight: Double) {
        self.id = id
        self.weight = weight
    }
}

public struct TreemapRectangle: Identifiable, Equatable {
    public let id: String
    public let rect: CGRect

    public init(id: String, rect: CGRect) {
        self.id = id
        self.rect = rect
    }
}

/// Deterministic squarified treemaps. The engine does not add visual gutters;
/// returned rectangles partition the bounds in proportion to the positive weights.
public enum TreemapLayout {
    public static func rectangles(for items: [TreemapItem], in bounds: CGRect) -> [TreemapRectangle] {
        guard bounds.origin.x.isFinite, bounds.origin.y.isFinite,
              bounds.width.isFinite, bounds.height.isFinite,
              bounds.width > 0, bounds.height > 0 else { return [] }

        let area = Double(bounds.width * bounds.height)
        guard area.isFinite, area > 0 else { return [] }

        // Stable ties preserve the caller's ordering. Dividing by the maximum first
        // prevents large byte totals from overflowing when the weights are summed.
        let sorted = items.enumerated()
            .filter { $0.element.weight.isFinite && $0.element.weight > 0 }
            .sorted {
                if $0.element.weight == $1.element.weight { return $0.offset < $1.offset }
                return $0.element.weight > $1.element.weight
            }
        guard let maximum = sorted.first?.element.weight else { return [] }
        let total = sorted.reduce(0.0) { $0 + $1.element.weight / maximum }
        let weighted = sorted.compactMap { entry -> WeightedArea? in
            let value = (entry.element.weight / maximum) / total * area
            guard value > 0, value.isFinite else { return nil }
            return WeightedArea(id: entry.element.id, area: value)
        }

        var remaining = bounds
        var result: [TreemapRectangle] = []
        var row: [WeightedArea] = []
        var index = 0

        while index < weighted.count {
            let candidate = weighted[index]
            let shortSide = Double(min(remaining.width, remaining.height))
            guard shortSide > 0 else { break }
            if row.isEmpty || worstRatio(row + [candidate], side: shortSide) <= worstRatio(row, side: shortSide) {
                row.append(candidate)
                index += 1
            } else {
                place(row, in: &remaining, isLast: false, result: &result)
                row.removeAll(keepingCapacity: true)
            }
        }
        if !row.isEmpty {
            place(row, in: &remaining, isLast: true, result: &result)
        }
        return result
    }

    private struct WeightedArea {
        let id: String
        let area: Double
    }

    private static func worstRatio(_ row: [WeightedArea], side: Double) -> Double {
        guard let smallest = row.last?.area, let largest = row.first?.area else { return .infinity }
        let sum = row.reduce(0.0) { $0 + $1.area }
        // Ratios formulated in terms of strip width avoid squaring large weights.
        let stripWidth = sum / side
        return max((largest / stripWidth) / stripWidth, stripWidth / (smallest / stripWidth))
    }

    private static func place(_ row: [WeightedArea], in bounds: inout CGRect,
                              isLast: Bool, result: inout [TreemapRectangle]) {
        let sum = row.reduce(0.0) { $0 + $1.area }
        guard sum > 0 else { return }
        if bounds.width >= bounds.height {
            let stripWidth = isLast ? bounds.width : min(bounds.width, CGFloat(sum) / bounds.height)
            guard stripWidth > 0 else { return }
            var y = bounds.minY
            for (index, item) in row.enumerated() {
                let height = index == row.count - 1 ? bounds.maxY - y : CGFloat(item.area / sum) * bounds.height
                result.append(TreemapRectangle(id: item.id, rect: CGRect(x: bounds.minX, y: y, width: stripWidth, height: max(0, height))))
                y += height
            }
            bounds = CGRect(x: bounds.minX + stripWidth, y: bounds.minY,
                            width: max(0, bounds.width - stripWidth), height: bounds.height)
        } else {
            let stripHeight = isLast ? bounds.height : min(bounds.height, CGFloat(sum) / bounds.width)
            guard stripHeight > 0 else { return }
            var x = bounds.minX
            for (index, item) in row.enumerated() {
                let width = index == row.count - 1 ? bounds.maxX - x : CGFloat(item.area / sum) * bounds.width
                result.append(TreemapRectangle(id: item.id, rect: CGRect(x: x, y: bounds.minY, width: max(0, width), height: stripHeight)))
                x += width
            }
            bounds = CGRect(x: bounds.minX, y: bounds.minY + stripHeight,
                            width: bounds.width, height: max(0, bounds.height - stripHeight))
        }
    }
}
