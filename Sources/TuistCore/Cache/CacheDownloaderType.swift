import Foundation

/// An enum that represents the type of downloader that the generate feature can work with.
public enum CacheDownloaderType {
    /// aria2 command-line download utility.
    /// https://github.com/aria2/aria2
    case aria2c

    /// Apple's default object to oordinates a group of related, network data transfer tasks.
    /// https://developer.apple.com/documentation/foundation/urlsession
    case urlsession
}
