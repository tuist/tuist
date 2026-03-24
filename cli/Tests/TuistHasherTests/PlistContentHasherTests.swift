import Foundation
import Mockable
import Path
import Testing
import TuistCore
import TuistSupport
import TuistTesting
import XcodeGraph

@testable import TuistHasher

struct InfoPlistContentHasherTests {
    private let subject: PlistContentHasher
    private let contentHasher: MockContentHashing
    private let filePath1 = try! AbsolutePath(validating: "/file1")

    init() {
        contentHasher = .init()
        subject = PlistContentHasher(contentHasher: contentHasher)
        given(contentHasher)
            .hash(Parameter<String>.any)
            .willProduce { $0 + "-hash" }
    }

    @Test
    func hash_whenPlistIsFile_tellsContentHasherToHashFileContent() async throws {
        // Given
        let infoPlist = InfoPlist.file(path: filePath1)
        given(contentHasher)
            .hash(path: .value(filePath1))
            .willReturn("stubHash")

        // When
        let hash = try await subject.hash(plist: .infoPlist(infoPlist))

        // Then
        verify(contentHasher)
            .hash(path: .any)
            .called(1)
        #expect(hash == "stubHash")
    }

    @Test
    func hash_whenPlistIsGeneratedFile_tellsContentHasherToHashFileContent() async throws {
        // Given
        let infoPlist = InfoPlist.generatedFile(
            path: filePath1,
            data: try #require(Data(base64Encoded: "stubHash"))
        )
        given(contentHasher)
            .hash(Parameter<Data>.any)
            .willProduce { $0.base64EncodedString() + "-hash" }

        // When
        let hash = try await subject.hash(plist: .infoPlist(infoPlist))

        // Then
        verify(contentHasher)
            .hash(Parameter<Data>.any)
            .called(1)
        #expect(hash == "stubHash-hash")
    }

    @Test
    func hash_whenPlistIsDictionary_allDictionaryValuesAreConsideredForHash() async throws {
        // Given
        let infoPlist = InfoPlist.dictionary([
            "1": 23,
            "2": "foo",
            "3": true,
            "4": false,
            "5": ["5a", "5b"],
            "6": ["6a": "6value"],
        ])
        // When
        let hash = try await subject.hash(plist: .infoPlist(infoPlist))

        // Then
        verify(contentHasher)
            .hash(Parameter<String>.any)
            .called(1)
        #expect(hash ==
            "1=integer(23);2=string(\"foo\");3=boolean(true);4=boolean(false);5=array([XcodeGraph.Plist.Value.string(\"5a\"), XcodeGraph.Plist.Value.string(\"5b\")]);6=dictionary([\"6a\": XcodeGraph.Plist.Value.string(\"6value\")]);-hash")
    }

    @Test
    func hash_whenPlistIsExtendingDefault_allDictionaryValuesAreConsideredForHash() async throws {
        // Given
        let infoPlist = InfoPlist.extendingDefault(with: [
            "1": 23,
            "2": "foo",
            "3": true,
            "4": false,
            "5": ["5a", "5b"],
            "6": ["6a": "6value"],
        ])

        // When
        let hash = try await subject.hash(plist: .infoPlist(infoPlist))

        // Then
        verify(contentHasher)
            .hash(Parameter<String>.any)
            .called(1)
        #expect(hash ==
            "1=integer(23);2=string(\"foo\");3=boolean(true);4=boolean(false);5=array([XcodeGraph.Plist.Value.string(\"5a\"), XcodeGraph.Plist.Value.string(\"5b\")]);6=dictionary([\"6a\": XcodeGraph.Plist.Value.string(\"6value\")]);-hash")
    }
}
