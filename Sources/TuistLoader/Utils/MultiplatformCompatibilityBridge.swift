import Foundation
import ProjectDescription

public typealias PDProject = ProjectDescription.Project
public typealias PDTarget = ProjectDescription.Target

protocol MultiplatformCompatibilityTarget {
    var sources: SourceFilesList? { get }
    var resources: ResourceFileElements? { get }
}

extension ProjectDescription.Target: MultiplatformCompatibilityTarget {}
extension ProjectDescription.Multiplatform.Target: MultiplatformCompatibilityTarget {}
