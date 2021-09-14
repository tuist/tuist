//
//  FileCodeGen+ManifestMapper.swift
//  FileCodeGen+ManifestMapper
//
//  Created by Mahadevaiah, Pavan | Pavan | ECMPD on 2021/09/14.
//

import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

extension TuistGraph.FileCodeGen {
    static func from(manifest: ProjectDescription.FileCodeGen?) -> TuistGraph.FileCodeGen? {
        guard let manifest = manifest else {
            return nil
        }
        
        switch manifest {
        case .public:
            return .public
        case .private:
            return .private
        case .project:
            return .project
        case .disabled:
            return .disabled
        }
    }
}
