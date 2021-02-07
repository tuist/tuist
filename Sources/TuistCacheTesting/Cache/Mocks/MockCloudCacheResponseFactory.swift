import Foundation
import TuistCloud
import TuistCore
import TuistGraph
import TuistSupport
import TuistSupportTesting
@testable import TuistCache
@testable import TuistCoreTesting

public class MockCloudCacheResourceFactory: CloudCacheResourceManufacturing {
    public init() {}

    public var invokedExistsResource = false
    public var invokedExistsResourceCount = 0
    public var invokedExistsResourceParameters: (hash: String, Void)?
    public var invokedExistsResourceParametersList = [(hash: String, Void)]()
    public var stubbedExistsResourceError: Error?
    public var stubbedExistsResourceResult: CloudExistsResource = HTTPResource(
        request: { URLRequest.test() },
        parse: { _, _ in CloudResponse(status: "HEAD", data: CloudHEADResponse()) },
        parseError: { _, _ in CloudHEADResponseError() }
    )

    public func existsResource(hash: String) throws -> HTTPResource<CloudResponse<CloudHEADResponse>, CloudHEADResponseError> {
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
    public var stubbedFetchResourceResult: CloudCacheResource = HTTPResource(
        request: { URLRequest.test() },
        parse: { _, _ in CloudResponse.test(data: CloudCacheResponse.test()) },
        parseError: { _, _ in CloudResponseError.test() }
    )

    public func fetchResource(hash: String) throws -> CloudCacheResource {
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
    public var stubbedStoreResourceResult: CloudCacheResource = HTTPResource(
        request: { URLRequest.test() },
        parse: { _, _ in CloudResponse.test(data: CloudCacheResponse.test()) },
        parseError: { _, _ in CloudResponseError.test() }
    )

    public func storeResource(hash: String, contentMD5: String) throws -> CloudCacheResource {
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
    public var invokedVerifyUploadResourceParametersList = [(hash: String, contentMD5: String)]()
    public var stubbedVerifyUploadResourceError: Error?
    public var stubbedVerifyUploadResourceResult: CloudVerifyUploadResource = HTTPResource(
        request: { URLRequest.test() },
        parse: { _, _ in CloudResponse.test(data: CloudVerifyUploadResponse.test()) },
        parseError: { _, _ in CloudResponseError.test() }
    )

    public func verifyUploadResource(hash: String, contentMD5: String) throws -> CloudVerifyUploadResource {
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
