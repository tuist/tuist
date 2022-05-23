//
//  ResourceSynthesizers+TestData.swift
//  TuistGraphTesting
//
//  Created by Shahzad Majeed on 5/23/22.
//

import Foundation
@testable import TuistGraph

extension TuistGraph.ResourceSynthesizer {
    public static func test(
        parser: Parser = .assets,
        extensions: Set<String> = ["xcassets"],
        template: Template = .defaultTemplate("Assets")
    ) -> Self {
        ResourceSynthesizer(parser: parser, extensions: extensions, template: template)
    }
}
