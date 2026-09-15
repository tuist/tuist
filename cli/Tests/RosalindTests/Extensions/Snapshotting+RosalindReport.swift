import Foundation
import Rosalind
import SnapshotTesting
import XCTest

extension Diffing {
    fileprivate static func rosalind() -> Diffing<AppBundleReport> {
        let jsonEncoder = JSONEncoder()
        let jsonDecoder = JSONDecoder()
        jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        return Diffing<AppBundleReport>.init(toData: { value in
            try! jsonEncoder.encode(value)
        }, fromData: { data in
            try! jsonDecoder.decode(AppBundleReport.self, from: data)
        }, diff: { (lhs: AppBundleReport, rhs: AppBundleReport) -> (String, [XCTAttachment])? in
            if lhs == rhs {
                return nil
            } else {
                return Snapshotting<String, String>.json.diffing.diff(
                    try! String(decoding: jsonEncoder.encode(lhs), as: UTF8.self),
                    try! String(decoding: jsonEncoder.encode(rhs), as: UTF8.self)
                )
            }
        })
    }
}

extension Snapshotting {
    static func rosalind() -> Snapshotting<AppBundleReport, AppBundleReport> {
        Snapshotting<AppBundleReport, AppBundleReport>.init(pathExtension: nil, diffing: .rosalind())
    }
}
