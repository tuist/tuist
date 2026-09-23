import Foundation
import Testing
import TuistServer
@testable import TuistRunnerCommand

struct StubRunnerVolumeContextService: RunnerVolumeContextServicing {
    static let serverURL = URL(string: "https://runner-volume-tests.tuist.dev")!

    func resolve(account: String?, path: String?) async throws -> RunnerVolumeContext {
        #expect(account == "explicit-account")
        #expect(path == "/project")
        return RunnerVolumeContext(accountHandle: "resolved-account", serverURL: Self.serverURL)
    }
}

enum RunnerVolumeTestData {
    static let id = "a57a427c-1ffc-476f-9282-558ff3f61585"
    static let volume = """
    {"id":"a57a427c-1ffc-476f-9282-558ff3f61585","key":"gradle","repository":"demo/android-app",
     "provider":"github","platform":"linux","architecture":"amd64","used_bytes":2700000000,
     "capacity_bytes":20000000000,"unmeasured_copies":0,"unmeasured_capacity_copies":0}
    """
    static let pagination = """
    {"current_page":2,"page_size":5,"total_count":6,"total_pages":2,
     "has_next_page":false,"has_previous_page":true}
    """

    static func decode<T: Decodable>(_ json: String) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: Data(json.utf8))
    }
}
