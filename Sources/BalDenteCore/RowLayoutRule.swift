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

/// How tall the menu bar panel gets, and when it shows the "more below" hint.
public enum PanelHeightRule {
    /// The panel never grows past `cap` points, and stays `margin` points clear of the bottom of a short screen.
    public static func maxHeight(screen: CGFloat, cap: CGFloat = 520, margin: CGFloat = 40) -> CGFloat {
        max(200, min(cap, screen - margin))
    }

    /// Points of content still hidden below the visible part of the scroll view.
    public static func hiddenBelow(contentHeight: CGFloat, offset: CGFloat, visibleHeight: CGFloat) -> CGFloat {
        max(0, contentHeight - offset - visibleHeight)
    }

    /// Show the hint while more than a sliver of content is still below.
    public static func showsMoreHint(hiddenBelow: CGFloat, threshold: CGFloat = 12) -> Bool { hiddenBelow > threshold }
}
