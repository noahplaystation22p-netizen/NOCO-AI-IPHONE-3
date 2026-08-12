import Foundation
import WatchKit

enum WatchHaptics {
    static func appOpened() {
        WKInterfaceDevice.current().play(.start)
    }

    static func selection() {
        WKInterfaceDevice.current().play(.click)
    }

    static func voiceStarted() {
        WKInterfaceDevice.current().play(.start)
    }

    static func listening() {
        WKInterfaceDevice.current().play(.directionUp)
    }

    static func replyArrived() {
        WKInterfaceDevice.current().play(.success)
    }

    static func taskDone() {
        WKInterfaceDevice.current().play(.notification)
    }

    static func crownSnap() {
        WKInterfaceDevice.current().play(.click)
    }

    static func error() {
        WKInterfaceDevice.current().play(.failure)
    }
}
