import Foundation

protocol Renderer {
    func render(results: [MeasureResult])
    func render(results: [BenchmarkResult])
}
