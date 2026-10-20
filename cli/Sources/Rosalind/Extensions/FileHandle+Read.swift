import Foundation

extension FileHandle {
    @_spi(Support)
    public func read<Element>(
        offset: UInt64,
        swapHandler: ((inout Data) -> Void)? = nil
    ) -> Element? {
        seek(toFileOffset: offset)
        var data = readData(
            ofLength: MemoryLayout<Element>.size
        )
        guard data.count >= MemoryLayout<Element>.size else { return nil }
        if let swapHandler { swapHandler(&data) }
        return data.withUnsafeBytes {
            $0.load(as: Element.self)
        }
    }
}
