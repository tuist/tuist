import Foundation
import Testing

@testable import TuistBazelCommand

struct BazelProfileParserTests {
    @Test func parses_and_bounds_critical_path_actions() throws {
        let profile = """
        {
          "traceEvents": [
            {"name":"thread_name","ph":"M","pid":1,"tid":0,"args":{"name":"Critical Path"}},
            {"name":"action 'Compiling hello.cc'","cat":"critical path component","ph":"X","tid":0,"ts":200,"dur":623576},
            {"name":"action 'Linking hello'","cat":"critical path component","ph":"X","tid":0,"ts":1000,"dur":116006}
          ]
        }
        """

        let result = try #require(BazelProfileParser().parse(data: Data(profile.utf8)))

        #expect(result.durationMilliseconds == 740)
        #expect(result.actions == [
            BazelCriticalPathActionTelemetry(description: "action 'Compiling hello.cc'", durationMilliseconds: 624),
            BazelCriticalPathActionTelemetry(description: "action 'Linking hello'", durationMilliseconds: 116),
        ])
    }

    @Test func redacts_absolute_paths_from_action_descriptions() throws {
        let profile = """
        {"traceEvents":[
          {"name":"thread_name","ph":"M","tid":0,"args":{"name":"Critical Path"}},
          {"name":"action '/Users/runner/project/hello.cc'","cat":"critical path component","ph":"X","tid":0,"dur":1000}
        ]}
        """

        let result = try #require(BazelProfileParser().parse(data: Data(profile.utf8)))

        #expect(result.actions.map(\.description) == ["action '<redacted>"])
    }

    @Test func extracts_a_bounded_anonymous_build_timeline() throws {
        let profile = """
        {"traceEvents":[
          {"name":"thread_name","ph":"M","tid":7,"args":{"name":"Critical Path"}},
          {"name":"thread_name","ph":"M","tid":8,"args":{"name":"Action worker"}},
          {"name":"action 'Compiling /Users/runner/project/hello.cc'","cat":"critical path component","ph":"X","tid":7,"ts":1000,"dur":12000},
          {"name":"Action cache check","cat":"action processing","ph":"X","tid":8,"ts":2000,"dur":8000},
          {"name":"Too short","cat":"analysis","ph":"X","tid":8,"ts":3000,"dur":4000}
        ]}
        """

        let result = try #require(BazelProfileParser().parseTelemetry(data: Data(profile.utf8)))
        let timeline = try #require(result.buildTimeline)

        #expect(timeline.laneLabels == ["Critical path", "Worker 1"])
        #expect(timeline.durationMilliseconds == 12)
        #expect(timeline.spans == [
            BazelBuildTimelineSpanTelemetry(
                lane: 0,
                startMilliseconds: 0,
                durationMilliseconds: 12,
                category: "critical_path",
                description: "action 'Compiling <redacted>"
            ),
            BazelBuildTimelineSpanTelemetry(
                lane: 1,
                startMilliseconds: 1,
                durationMilliseconds: 8,
                category: "execution",
                description: "Action cache check"
            ),
        ])
    }
}
