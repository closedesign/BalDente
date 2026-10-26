import BalDenteCore
import SwiftUI

/// Lays a page's cards out in 1 to 3 columns depending on the width, each card going to the shortest column.
/// The order reads left to right, top to bottom, so a narrow window (one column) is the same page as before.
struct MasonryLayout: Layout {
    var minColumn: CGFloat = 380
    var spacing: CGFloat = 18

    private func columns(_ width: CGFloat) -> Int { ColumnRule.count(width: width, minColumn: minColumn, spacing: spacing) }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (frames: [CGRect], height: CGFloat) {
        let n = columns(width)
        let colW = (width - spacing * CGFloat(n - 1)) / CGFloat(n)
        var heights = [CGFloat](repeating: 0, count: n)
        var frames: [CGRect] = []
        for v in subviews {
            let h = v.sizeThatFits(ProposedViewSize(width: colW, height: nil)).height
            let c = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            frames.append(CGRect(x: CGFloat(c) * (colW + spacing), y: heights[c], width: colW, height: h))
            heights[c] += h + spacing
        }
        return (frames, max(0, (heights.max() ?? spacing) - spacing))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? minColumn
        return CGSize(width: w, height: arrange(w, subviews).height)
    }

    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let a = arrange(b.width, subviews)
        for (v, f) in zip(subviews, a.frames) {
            v.place(at: CGPoint(x: b.minX + f.minX, y: b.minY + f.minY), anchor: .topLeading, proposal: ProposedViewSize(width: f.width, height: f.height))
        }
    }
}
