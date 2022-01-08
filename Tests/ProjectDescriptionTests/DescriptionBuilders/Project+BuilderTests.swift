//
//  Project+BuilderTests.swift
//  ProjectDescriptionTests
//
//  Created by Luis Padron on 1/4/22.
//

import Foundation
import XCTest

@testable import ProjectDescription

final class ProjectBuilderTests: XCTestCase {
    func test_targets_and_scheme() {
        let project = Project(name: "MyProject") {
            Target(
                name: "TargetA",
                platform: .iOS,
                product: .framework,
                bundleId: "com.tuist.Target"
            )

            Scheme(name: "SchemeA")
                .build {
                    Target(
                        name: "TargetB",
                        platform: .iOS,
                        product: .framework,
                        bundleId: "com.tuist.Target"
                    )
                }
                .test {
                    Target(
                        name: "TestTarget",
                        platform: .iOS,
                        product: .unitTests,
                        bundleId: "com.tuist.Target"
                    )
                }
        }

        XCTAssertEqual(project.name, "MyProject")
        XCTAssertEqual(project.targets, [
            Target(
                name: "TargetA",
                platform: .iOS,
                product: .framework,
                bundleId: "com.tuist.Target"
            ),
            Target(
                name: "TargetB",
                platform: .iOS,
                product: .framework,
                bundleId: "com.tuist.Target"
            ),
            Target(
                name: "TestTarget",
                platform: .iOS,
                product: .unitTests,
                bundleId: "com.tuist.Target"
            )
        ])
        XCTAssertEqual(project.schemes, [
            Scheme(
                name: "SchemeA",
                buildAction: .init(targets: ["TargetB"]),
                testAction: .targets(["TestTarget"])
            )
        ])
    }
}
