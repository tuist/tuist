import Foundation
import Mockable
import Testing
import TuistConfig
import TuistConfigLoader
import TuistEnvironment
import TuistServer
@testable import TuistRunnerCommand

enum RunnerVolumeTestData {
    static let serverURL = URL(string: "https://runner-volume-tests.tuist.dev")!

    static func configLoader(fullHandle: String? = "resolved-account/project") async throws -> MockConfigLoading {
        let loader = MockConfigLoading()
        let directory = try await Environment.current.pathRelativeToWorkingDirectory("/project")
        given(loader).loadConfig(path: .value(directory)).willReturn(.test(fullHandle: fullHandle))
        return loader
    }

    static func serverEnvironmentService() -> MockServerEnvironmentServicing {
        let service = MockServerEnvironmentServicing()
        given(service).url(configServerURL: .value(Tuist.test().url)).willReturn(serverURL)
        return service
    }

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
