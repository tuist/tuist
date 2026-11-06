import Foundation
import GRPCCore
import GRPCProtobuf
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

    @Test(arguments: [false, true]) func decodesFractionalHintsFromBinaryAndUnpaddedBase64(stringEncoded: Bool) throws {
        let error = try Self.error(seconds: 5, nanos: 250_000_000, stringEncoded: stringEncoded)
        #expect(REAPIBackpressureRetryPolicy.retryInfoDelay(error) == .milliseconds(5250))
    }

    @Test func ignoresNegativeMalformedOrUnrelatedDetails() throws {
        #expect(REAPIBackpressureRetryPolicy.retryInfoDelay(try Self.error(seconds: -1)) == nil)
        #expect(REAPIBackpressureRetryPolicy.retryInfoDelay(try Self.error(seconds: 0, nanos: -1)) == nil)
        #expect(REAPIBackpressureRetryPolicy.retryInfoDelay(try Self.error(seconds: 1, statusCode: .unavailable)) == nil)
        let unrelated = GoogleRPCStatus(code: .resourceExhausted, message: "busy", details: .debugInfo(stack: [], detail: "busy"))
        #expect(REAPIBackpressureRetryPolicy.retryInfoDelay(RPCError(
            code: .resourceExhausted, message: "busy", metadata: unrelated.rpcErrorMetadata
        )) == nil)
        let malformed = GoogleRPCStatus(code: .resourceExhausted, message: "busy", details: .any(.with {
            $0.typeURL = "type.googleapis.com/google.rpc.RetryInfo"
            $0.value = Data([255])
        }))
        #expect(REAPIBackpressureRetryPolicy.retryInfoDelay(RPCError(
            code: .resourceExhausted, message: "busy", metadata: malformed.rpcErrorMetadata
        )) == nil)
        var metadata = Metadata()
        metadata.addBinary([255], forKey: "grpc-status-details-bin")
        #expect(REAPIBackpressureRetryPolicy.retryInfoDelay(RPCError(
            code: .resourceExhausted, message: "busy", metadata: metadata
        )) == nil)
    }

    @Test func sharedBudgetDoesNotOverspendOrChargeDeclinedHints() {
        let budget = REAPIUploadRetryBudget(maximumDelay: .seconds(1))
        #expect(budget.consume(.milliseconds(600)))
        #expect(!budget.consume(.milliseconds(500)))
        #expect(!budget.consume(.milliseconds(-1)))
        #expect(budget.consume(.milliseconds(400)))
        #expect(!budget.consume(.milliseconds(1)))
        #expect(!REAPIUploadRetryBudget(maximumDelay: .seconds(-1)).consume(.milliseconds(1)))
    }

    @Test func sharedBudgetIsAtomicAcrossConcurrentCalls() async {
        let budget = REAPIUploadRetryBudget(maximumDelay: .seconds(1))
        let admitted = await withTaskGroup(of: Bool.self) { group in
            for _ in 0 ..< 100 {
                group.addTask { budget.consume(.milliseconds(100)) }
            }
            var admitted = 0
            for await consumed in group where consumed {
                admitted += 1
            }
            return admitted
        }
        #expect(admitted == 10)
        #expect(!budget.consume(.milliseconds(1)))
    }

    static func error(
        seconds: Int64,
        nanos: Int32 = 0,
        statusCode: RPCError.Code = .resourceExhausted,
        stringEncoded: Bool = false
    ) throws -> RPCError {
        let status = GoogleRPCStatus(
            code: statusCode, message: "busy",
            details: .retryInfo(delay: .seconds(seconds) + .nanoseconds(Int64(nanos)))
        )
        let bytes: [UInt8] = try status.serializedBytes()
        var metadata = Metadata()
        if stringEncoded {
            metadata.addString(
                Data(bytes).base64EncodedString().replacingOccurrences(of: "=", with: ""),
                forKey: "grpc-status-details-bin"
            )
        } else {
            metadata.addBinary(bytes, forKey: "grpc-status-details-bin")
        }
        return RPCError(code: .resourceExhausted, message: "busy", metadata: metadata)
    }
}
