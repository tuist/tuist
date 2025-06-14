#if canImport(WidgetKit)

    import SwiftUI
    import WidgetKit

    struct Provider: TimelineProvider {
        public typealias Entry = SimpleEntry

        func placeholder(in _: Context) -> SimpleEntry {
            SimpleEntry(date: Date())
        }

        func getSnapshot(in _: Context, completion _: @escaping (SimpleEntry) -> Void) {}

        func getTimeline(in _: Context, completion _: @escaping (Timeline<SimpleEntry>) -> Void) {}

        public func snapshot(with _: Context, completion: @escaping (SimpleEntry) -> Void) {
            let entry = SimpleEntry(date: Date())
            completion(entry)
        }

        public func timeline(with _: Context, completion: @escaping (Timeline<Entry>) -> Void) {
            var entries: [SimpleEntry] = []

            // Generate a timeline consisting of five entries an hour apart, starting from the current date.
            let currentDate = Date()
            for hourOffset in 0 ..< 5 {
                let entryDate = Calendar.current.date(byAdding: .hour, value: hourOffset, to: currentDate)!
                let entry = SimpleEntry(date: entryDate)
                entries.append(entry)
            }

            let timeline = Timeline(entries: entries, policy: .atEnd)
            completion(timeline)
        }
    }

    struct SimpleEntry: TimelineEntry {
        public let date: Date
    }

    struct PlaceholderView: View {
        var body: some View {
            Text("Placeholder View")
        }
    }

    struct MyWidgetEntryView: View {
        var entry: Provider.Entry

        var body: some View {
            Text(entry.date, style: .time)
        }
    }

    @main
    struct MyWidget: Widget {
        private let kind: String = "MyWidget"

        public var body: some WidgetConfiguration {
            StaticConfiguration(kind: kind, provider: Provider()) { entry in
                MyWidgetEntryView(entry: entry)
            }
            .configurationDisplayName("MyWidget")
            .description("This is an example widget.")
        }
    }

#endif
