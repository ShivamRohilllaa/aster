import XCTest
import CoreGraphics
@testable import AsterCore

final class TreemapLayoutTests: XCTestCase {
    func testProportionalAreaAndNoOverlaps() {
        let weights: [Double] = [90, 53, 31, 20, 11, 9, 4, 2, 1]
        let items = weights.enumerated().map { TreemapItem(id: "\($0.offset)", weight: $0.element) }
        for bounds in [CGRect(x: 12, y: 19, width: 900, height: 500), CGRect(x: 0, y: 0, width: 100, height: 800)] {
            let tiles = TreemapLayout.rectangles(for: items, in: bounds)
            XCTAssertEqual(tiles.count, weights.count)
            let total = weights.reduce(0, +)
            let totalArea = Double(bounds.width * bounds.height)
            for tile in tiles {
                XCTAssertTrue(tile.rect.origin.x.isFinite && tile.rect.origin.y.isFinite)
                XCTAssertGreaterThan(tile.rect.width, 0)
                XCTAssertGreaterThan(tile.rect.height, 0)
                XCTAssertGreaterThanOrEqual(tile.rect.minX + 0.000001, bounds.minX)
                XCTAssertGreaterThanOrEqual(tile.rect.minY + 0.000001, bounds.minY)
                XCTAssertLessThanOrEqual(tile.rect.maxX, bounds.maxX + 0.000001)
                XCTAssertLessThanOrEqual(tile.rect.maxY, bounds.maxY + 0.000001)
                XCTAssertEqual(Double(tile.rect.width * tile.rect.height), weights[Int(tile.id)!] / total * totalArea, accuracy: 0.00001)
            }
            XCTAssertEqual(tiles.reduce(0.0) { $0 + Double($1.rect.width * $1.rect.height) }, totalArea, accuracy: 0.00001)
            for first in tiles.indices {
                for second in tiles.indices where second > first {
                    let overlap = tiles[first].rect.intersection(tiles[second].rect)
                    XCTAssertTrue(overlap.isNull || overlap.width * overlap.height < 0.00001)
                }
            }
        }
    }

    func testInvalidAndZeroWeightsDoNotCreateTiles() {
        let items = [TreemapItem(id: "zero", weight: 0), TreemapItem(id: "negative", weight: -5),
                     TreemapItem(id: "infinite", weight: .infinity), TreemapItem(id: "nan", weight: .nan),
                     TreemapItem(id: "only", weight: 10)]
        let bounds = CGRect(x: 0, y: 0, width: 700, height: 400)
        XCTAssertEqual(TreemapLayout.rectangles(for: items, in: bounds), [TreemapRectangle(id: "only", rect: bounds)])
        XCTAssertTrue(TreemapLayout.rectangles(for: [], in: bounds).isEmpty)
        XCTAssertTrue(TreemapLayout.rectangles(for: items, in: .zero).isEmpty)
    }

    func testStableOrderingForEqualWeights() {
        let items = ["c", "a", "b", "d"].map { TreemapItem(id: $0, weight: 1) }
        let bounds = CGRect(x: 0, y: 0, width: 500, height: 300)
        let first = TreemapLayout.rectangles(for: items, in: bounds)
        XCTAssertEqual(first.map(\.id), ["c", "a", "b", "d"])
        XCTAssertEqual(first, TreemapLayout.rectangles(for: items, in: bounds))
    }

    func testVeryLargeFiniteWeightsDoNotOverflow() {
        let items = [TreemapItem(id: "a", weight: Double.greatestFiniteMagnitude),
                     TreemapItem(id: "b", weight: Double.greatestFiniteMagnitude / 2)]
        let tiles = TreemapLayout.rectangles(for: items, in: CGRect(x: 0, y: 0, width: 600, height: 300))
        XCTAssertEqual(tiles.count, 2)
        XCTAssertEqual(tiles[0].rect.width * tiles[0].rect.height, 120_000, accuracy: 0.001)
        XCTAssertEqual(tiles[1].rect.width * tiles[1].rect.height, 60_000, accuracy: 0.001)
    }
}
