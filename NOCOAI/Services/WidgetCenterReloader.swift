import Foundation
import WidgetKit

/// Thin wrapper so ConnectionStore doesn't need WidgetKit everywhere.
enum WidgetCenterReloader {
    static func reload() {
        WidgetCenter.shared.reloadTimelines(ofKind: "NOCOQuickActionsWidget")
    }
}
