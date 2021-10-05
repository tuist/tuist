import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

class MirrorHasher {
    let contentHashing: ContentHashing
    init(contentHashing: ContentHashing) {
        self.contentHashing = contentHashing
    }

    func hash(of target: Any) throws -> String {
        var stringsToHash = [String]()
        try calculateHashes(target, stringsToHash: &stringsToHash)
        return try contentHashing.hash(stringsToHash)
    }

    private func calculateHashes( _ value: Any, name: String? = nil, stringsToHash: inout [String]) throws {
        let mirror = Mirror(reflecting: value)
        switch (value, mirror.displayStyle) {
        case (_ as TargetDependency, _):
            // We skip this for now because of TargetDependency.project includes an AbsolutePath to the root,
            // making recalculating the hash of all its content
            break
        case (let path as AbsolutePath, _):
            try stringsToHash.append(contentHashing.hash(path: path))
        case (let data as Data, _):
            try stringsToHash.append(contentHashing.hash(data))
        case (_, .collection?),
             (_, .set?):
            let sortedChildren = mirror.children
                .sorted(by: { "\($0.value)" < "\($1.value)" })
            for child in sortedChildren {
                try calculateHashes(child.value, name: child.label, stringsToHash: &stringsToHash)
            }
        case (_, .dictionary?):
            let sortedChildren = mirror.children
                .sorted(by: {
                    let (lhsKey, _) = $0.value as! (key: Any, value: Any)
                    let (rhsKey, _) = $1.value as! (key: Any, value: Any)
                    return "\(lhsKey)" < "\(rhsKey)"
                })
            for child in sortedChildren {
                try calculateHashes(child.value, name: child.label, stringsToHash: &stringsToHash)
            }
        case (_, .struct?),
             (_, .tuple?),
             (_, .enum?):
            for child in mirror.children {
                try calculateHashes(child.value, name: child.label, stringsToHash: &stringsToHash)
            }
        case (_, .optional?):
            if let value = mirror.children.first?.value {
                try calculateHashes(value, name: nil, stringsToHash: &stringsToHash)
            }
        case (_, .class?):
            fatalError("Not Supported")
        default:
            stringsToHash.append("\(value)")
        }
        if let name = name {
            stringsToHash.append("\(name)")
        }
    }
}
