import Basic
import Foundation
import xpmcore

protocol GraphJSONInitiatable {
    init(json: JSON, projectPath: AbsolutePath, fileHandler: FileHandling) throws
}
