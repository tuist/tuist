import Foundation
import RxBlocking
import RxRelay
import RxSwift
import XCTest
@testable import TuistSupport
@testable import TuistSupportTesting

final class ObservableSystemTests: TuistUnitTestCase {
    func test_mapToString() {
        // Given
        let subject = PublishSubject<SystemEvent<Data>>()
        var got: [SystemEvent<String>] = []

        // When
        _ = subject.asObservable().mapToString().subscribe(onNext: {
            got.append($0)
        })
        subject.on(.next(.standardOutput("a".data(using: .utf8)!)))
        subject.on(.next(.standardOutput("b".data(using: .utf8)!)))

        // Then
        XCTAssertEqual(got.count, 2)
        XCTAssertEqual(got.first, .standardOutput("a"))
        XCTAssertEqual(got.last, .standardOutput("b"))
    }

    func test_collectAndMergeOutput() {
        // Given
        let subject = PublishSubject<SystemEvent<Data>>()
        var got: String = ""

        // When
        _ = subject.asObservable()
            .mapToString()
            .collectAndMergeOutput()
            .subscribe(onNext: {
                got.append($0)
            })
        subject.on(.next(.standardOutput("a\n".data(using: .utf8)!)))
        subject.on(.next(.standardOutput("b\n".data(using: .utf8)!)))
        subject.on(.completed)

        // Then
        XCTAssertEqual(got, "a\nb\n")
    }

    func test_collectOutput() {
        // Given
        let subject = PublishSubject<SystemEvent<Data>>()
        var got: SystemCollectedOutput?

        // When
        _ = subject.asObservable()
            .mapToString()
            .collectOutput()
            .subscribe(onNext: {
                got = $0
            })
        subject.on(.next(.standardOutput("a\n".data(using: .utf8)!)))
        subject.on(.next(.standardOutput("b\n".data(using: .utf8)!)))
        subject.on(.next(.standardError("c\n".data(using: .utf8)!)))
        subject.on(.next(.standardError("d\n".data(using: .utf8)!)))
        subject.on(.completed)

        // Then
        XCTAssertEqual(got?.standardOutput, "a\nb\n")
        XCTAssertEqual(got?.standardError, "c\nd\n")
    }

    func test_filterStandardOutput() {
        // Given
        let subject = PublishSubject<SystemEvent<Data>>()
        var got: [SystemEvent<String>] = []

        // When
        _ = subject.asObservable()
            .mapToString()
            .filterStandardOutput { $0.contains("a") }
            .subscribe(onNext: {
                got.append($0)
            })
        subject.on(.next(.standardOutput("a\n".data(using: .utf8)!)))
        subject.on(.next(.standardOutput("b\n".data(using: .utf8)!)))
        subject.on(.next(.standardError("d\n".data(using: .utf8)!)))
        subject.on(.completed)

        // Then
        XCTAssertEqual(got.count, 2)
        XCTAssertEqual(got.first, .standardOutput("a\n"))
        XCTAssertEqual(got.last, .standardError("d\n"))
    }

    func test_rejectStandardOutput() {
        // Given
        let subject = PublishSubject<SystemEvent<Data>>()
        var got: [SystemEvent<String>] = []

        // When
        _ = subject.asObservable()
            .mapToString()
            .rejectStandardOutput { $0.contains("a") }
            .subscribe(onNext: {
                got.append($0)
            })
        subject.on(.next(.standardOutput("a\n".data(using: .utf8)!)))
        subject.on(.next(.standardOutput("b\n".data(using: .utf8)!)))
        subject.on(.next(.standardError("d\n".data(using: .utf8)!)))
        subject.on(.completed)

        // Then
        XCTAssertEqual(got.count, 2)
        XCTAssertEqual(got.first, .standardOutput("b\n"))
        XCTAssertEqual(got.last, .standardError("d\n"))
    }

    func test_filterStandardError() {
        // Given
        let subject = PublishSubject<SystemEvent<Data>>()
        var got: [SystemEvent<String>] = []

        // When
        _ = subject.asObservable()
            .mapToString()
            .filterStandardError { $0.contains("c") }
            .subscribe(onNext: {
                got.append($0)
            })
        subject.on(.next(.standardOutput("a\n".data(using: .utf8)!)))
        subject.on(.next(.standardError("c\n".data(using: .utf8)!)))
        subject.on(.next(.standardError("d\n".data(using: .utf8)!)))
        subject.on(.completed)

        // Then
        XCTAssertEqual(got.count, 2)
        XCTAssertEqual(got.first, .standardOutput("a\n"))
        XCTAssertEqual(got.last, .standardError("c\n"))
    }

    func test_rejectStandardError() {
        // Given
        let subject = PublishSubject<SystemEvent<Data>>()
        var got: [SystemEvent<String>] = []

        // When
        _ = subject.asObservable()
            .mapToString()
            .rejectStandardError { $0.contains("c") }
            .subscribe(onNext: {
                got.append($0)
            })
        subject.on(.next(.standardOutput("a\n".data(using: .utf8)!)))
        subject.on(.next(.standardError("c\n".data(using: .utf8)!)))
        subject.on(.next(.standardError("d\n".data(using: .utf8)!)))
        subject.on(.completed)

        // Then
        XCTAssertEqual(got.count, 2)
        XCTAssertEqual(got.first, .standardOutput("a\n"))
        XCTAssertEqual(got.last, .standardError("d\n"))
    }
}
