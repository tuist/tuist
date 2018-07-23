import Basic
import Foundation
import TuistCore

protocol GraphJSONInitiatable {
    init(json: JSON, projectPath: AbsolutePath, fileHandler: FileHandling) throws
}
