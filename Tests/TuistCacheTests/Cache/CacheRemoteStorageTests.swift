import XCTest
import TuistCore
import TuistCloud
import TuistCoreTesting
import RxSwift
import TSCBasic

@testable import TuistCache
@testable import TuistSupportTesting

final class CacheRemoteStorageTests: TuistUnitTestCase {
    var subject: CacheRemoteStorage!
    var cloudClient: CloudClienting!
    
    // - exists
    
    func test_exists_whenClientReturnsAnError() throws {
        // Given
        cloudClient = MockCloudClienting<CloudResponse<CloudHEADResponse>>.makeForError(error: CloudClientError.unauthorized)
        subject = CacheRemoteStorage(cloudClient: cloudClient)
        
        // When
        let result = subject.exists(hash: "acho tio", userConfig: .test())
            .toBlocking()
            .materialize()
        
        // Then
        switch result {
        case .completed:
            XCTFail("Expected result to complete with error, but result was successful.")
        case .failed(_, let error):
            XCTAssertEqual(error as! CloudClientError, CloudClientError.unauthorized)
        }
    }
    
    func test_exists_whenClientReturnsAnHTTPError() throws {
        // Given
        let cloudResponse = CloudResponse<CloudHEADResponse>(status: "shaki", data: CloudHEADResponse())
        let httpResponse: HTTPURLResponse = .test(statusCode: 500)
        cloudClient = MockCloudClienting.makeForSuccess(object: cloudResponse, response: httpResponse)
        subject = CacheRemoteStorage(cloudClient: cloudClient)
        
        // When
        let result = try subject.exists(hash: "acho tio", userConfig: .test())
            .toBlocking()
            .single()

        // Then
        XCTAssertFalse(result)
    }
    
    func test_exists_whenClientReturnsASuccess() throws {
        // Given
        let cloudResponse = CloudResponse<CloudHEADResponse>(status: "shaki", data: CloudHEADResponse())
        let httpResponse: HTTPURLResponse = .test()
        cloudClient = MockCloudClienting.makeForSuccess(object: cloudResponse, response: httpResponse)
        subject = CacheRemoteStorage(cloudClient: cloudClient)
        
        // When
        let result = try subject.exists(hash: "acho tio", userConfig: .test())
            .toBlocking()
            .single()
        
        // Then
        XCTAssertTrue(result)
    }
    
    func test_exists_whenClientReturnsA202() throws {
        // Given
        let cloudResponse = CloudResponse<CloudHEADResponse>(status: "shaki", data: CloudHEADResponse())
        let httpResponse: HTTPURLResponse = .test(statusCode: 202)
        cloudClient = MockCloudClienting.makeForSuccess(object: cloudResponse, response: httpResponse)
        subject = CacheRemoteStorage(cloudClient: cloudClient)
        
        // When
        let result = try subject.exists(hash: "acho tio", userConfig: .test())
            .toBlocking()
            .single()
        
        // Then
        XCTAssertTrue(result)
    }
    
    // - fetch
    
    func test_fetch_whenClientReturnsAnError() throws {
        // Given
        let cloudClient = MockCloudClienting<CloudResponse<CloudCacheResponse>>()
        cloudClient.configureForError(error: CloudClientError.unauthorized)
        subject = CacheRemoteStorage(cloudClient: cloudClient)
        
        // When
        let result = subject.fetch(hash: "acho tio", userConfig: .test())
            .toBlocking()
            .materialize()
        
        // Then
        switch result {
        case .completed:
            XCTFail("Expected result to complete with error, but result was successful.")
        case .failed(_, let error):
            XCTAssertEqual(error as! CloudClientError, CloudClientError.unauthorized)
        }
    }
    
    func test_fetch_whenClientReturnsASuccess() throws {
        // Given
        let httpResponse: HTTPURLResponse = .test()
        let cacheResponse = CloudCacheResponse(url: .test(), expiresAt: 123)
        let cloudResponse = CloudResponse<CloudCacheResponse>(status: "shaki", data: cacheResponse)
        cloudClient = MockCloudClienting.makeForSuccess(object: cloudResponse, response: httpResponse)
        subject = CacheRemoteStorage(cloudClient: cloudClient)
        
        // When
        let result = try subject.fetch(hash: "acho tio", userConfig: .test())
            .toBlocking()
            .single()
        
        // Then
        XCTAssertEqual(result, AbsolutePath("/"))
    }
    
    // - store
    
    func test_store_whenClientReturnsAnError() throws {
        // Given
        let cloudClient = MockCloudClienting<CloudResponse<CloudCacheResponse>>()
        cloudClient.configureForError(error: CloudClientError.unauthorized)
        subject = CacheRemoteStorage(cloudClient: cloudClient)
        
        // When
        let result = subject.store(hash: "acho tio", userConfig: .test(), xcframeworkPath: .root)
            .toBlocking()
            .materialize()
        
        // Then
        switch result {
        case .completed:
            XCTFail("Expected result to complete with error, but result was successful.")
        case .failed(_, let error):
            XCTAssertEqual(error as! CloudClientError, CloudClientError.unauthorized)
        }
    }
    
    func test_store_whenClientReturnsASuccess() throws {
        // Given
        let httpResponse: HTTPURLResponse = .test()
        let cacheResponse = CloudCacheResponse(url: .test(), expiresAt: 123)
        let cloudResponse = CloudResponse<CloudCacheResponse>(status: "shaki", data: cacheResponse)
        cloudClient = MockCloudClienting.makeForSuccess(object: cloudResponse, response: httpResponse)
        subject = CacheRemoteStorage(cloudClient: cloudClient)
        
        // When
        _ = try subject.store(hash: "acho tio", userConfig: .test(), xcframeworkPath: .root)
            .toBlocking()
            .last()

        // Then
//        XCTAssertEqual(result, [AbsolutePath("/")])
    }
}
