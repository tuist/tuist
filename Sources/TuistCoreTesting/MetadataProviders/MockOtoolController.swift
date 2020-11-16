//
//  File.swift
//  
//
//  Created by Facundo Menzella on 16/11/2020.
//

import Foundation
import TSCBasic
@testable import TuistCore

final class MockOtoolController: OtoolControlling {

    var dlybDependenciesPathStub: ((AbsolutePath) -> [String])?

    func dlybDependenciesPath(forBinaryAt path: AbsolutePath) throws -> [String] {
        return dlybDependenciesPathStub?(path) ?? []
    }

}
