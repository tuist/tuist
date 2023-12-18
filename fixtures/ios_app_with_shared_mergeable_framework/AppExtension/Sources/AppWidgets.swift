import DynamicFrameworkA // Xcode target (dynamic framework)
import DynamicFrameworkB // Xcode target (dynamic framework)
import MergeableXCFramework // XCFramework (dynamic framework)
import SwiftUI
import WidgetKit

@main
struct AppWidgetsBundle: WidgetBundle {
    var body: some Widget {
        AppWidget()
    }
}

struct AppWidget: Widget {
    var name: String {
        "\(MergeableXCFramework().name) > \(DynamicFrameworkAComponent().composedName()) \(DynamicFrameworkBComponent().composedName())"
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "AppWidget",
            provider: AppWidgetProvider(title: name)
        ) { entry in
            ZStack {
                Text(entry.title)
            }
        }
    }
}

struct AppWidgetProvider: TimelineProvider {
    let title: String

    struct Entry: TimelineEntry {
        let date: Date
        let title: String
    }

    func placeholder(in _: Context) -> AppWidgetProvider.Entry {
        Entry(date: Date(), title: title)
    }

    func getSnapshot(in _: Context, completion: @escaping (AppWidgetProvider.Entry) -> Void) {
        completion(Entry(date: Date(), title: title))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<AppWidgetProvider.Entry>) -> Void) {
        completion(.init(entries: [Entry(date: Date(), title: title)], policy: .never))
    }
}
