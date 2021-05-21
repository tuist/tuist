import Foundation
import TuistCore
import TuistGraph
import TuistLab
import TuistSupport
import TuistSupportTesting
@testable import TuistCache
@testable import TuistCoreTesting

public class MockLabCacheResourceFactory: LabCacheResourceFactorying {
    public init() {}

    public var invokedExistsResource = false
    public var invokedExistsResourceCount = 0
    public var invokedExistsResourceParameters: (hash: String, Void)?
    public var invokedExistsResourceParametersList = [(hash: String, Void)]()
    public var stubbedExistsResourceError: Error?
    public var stubbedExistsResourceResult: LabExistsResource = HTTPResource(
        request: { URLRequest.test() },
        parse: { _, _ in LabResponse(status: "HEAD", data: LabHEADResponse()) },
        parseError: { _, _ in LabHEADResponseError() }
    )

    public func existsResource(hash: String) throws -> HTTPResource<LabResponse<LabHEADResponse>, LabHEADResponseError> {
        invokedExistsResource = true
        invokedExistsResourceCount += 1
        invokedExistsResourceParameters = (hash, ())
        invokedExistsResourceParametersList.append((hash, ()))
        if let error = stubbedExistsResourceError {
            throw error
        }
        return stubbedExistsResourceResult
    }

    public var invokedFetchResource = false
    public var invokedFetchResourceCount = 0
    public var invokedFetchResourceParameters: (hash: String, Void)?
    public var invokedFetchResourceParametersList = [(hash: String, Void)]()
    public var stubbedFetchResourceError: Error?
    public var stubbedFetchResourceResult: LabCacheResource = HTTPResource(
        request: { URLRequest.test() },
        parse: { _, _ in LabResponse.test(data: LabCacheResponse.test()) },
        parseError: { _, _ in LabResponseError.test() }
    )

    public func fetchResource(hash: String) throws -> LabCacheResource {
        invokedFetchResource = true
        invokedFetchResourceCount += 1
        invokedFetchResourceParameters = (hash, ())
        invokedFetchResourceParametersList.append((hash, ()))
        if let error = stubbedFetchResourceError {
            throw error
        }
        return stubbedFetchResourceResult
    }

    public var invokedStoreResource = false
    public var invokedStoreResourceCount = 0
    public var invokedStoreResourceParameters: (hash: String, contentMD5: String)?
    public var invokedStoreResourceParametersList = [(hash: String, contentMD5: String)]()
    public var stubbedStoreResourceError: Error?
    public var stubbedStoreResourceResult: LabCacheResource = HTTPResource(
        request: { URLRequest.test() },
        parse: { _, _ in LabResponse.test(data: LabCacheResponse.test()) },
        parseError: { _, _ in LabResponseError.test() }
    )

    public func storeResource(hash: String, contentMD5: String) throws -> LabCacheResource {
        invokedStoreResource = true
        invokedStoreResourceCount += 1
        invokedStoreResourceParameters = (hash, contentMD5)
        invokedStoreResourceParametersList.append((hash, contentMD5))
        if let error = stubbedStoreResourceError {
            throw error
        }
        return stubbedStoreResourceResult
    }

    public var invokedVerifyUploadResource = false
    public var invokedVerifyUploadResourceCount = 0
    public var invokedVerifyUploadResourceParameters: (hash: String, contentMD5: String)?
    public var invokedVerifyUploadResourceParametersList = [(hash: String, contentMD5: String)]() // swiftlint:disable:this identifier_name
    public var stubbedVerifyUploadResourceError: Error?
    public var stubbedVerifyUploadResourceResult: LabVerifyUploadResource = HTTPResource(
        request: { URLRequest.test() },
        parse: { _, _ in LabResponse.test(data: LabVerifyUploadResponse.test()) },
        parseError: { _, _ in LabResponseError.test() }
    )

    public func verifyUploadResource(hash: String, contentMD5: String) throws -> LabVerifyUploadResource {
        invokedVerifyUploadResource = true
        invokedVerifyUploadResourceCount += 1
        invokedVerifyUploadResourceParameters = (hash, contentMD5)
        invokedVerifyUploadResourceParametersList.append((hash, contentMD5))
        if let error = stubbedVerifyUploadResourceError {
            throw error
        }
        return stubbedVerifyUploadResourceResult
    }
}
