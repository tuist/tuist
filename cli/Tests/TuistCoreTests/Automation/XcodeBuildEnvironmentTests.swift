import Testing
@testable import TuistCore

struct XcodeBuildEnvironmentTests {
    @Test func compilationCacheVariables_name_the_project_and_its_upload_policy() {
        #expect(
            XcodeBuildEnvironment.compilationCacheVariables(fullHandle: "acme/app", upload: false, environment: [:])
                == ["TUIST_CAS_ACCOUNT": "acme", "TUIST_CAS_PROJECT": "app", "TUIST_CAS_UPLOAD": "false"]
        )
        #expect(
            XcodeBuildEnvironment.compilationCacheVariables(fullHandle: "acme/app", upload: true, environment: [:])
                == ["TUIST_CAS_ACCOUNT": "acme", "TUIST_CAS_PROJECT": "app"]
        )
        #expect(XcodeBuildEnvironment.compilationCacheVariables(fullHandle: nil, upload: true, environment: [:]).isEmpty)
    }

    @Test func compilationCacheVariables_leave_values_the_caller_set() {
        #expect(
            XcodeBuildEnvironment.compilationCacheVariables(
                fullHandle: "acme/app",
                upload: false,
                environment: ["TUIST_CAS_PROJECT": "other", "TUIST_CAS_UPLOAD": "true"]
            ).isEmpty
        )
    }
}
