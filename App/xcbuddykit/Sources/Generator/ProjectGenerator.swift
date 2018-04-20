import Foundation

protocol ProjectGenerating: AnyObject {
}

final class ProjectGenerator: ProjectGenerating {
    let targetGenerator: TargetGenerating

    init(targetGenerator: TargetGenerating) {
        self.targetGenerator = targetGenerator
    }

    func generate(context _: GeneratorContexting) throws {
        // TODO:
    }
}
