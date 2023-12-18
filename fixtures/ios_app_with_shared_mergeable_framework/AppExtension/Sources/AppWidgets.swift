import SwiftUI
import WidgetKit
import MergeableXCFramework // XCFramework (dynamic framework)
import DynamicFrameworkA // Xcode target (dynamic framework)
import DynamicFrameworkB // Xcode target (dynamic framework)

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

    func placeholder(in context: Context) -> AppWidgetProvider.Entry {
        Entry(date: Date(), title: title)
    }

    func getSnapshot(in context: Context, completion: @escaping (AppWidgetProvider.Entry) -> Void) {
        completion(Entry(date: Date(), title: title))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AppWidgetProvider.Entry>) -> Void) {
        completion(.init(entries: [Entry(date: Date(), title: title)], policy: .never))
    }
}
