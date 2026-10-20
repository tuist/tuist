import Foundation
import Testing

@testable import TuistServer

struct BuildListCompatibilityTests {
    private let legacyResponse = #"""
    {
      "builds": [{
        "id": "00000000-0000-4000-8000-000000000001",
        "duration": 1000,
        "status": "success",
        "is_ci": false,
        "cacheable_tasks_count": 0,
        "cacheable_task_local_hits_count": 0,
        "cacheable_task_remote_hits_count": 0,
        "inserted_at": "2026-10-14T09:30:15Z",
        "url": "/team/project/builds/build-runs/00000000-0000-4000-8000-000000000001"
      }],
      "pagination_metadata": {
        "has_next_page": false,
        "has_previous_page": false,
        "current_page": 1,
        "page_size": 20,
        "total_count": 1,
        "total_pages": 1
      }
    }
    """#

    @Test func new_query_parameters_remain_optional_for_older_servers() {
        let query = Operations.listBuilds.Input.Query()
        #expect(query.from == nil)
        #expect(query.to == nil)
        #expect(query.is_ci == nil)
        #expect(query.after == nil)
        #expect(query.before == nil)
    }

    @Test(arguments: [false, true])
    func decodes_older_server_responses_and_ignores_future_fields(includeFutureFields: Bool) throws {
        var json = try #require(JSONSerialization.jsonObject(with: Data(legacyResponse.utf8)) as? [String: Any])
        if includeFutureFields {
            json["future_response_field"] = ["version": 2]
            var builds = try #require(json["builds"] as? [[String: Any]])
            builds[0]["future_build_field"] = "ignored"
            builds[0]["started_at"] = NSNull()
            json["builds"] = builds
        }

        let response = try decode(json)
        let build = try #require(response.builds.first)
        #expect(build.started_at == nil)
        #expect(response.pagination_metadata.start_cursor == nil)
        #expect(response.pagination_metadata.end_cursor == nil)
        #expect(response.pagination_metadata.current_page == 1)
        #expect(response.pagination_metadata.total_count == 1)
        #expect(response.pagination_metadata.total_pages == 1)
    }

    @Test func decodes_nullable_cursor_metadata_and_recorded_start_time() throws {
        var json = try #require(JSONSerialization.jsonObject(with: Data(legacyResponse.utf8)) as? [String: Any])
        var builds = try #require(json["builds"] as? [[String: Any]])
        builds[0]["started_at"] = "2026-10-14T09:29:00Z"
        json["builds"] = builds
        let metadata: [String: Any] = [
            "has_next_page": false,
            "has_previous_page": true,
            "page_size": 20,
            "current_page": NSNull(),
            "total_count": NSNull(),
            "total_pages": NSNull(),
            "start_cursor": "opaque-start",
            "end_cursor": "opaque-end",
            "future_pagination_field": true,
        ]
        json["pagination_metadata"] = metadata

        let response = try decode(json)
        let build = try #require(response.builds.first)
        #expect(build.started_at == ISO8601DateFormatter().date(from: "2026-10-14T09:29:00Z"))
        #expect(response.pagination_metadata.current_page == nil)
        #expect(response.pagination_metadata.total_count == nil)
        #expect(response.pagination_metadata.total_pages == nil)
        #expect(response.pagination_metadata.start_cursor == "opaque-start")
        #expect(response.pagination_metadata.end_cursor == "opaque-end")
    }

    private func decode(_ json: [String: Any]) throws -> Operations.listBuilds.Output.Ok.Body.jsonPayload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            Operations.listBuilds.Output.Ok.Body.jsonPayload.self,
            from: JSONSerialization.data(withJSONObject: json)
        )
    }
}
