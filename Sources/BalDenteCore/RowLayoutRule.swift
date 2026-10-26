import CoreGraphics

/// When a settings row keeps its control beside the label and when it drops the control underneath.
public enum RowLayoutRule {
    /// Stack when the label would get less than `minLead` points next to the control. An unknown (infinite) width never stacks.
    public static func stacked(width: CGFloat, controlWidth: CGFloat, minLead: CGFloat, gap: CGFloat) -> Bool {
        width.isFinite && controlWidth + gap + minLead > width
    }
}

/// How many columns a page of cards gets: as many as fit at `minColumn` each, from 1 up to `maxColumns`.
public enum ColumnRule {
    public static func count(width: CGFloat, minColumn: CGFloat, spacing: CGFloat, maxColumns: Int = 3) -> Int {
        guard width.isFinite, width > 0 else { return 1 }
        return max(1, min(maxColumns, Int(((width + spacing) / (minColumn + spacing)).rounded(.down))))
    }
}
