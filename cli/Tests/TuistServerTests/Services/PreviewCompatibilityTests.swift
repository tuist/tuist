import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing
import TuistEnvironment
import TuistTesting

@testable import TuistServer

struct PreviewCompatibilityTests {
    @Test(.withMockedEnvironment(), arguments: [false, true])
    func uploads_preserve_the_legacy_request_and_only_send_known_architectures(native: Bool) async throws {
        let environment = try #require(Environment.mocked)
        environment.variables["TUIST_TOKEN"] = "project-token"

        let upload = try await Client.$additionalMiddlewares.withValue([PreviewUploadCompatibilityServer(native: native)]) {
            try await MultipartUploadStartPreviewsService().startPreviewsMultipartUpload(
                type: native ? .executable : .ipa,
                displayName: "App",
                version: nil,
                buildVersion: "1",
                bundleIdentifier: nil,
                supportedPlatforms: native ? [.macos] : [.ios],
                supportedArchitectures: native ? ["arm64"] : [],
                gitBranch: nil,
                gitCommitSHA: nil,
                gitRef: nil,
                binaryId: nil,
                fullHandle: "team/app",
                serverURL: URL(string: "https://test.tuist.dev")!,
                track: nil
            )
        }

        #expect(upload.appBuildId == "build")
        #expect(upload.uploadId == "upload")
    }

    @Test(
        .withMockedEnvironment(),
        arguments: ["getPreview", "listPreviews", "getLatestPreview", "completePreviewsMultipartUpload"], [false, true]
    )
    func preview_responses_negotiate_formats_and_decode_older_and_future_servers(operation: String, future: Bool) async throws {
        let environment = try #require(Environment.mocked)
        environment.variables["TUIST_TOKEN"] = "project-token"

        for authenticated in [false, true] {
            let response: Components.Schemas.Preview = try await Client.$additionalMiddlewares.withValue([
                PreviewCompatibilityServer(future: future),
            ]) {
                let serverURL = URL(string: "https://example.com")!
                let client = authenticated ? Client.authenticated(serverURL: serverURL) : Client
                    .unauthenticated(serverURL: serverURL)
                switch operation {
                case "getPreview":
                    return try await client.getPreview(.init(path: .init(
                        account_handle: "team", project_handle: "app", preview_id: "preview"
                    ))).ok.body.json
                case "listPreviews":
                    let list = try await client.listPreviews(.init(path: .init(
                        account_handle: "team", project_handle: "app"
                    ))).ok.body.json
                    return try #require(list.previews.first)
                case "getLatestPreview":
                    let latest = try await client.getLatestPreview(.init(
                        path: .init(account_handle: "team", project_handle: "app"), query: .init(
                            binary_id: "binary",
                            build_version: "1"
                        )
                    )).ok.body.json
                    return try #require(latest.preview)
                default:
                    return try await client.completePreviewsMultipartUpload(.init(
                        path: .init(account_handle: "team", project_handle: "app"),
                        body: .json(.init(
                            app_build_id: "build",
                            multipart_upload_parts: .init(parts: [.init(etag: "etag", part_number: 1)], upload_id: "upload"),
                            preview_id: "build"
                        ))
                    )).ok.body.json
                }
            }

            let preview = try ServerPreview(response)
            #expect(preview.id == "preview")
            #expect(preview.appBuilds.map(\.id) == ["mobile"])
            #expect(preview.appBuilds.first?.supportedPlatforms == [.simulator(.iOS)])
            #expect(preview.supportedPlatforms == [.simulator(.iOS)])
            #expect(response.builds.first?.supported_architectures == nil)
        }
    }
}

private struct PreviewCompatibilityServer: ClientMiddleware {
    let future: Bool

    func intercept(
        _ request: HTTPRequest,
        body _: HTTPBody?,
        baseURL _: URL,
        operationID: String,
        next _: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let header = try #require(HTTPField.Name("x-tuist-preview-capabilities"))
        #expect(request.headerFields[header] == "desktop")
        var builds: [[String: Any]] = [[
            "id": "mobile", "url": "https://example.com/mobile.zip", "type": "app_bundle",
            "supported_platforms": ["ios_simulator"],
        ]]
        if future {
            builds.append([
                "id": "future", "url": "https://example.com/future", "type": "future_format",
                "supported_platforms": ["ios_simulator"], "supported_architectures": ["future_cpu"],
            ])
        }
        var preview: [String: Any] = [
            "id": "preview", "url": "https://example.com/preview", "qr_code_url": "https://example.com/qr.png",
            "icon_url": "https://example.com/icon.png", "device_url": "https://example.com/install",
            "inserted_at": "2024-01-01T00:00:00Z", "created_from_ci": false,
            "supported_platforms": future ? ["future_os", "ios_simulator"] : ["ios_simulator"],
            "builds": builds,
        ]
        if future {
            preview["future_metadata"] = ["ignored": true]
        }
        let payload: [String: Any]
        switch operationID {
        case "listPreviews":
            payload = ["previews": [preview], "pagination_metadata": [
                "has_next_page": false, "has_previous_page": false, "current_page": 1,
                "page_size": 20, "total_count": 1, "total_pages": 1,
            ]]
        case "getLatestPreview":
            payload = ["preview": preview]
        default:
            payload = preview
        }
        var response = HTTPResponse(status: .ok)
        response.headerFields[.contentType] = "application/json"
        return (response, HTTPBody(try JSONSerialization.data(withJSONObject: payload)))
    }
}

private struct PreviewUploadCompatibilityServer: ClientMiddleware {
    let native: Bool

    func intercept(
        _: HTTPRequest,
        body: HTTPBody?,
        baseURL _: URL,
        operationID: String,
        next _: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        #expect(operationID == "startPreviewsMultipartUpload")
        let body = try #require(body)
        let data = try await Data(collecting: body, upTo: 4096)
        let payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(payload["type"] as? String == (native ? "executable" : "ipa"))
        #expect(payload["supported_platforms"] as? [String] == (native ? ["macos"] : ["ios"]))
        #expect(payload["supported_architectures"] as? [String] == (native ? ["arm64"] : nil))
        var response = HTTPResponse(status: .ok)
        response.headerFields[.contentType] = "application/json"
        return (response, HTTPBody(#"{"data":{"app_build_id":"build","upload_id":"upload"},"status":"success"}"#))
    }
}
