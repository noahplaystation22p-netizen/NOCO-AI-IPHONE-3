import ClockKit
import SwiftUI

/// NOCO complication templates (WidgetKit/ClockKit ready).
final class NOCOComplicationProvider: NSObject, CLKComplicationDataSource {
    func getCurrentTimelineEntry(
        for complication: CLKComplication,
        withHandler handler: @escaping (CLKComplicationTimelineEntry?) -> Void
    ) {
        let template = makeTemplate(for: complication.family)
        let entry = CLKComplicationTimelineEntry(date: Date(), complicationTemplate: template)
        handler(entry)
    }

    func getTimelineEndDate(for complication: CLKComplication, withHandler handler: @escaping (Date?) -> Void) {
        handler(nil)
    }

    func getPrivacyBehavior(
        for complication: CLKComplication,
        withHandler handler: @escaping (CLKComplicationPrivacyBehavior) -> Void
    ) {
        handler(.showOnLockScreen)
    }

    private func makeTemplate(for family: CLKComplicationFamily) -> CLKComplicationTemplate {
        switch family {
        case .graphicCircular:
            return CLKComplicationTemplateGraphicCircularView(NOCOComplicationCircular())
        case .graphicCorner:
            return CLKComplicationTemplateGraphicCornerCircularView(NOCOComplicationCircular())
        default:
            return CLKComplicationTemplateModularSmallSimpleText(textProvider: CLKSimpleTextProvider(text: "NOCO"))
        }
    }
}

struct NOCOComplicationCircular: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    AngularGradient(colors: WatchRainbow.flow, center: .center),
                    lineWidth: 3
                )
            Text("N")
                .font(.caption.weight(.black))
        }
    }
}
