//
//  ProjectModifier.swift
//  ProjectDescription
//
//  Created by Luis Padron on 1/4/22.
//

import Foundation

public protocol ProjectItem {
    func map(_ project: inout Project)
}

@resultBuilder public struct ProjectItemsBuilder {
    public static func buildBlock(_ components: ProjectItem...) -> [ProjectItem] {
        components
    }

    public static func buildBlock(_ components: Target...) -> [Target] {
        components
    }
}

// MARK: - Target Implementation

extension Target: ProjectItem {
    public func map(_ project: inout Project) {
        project.targets.append(self)
    }
}

// MARK: - Scheme Implementation

extension Scheme: ProjectItem {
    public func map(_ project: inout Project) {
        project.schemes.append(self)
    }

    public func build(
        @ProjectItemsBuilder _ targets: () -> [Target]
    ) -> SchemeBuilder {
        SchemeBuilder(scheme: self)
            .build(targets)
    }

    public func test(
        @ProjectItemsBuilder _ targets: () -> [Target]
    ) -> SchemeBuilder {
        SchemeBuilder(scheme: self)
            .test(targets)
    }
}

public struct SchemeBuilder: ProjectItem {
    var scheme: Scheme
    var targets: [Target] = []

    public func map(_ project: inout Project) {
        #warning("We should ensure these targets are unique")
        project.targets.append(contentsOf: targets)
        project.schemes.append(scheme)
    }

    public func build(
        @ProjectItemsBuilder _ builder: () -> [Target]
    ) -> Self {
        var copy = self
        copy.targets.append(contentsOf: builder())
        copy.scheme.buildAction = .buildAction(targets: builder().map { TargetReference(stringLiteral: $0.name) })
        return copy
    }

    public func test(
        @ProjectItemsBuilder _ builder: () -> [Target]
    ) -> Self {
        var copy = self
        copy.targets.append(contentsOf: builder())
        copy.scheme.testAction = .targets(builder().map { TestableTarget(target: .init(stringLiteral: $0.name)) })
        return copy
    }
}
