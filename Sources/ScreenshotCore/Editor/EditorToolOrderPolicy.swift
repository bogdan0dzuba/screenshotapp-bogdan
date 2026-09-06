import Foundation

public enum EditorToolOrderPolicy {
    public static let defaultOrder = [
        "rectangle", "arrow", "line", "ellipse", "pencil",
        "highlighter", "text", "counter", "blur", "pixelate",
    ]

    public static func normalize(_ order: [String]) -> [String] {
        var seen = Set<String>()
        let known = order.filter { defaultOrder.contains($0) && seen.insert($0).inserted }
        let missing = defaultOrder.filter { !seen.contains($0) }
        return known + missing
    }

    public static func move(fromOffsets offsets: IndexSet, toOffset destination: Int, in order: [String]) -> [String] {
        var result = normalize(order)
        let source = offsets.filter { result.indices.contains($0) }
        guard !source.isEmpty else { return result }

        let moved = source.map { result[$0] }
        for index in source.reversed() {
            result.remove(at: index)
        }
        let insertionIndex = min(max(destination, 0), result.count)
        result.insert(contentsOf: moved, at: insertionIndex)
        return normalize(result)
    }
}
