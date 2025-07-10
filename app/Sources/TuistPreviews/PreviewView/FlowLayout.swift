import Foundation
import SwiftUI

struct FlowLayout: Layout {
    let spacing: CGFloat

    init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let rows = arrangeSubviews(proposal: proposal, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height + (rows.count > 1 ? spacing : 0) }
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let rows = arrangeSubviews(proposal: proposal, subviews: subviews)
        var y = bounds.minY

        for row in rows {
            var x = bounds.minX
            for subview in row.subviews {
                subview.place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(width: subview.sizeThatFits(.unspecified).width, height: row.height)
                )
                x += subview.sizeThatFits(.unspecified).width + spacing
            }
            y += row.height + spacing
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var currentRow = Row(subviews: [], width: 0, height: 0)
        let maxWidth = proposal.width ?? .infinity

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let newWidth = currentRow.width + size.width + (currentRow.subviews.isEmpty ? 0 : spacing)

            if newWidth <= maxWidth || currentRow.subviews.isEmpty {
                currentRow.subviews.append(subview)
                currentRow.width = newWidth
                currentRow.height = max(currentRow.height, size.height)
            } else {
                rows.append(currentRow)
                currentRow = Row(subviews: [subview], width: size.width, height: size.height)
            }
        }

        if !currentRow.subviews.isEmpty {
            rows.append(currentRow)
        }

        return rows
    }

    private struct Row {
        var subviews: [LayoutSubview]
        var width: CGFloat
        var height: CGFloat
    }
}
