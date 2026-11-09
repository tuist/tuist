import Foundation
import Testing

@testable import TuistServer

struct ServerProjectTests {
    @Test func decodesBuildSystemsTheClientDoesNotKnow() throws {
        let json = """
        {
          "id": 1,
          "full_name": "tuist/once",
          "default_branch": "main",
          "visibility": "private",
          "build_system": "a-build-system-added-later"
        }
        """

        let project = try JSONDecoder().decode(Components.Schemas.Project.self, from: Data(json.utf8))

        #expect(ServerProject(project).buildSystem == "a-build-system-added-later")
    }
}
