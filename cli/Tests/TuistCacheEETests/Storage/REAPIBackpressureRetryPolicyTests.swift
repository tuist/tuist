import Foundation
import GRPCCore
import SwiftProtobuf
import Testing
@testable import TuistREAPI

struct REAPIBackpressureRetryPolicyTests {
    @Test func defaultsAndProgrammaticBounds() {
        let defaults = REAPIBackpressureRetryPolicy()
        #expect(defaults.maximumRetryCount == 6)
        #expect(defaults.baseDelayMilliseconds == 1000)
        #expect(defaults.maximumCumulativeDelay == .seconds(60))
        let bounded = REAPIBackpressureRetryPolicy(maximumRetryCount: Int.max, baseDelayMilliseconds: Int64.max)
        #expect(bounded.maximumRetryCount == 10)
        #expect(bounded.baseDelayMilliseconds == 30000)
        #expect(REAPIBackpressureRetryPolicy(maximumRetryCount: 0).maximumRetryCount == 0)
    }

    @Test func exponentialBackoffHasProportionalJitter() {
        let policy = REAPIBackpressureRetryPolicy()
        let error = RPCError(code: .resourceExhausted, message: "busy")
        for (retry, milliseconds) in [1000, 2000, 4000, 8000, 16000, 30000].enumerated() {
            for _ in 0 ..< 20 {
                let delay = policy.delay(for: retry, error: error)
                #expect(delay >= .milliseconds(milliseconds * 8 / 10))
                #expect(delay <= .milliseconds(milliseconds * 12 / 10))
            }
        }
        #expect(policy.delay(for: Int.max, error: error) <= .seconds(36))
    }

    @Test func honorsMinimumRetryInfoWithoutShorteningLongHints() throws {
        let policy = REAPIBackpressureRetryPolicy(baseDelayMilliseconds: 1)
        let error = try Self.error(seconds: 5)
        #expect(REAPIBackpressureRetryPolicy.retryInfoDelay(error) == .seconds(5))
        for _ in 0 ..< 20 {
            let delay = policy.delay(for: 0, error: error)
            #expect(delay >= .seconds(5))
            #expect(delay <= .seconds(6))
        }
        for seconds in [Int64(300), Int64.max] {
            let error = try Self.error(seconds: seconds)
            #expect(REAPIBackpressureRetryPolicy.retryInfoDelay(error) == .seconds(seconds))
            #expect(policy.delay(for: 0, error: error) == .seconds(seconds))
            #expect(policy.delay(for: 0, error: error) > policy.maximumCumulativeDelay)
        }
    }

    @Test func ignoresMalformedOrUnrelatedDetails() throws {
        #expect(REAPIBackpressureRetryPolicy.retryInfoDelay(try Self.error(seconds: -1)) == nil)
        #expect(REAPIBackpressureRetryPolicy.retryInfoDelay(try Self.error(seconds: 1, nanos: -1)) == nil)
        #expect(REAPIBackpressureRetryPolicy.retryInfoDelay(try Self.error(seconds: 1, nanos: 1_000_000_000)) == nil)
        #expect(REAPIBackpressureRetryPolicy.retryInfoDelay(try Self.error(seconds: 1, type: "google.rpc.Other")) == nil)
        var metadata = Metadata()
        metadata.addBinary([255], forKey: "grpc-status-details-bin")
        #expect(REAPIBackpressureRetryPolicy.retryInfoDelay(RPCError(
            code: .resourceExhausted, message: "busy", metadata: metadata
        )) == nil)
    }

    static func error(seconds: Int64, nanos: Int32 = 0, type: String = "google.rpc.RetryInfo") throws -> RPCError {
        let retry = Google_Rpc_RetryInfo.with {
            $0.retryDelay.seconds = seconds
            $0.retryDelay.nanos = nanos
        }
        let status = try Google_Rpc_Status.with {
            $0.code = 8
            $0.details = [try .with {
                $0.typeURL = "type.googleapis.com/\(type)"
                $0.value = try retry.serializedData()
            }]
        }
        var metadata = Metadata()
        metadata.addBinary(Array(try status.serializedData()), forKey: "grpc-status-details-bin")
        return RPCError(code: .resourceExhausted, message: "busy", metadata: metadata)
    }
}
