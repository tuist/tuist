import FileSystem
import Path
import TuistCore

struct StaleGeneratedFilesCleaner {
    private let fileSystem: FileSysteming

    init(fileSystem: FileSysteming = FileSystem()) {
        self.fileSystem = fileSystem
    }

    func sideEffects(
        for directories: Set<AbsolutePath>,
        activeFilesByDirectory: [AbsolutePath: Set<AbsolutePath>]
    ) async throws -> [SideEffectDescriptor] {
        var sideEffects: [SideEffectDescriptor] = []
        for directory in directories.sorted(by: { $0.pathString < $1.pathString }) {
            guard try await fileSystem.exists(directory) else { continue }

            let activeFiles = activeFilesByDirectory[directory] ?? []
            guard !activeFiles.isEmpty else {
                sideEffects.append(.directory(.init(path: directory, state: .absent)))
                continue
            }

            let contents = try await fileSystem.glob(directory: directory, include: ["*"]).collect()
            for item in contents where !activeFiles.contains(item) {
                if try await fileSystem.exists(item, isDirectory: true) {
                    sideEffects.append(.directory(.init(path: item, state: .absent)))
                } else {
                    sideEffects.append(.file(.init(path: item, state: .absent)))
                }
            }
        }

        return sideEffects
    }
}
