import Foundation

public enum SliceRules {
    public static func accepts(horizontal: Double, vertical: Double, width: Double) -> Bool {
        guard width.isFinite, width > 0, horizontal.isFinite, vertical.isFinite else { return false }
        return abs(horizontal) >= max(70, width * 0.28) && abs(horizontal) > abs(vertical) * 2.2
    }
}
