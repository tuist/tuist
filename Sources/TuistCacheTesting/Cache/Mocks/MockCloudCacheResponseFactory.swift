import Foundation
import TuistCloud
import TuistCore
import TuistGraph
import TuistSupport
import TuistSupportTesting
@testable import TuistCache
@testable import TuistCoreTesting

public class MockCloudCacheResourceFactory: CloudCacheResourceFactorying {
    public init() {}

    public var invokedExistsResource = false
    public var invokedExistsResourceCount = 0
    public var invokedExistsResourceParameters: (name: String, hash: String, Void)? // swiftlint:disable:this large_tuple
    public var invokedExistsResourceParametersList = [(name: String, hash: String, Void)]()
    public var stubbedExistsResourceError: Error?
    public var stubbedExistsResourceResult: CloudExistsResource = HTTPResource(
        request: { URLRequest.test() },
        parse: { _, _ in CloudResponse(status: "HEAD", data: CloudEmptyResponse()) },
        parseError: { _, _ in CloudEmptyResponseError() }
    )

    public func existsResource(
        name: String,
        hash: String
    ) throws -> HTTPResource<CloudResponse<CloudEmptyResponse>, CloudEmptyResponseError> {
        invokedExistsResource = true
        invokedExistsResourceCount += 1
        invokedExistsResourceParameters = (name, hash, ())
        invokedExistsResourceParametersList.append((name, hash, ()))
        if let error = stubbedExistsResourceError {
            throw error
        }
        return stubbedExistsResourceResult
    }

    public var invokedFetchResource = false
    public var invokedFetchResourceCount = 0
    public var invokedFetchResourceParameters: (name: String, hash: String, Void)? // swiftlint:disable:this large_tuple
    public var invokedFetchResourceParametersList = [(name: String, hash: String, Void)]()
    public var stubbedFetchResourceError: Error?
    public var stubbedFetchResourceResult: CloudCacheResource = HTTPResource(
        request: { URLRequest.test() },
        parse: { _, _ in CloudResponse.test(data: CloudCacheResponse.test()) },
        parseError: { _, _ in CloudResponseError.test() }
    )

    public func fetchResource(name: String, hash: String) throws -> CloudCacheResource {
        invokedFetchResource = true
        invokedFetchResourceCount += 1
        invokedFetchResourceParameters = (name, hash, ())
        invokedFetchResourceParametersList.append((name, hash, ()))
        if let error = stubbedFetchResourceError {
            throw error
        }
        return stubbedFetchResourceResult
    }

    public var invokedStoreResource = false
    public var invokedStoreResourceCount = 0
    // swiftlint:disable:next large_tuple
    public var invokedStoreResourceParameters: (
        name: String,
        hash: String,
        contentMD5: String
    )?
    public var invokedStoreResourceParametersList = [(name: String, hash: String, contentMD5: String)]()
    public var stubbedStoreResourceError: Error?
    public var stubbedStoreResourceResult: CloudCacheResource = HTTPResource(
        request: { URLRequest.test() },
        parse: { _, _ in CloudResponse.test(data: CloudCacheResponse.test()) },
        parseError: { _, _ in CloudResponseError.test() }
    )

    public func storeResource(name: String, hash: String, contentMD5: String) throws -> CloudCacheResource {
        invokedStoreResource = true
        invokedStoreResourceCount += 1
        invokedStoreResourceParameters = (name, hash, contentMD5)
        invokedStoreResourceParametersList.append((name, hash, contentMD5))
        if let error = stubbedStoreResourceError {
            throw error
        }
        return stubbedStoreResourceResult
    }

    public var invokedVerifyUploadResource = false
    public var invokedVerifyUploadResourceCount = 0
    // swiftlint:disable:next large_tuple
    public var invokedVerifyUploadResourceParameters: (
        name: String,
        hash: String,
        contentMD5: String
    )?
    public var invokedVerifyUploadResourceParametersList = [(name: String, hash: String, contentMD5: String)]()
    public var stubbedVerifyUploadResourceError: Error?
    public var stubbedVerifyUploadResourceResult: CloudVerifyUploadResource = HTTPResource(
        request: { URLRequest.test() },
        parse: { _, _ in CloudResponse.test(data: CloudVerifyUploadResponse.test()) },
        parseError: { _, _ in CloudResponseError.test() }
    )

    public func verifyUploadResource(name: String, hash: String, contentMD5: String) throws -> CloudVerifyUploadResource {
        invokedVerifyUploadResource = true
        invokedVerifyUploadResourceCount += 1
        invokedVerifyUploadResourceParameters = (name, hash, contentMD5)
        invokedVerifyUploadResourceParametersList.append((name, hash, contentMD5))
        if let error = stubbedVerifyUploadResourceError {
            throw error
        }
        return stubbedVerifyUploadResourceResult
    }
}
