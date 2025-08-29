extension Tuist {
    /// Options for caching.
    public struct CacheOptions: Codable, Equatable, Sendable {
        
        public struct DownloadOptions: Codable, Equatable, Sendable {
            public var chunked: Bool
            
            /// When chunking the downloads, the size of each chunk in bytes.
            public var chunkSize: Int
            
            /// The maximum of concurrent downloads.
            public var concurrencyLimit: Int?
            
            /// It instantiates the options to configure the cache download.
            /// - Parameters:
            ///   - chunked: When true, it downloads every cache artifact in chunks. With large files or unreliable network connections, small chunks can improve the resilience of the cache improving the user experience. By default they are not chunked.
            ///   - chunkSize: The size of each chunk. The default value is 8 MB.
            ///   - concurrencyLimit: The maximum of concurrent downloads.
            /// - Returns: Download options.
            public static func options(chunked: Bool = false,
                                       chunkSize: Int = 2 * 1024 * 1024,
                                       concurrencyLimit: Int? = 20) -> Self {
                return Self(chunked: chunked,
                            chunkSize: chunkSize,
                            concurrencyLimit: concurrencyLimit)
            }
        }
        
        public var keepSourceTargets: Bool
        public var downloadOptions: DownloadOptions
        
        public static func options(
            keepSourceTargets: Bool = false,
            downloadOptions: DownloadOptions = .options()
        ) -> Self {
            self.init(
                keepSourceTargets: keepSourceTargets,
                downloadOptions: downloadOptions
            )
        }
    }
}
