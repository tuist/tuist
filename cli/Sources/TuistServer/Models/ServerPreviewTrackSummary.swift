public struct ServerPreviewTrackSummary: Equatable, Sendable {
    public struct Track: Equatable, Sendable {
        public let name: String
        public let count: Int

        public init(name: String, count: Int) {
            self.name = name
            self.count = count
        }
    }

    public let totalCount: Int
    public let tracks: [Track]

    public init(totalCount: Int, tracks: [Track]) {
        self.totalCount = totalCount
        self.tracks = tracks
    }
}
