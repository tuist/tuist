import Foundation
import TSCBasic

@testable import TuistDependencies

extension CarthageVersionFile {
    static func test(
        iOS: [Product] = [],
        macOS: [Product] = [],
        watchOS: [Product] = [],
        tvOS: [Product] = [],
        visionOS: [Product] = []
    ) -> Self {
        .init(
            iOS: iOS,
            macOS: macOS,
            watchOS: watchOS,
            tvOS: tvOS,
            visionOS: visionOS
        )
    }

    static var testAlamofire: Self {
        .init(
            iOS: [
                .init(
                    name: "Alamofire",
                    container: "Alamofire.xcframework"
                ),
                .init(
                    name: "Alamofire",
                    container: "Alamofire.xcframework"
                ),
            ],
            macOS: [
                .init(
                    name: "Alamofire",
                    container: "Alamofire.xcframework"
                ),
            ],
            watchOS: [
                .init(
                    name: "Alamofire",
                    container: "Alamofire.xcframework"
                ),
                .init(
                    name: "Alamofire",
                    container: "Alamofire.xcframework"
                ),
            ],
            tvOS: [
                .init(
                    name: "Alamofire",
                    container: "Alamofire.xcframework"
                ),
                .init(
                    name: "Alamofire",
                    container: "Alamofire.xcframework"
                ),
            ],
            visionOS: nil
        )
    }

    static var testRxSwift: Self {
        .init(
            iOS: [
                .init(
                    name: "RxBlocking",
                    container: "RxBlocking.xcframework"
                ),
                .init(
                    name: "RxBlocking",
                    container: "RxBlocking.xcframework"
                ),
                .init(
                    name: "RxCocoa",
                    container: "RxCocoa.xcframework"
                ),
                .init(
                    name: "RxCocoa",
                    container: "RxCocoa.xcframework"
                ),
                .init(
                    name: "RxRelay",
                    container: "RxRelay.xcframework"
                ),
                .init(
                    name: "RxRelay",
                    container: "RxRelay.xcframework"
                ),
                .init(
                    name: "RxSwift",
                    container: "RxSwift.xcframework"
                ),
                .init(
                    name: "RxSwift",
                    container: "RxSwift.xcframework"
                ),
                .init(
                    name: "RxTest",
                    container: "RxTest.xcframework"
                ),
                .init(
                    name: "RxTest",
                    container: "RxTest.xcframework"
                ),
            ],
            macOS: [
                .init(
                    name: "RxBlocking",
                    container: "RxBlocking.xcframework"
                ),
                .init(
                    name: "RxCocoa",
                    container: "RxCocoa.xcframework"
                ),
                .init(
                    name: "RxRelay",
                    container: "RxRelay.xcframework"
                ),
                .init(
                    name: "RxSwift",
                    container: "RxSwift.xcframework"
                ),
                .init(
                    name: "RxTest",
                    container: "RxTest.xcframework"
                ),
            ],
            watchOS: [
                .init(
                    name: "RxBlocking",
                    container: "RxBlocking.xcframework"
                ),
                .init(
                    name: "RxBlocking",
                    container: "RxBlocking.xcframework"
                ),
                .init(
                    name: "RxCocoa",
                    container: "RxCocoa.xcframework"
                ),
                .init(
                    name: "RxCocoa",
                    container: "RxCocoa.xcframework"
                ),
                .init(
                    name: "RxRelay",
                    container: "RxRelay.xcframework"
                ),
                .init(
                    name: "RxRelay",
                    container: "RxRelay.xcframework"
                ),
                .init(
                    name: "RxSwift",
                    container: "RxSwift.xcframework"
                ),
                .init(
                    name: "RxSwift",
                    container: "RxSwift.xcframework"
                ),
            ],
            tvOS: [
                .init(
                    name: "RxBlocking",
                    container: "RxBlocking.xcframework"
                ),
                .init(
                    name: "RxBlocking",
                    container: "RxBlocking.xcframework"
                ),
                .init(
                    name: "RxCocoa",
                    container: "RxCocoa.xcframework"
                ),
                .init(
                    name: "RxCocoa",
                    container: "RxCocoa.xcframework"
                ),
                .init(
                    name: "RxRelay",
                    container: "RxRelay.xcframework"
                ),
                .init(
                    name: "RxRelay",
                    container: "RxRelay.xcframework"
                ),
                .init(
                    name: "RxSwift",
                    container: "RxSwift.xcframework"
                ),
                .init(
                    name: "RxSwift",
                    container: "RxSwift.xcframework"
                ),
                .init(
                    name: "RxTest",
                    container: "RxTest.xcframework"
                ),
            ],
            visionOS: nil
        )
    }

    static var testRealmCocoa: Self {
        .init(
            iOS: [
                .init(
                    name: "Realm",
                    container: "Realm.xcframework"
                ),
                .init(
                    name: "Realm",
                    container: "Realm.xcframework"
                ),
                .init(
                    name: "RealmSwift",
                    container: "RealmSwift.xcframework"
                ),
                .init(
                    name: "RealmSwift",
                    container: "RealmSwift.xcframework"
                ),
            ],
            macOS: nil,
            watchOS: nil,
            tvOS: nil,
            visionOS: nil
        )
    }

    static var testAhoyRTC: Self {
        .init(
            iOS: [
                .init(
                    name: "AhoyKit",
                    container: nil
                ),
                .init(
                    name: "WebRTC",
                    container: nil
                ),
            ],
            macOS: [],
            watchOS: [],
            tvOS: [],
            visionOS: []
        )
    }
}

extension CarthageVersionFile {
    /// A snapshot of `.Alamofire.version` file
    /// that was generated by `Carthage` in` `0.37.0` version
    /// using `carthage bootstrap --platform iOS,macOS,tvOS,watchOS --use-xcframeworks --no-use-binaries --use-netrc --cache-builds --new-resolver` command
    static var testAlamofireJson: String {
        """
        {
          "Mac" : [
            {
              "swiftToolchainVersion" : "5.4 (swiftlang-1205.0.26.9 clang-1205.0.19.55)",
              "hash" : "57f5c800334d5f7a1c46285e1e00fd9e26abaf836dbcec92578b69403dd69596",
              "name" : "Alamofire",
              "container" : "Alamofire.xcframework",
              "identifier" : "macos-arm64_x86_64"
            }
          ],
          "watchOS" : [
            {
              "swiftToolchainVersion" : "5.4 (swiftlang-1205.0.26.9 clang-1205.0.19.55)",
              "hash" : "ce13aaa785ffa2c3c16ba88b8ab54e97bac5ba0a41a5ac22d9552a84100b07dc",
              "name" : "Alamofire",
              "container" : "Alamofire.xcframework",
              "identifier" : "watchos-arm64_i386_x86_64-simulator"
            },
            {
              "swiftToolchainVersion" : "5.4 (swiftlang-1205.0.26.9 clang-1205.0.19.55)",
              "hash" : "54293baccc33dc9f91018a4ec9253f3b17faa0c62fe3eef973835a76bc1357c9",
              "name" : "Alamofire",
              "container" : "Alamofire.xcframework",
              "identifier" : "watchos-arm64_32_armv7k"
            }
          ],
          "tvOS" : [
            {
              "swiftToolchainVersion" : "5.4 (swiftlang-1205.0.26.9 clang-1205.0.19.55)",
              "hash" : "bf2734287d14a558d4b739727ebe5f9f9a1f6ed2aeb0c5781b633b8bcac37d70",
              "name" : "Alamofire",
              "container" : "Alamofire.xcframework",
              "identifier" : "tvos-arm64"
            },
            {
              "swiftToolchainVersion" : "5.4 (swiftlang-1205.0.26.9 clang-1205.0.19.55)",
              "hash" : "0494fd475a6c62575d810bf50c8c3d09a5b3e5cc192d6f88005e45ff718bf503",
              "name" : "Alamofire",
              "container" : "Alamofire.xcframework",
              "identifier" : "tvos-arm64_x86_64-simulator"
            }
          ],
          "commitish" : "5.4.3",
          "iOS" : [
            {
              "swiftToolchainVersion" : "5.4 (swiftlang-1205.0.26.9 clang-1205.0.19.55)",
              "hash" : "5fbbffeccfee11c3d48840b59111c9483f985e01a53109e920cf60a79df743cb",
              "name" : "Alamofire",
              "container" : "Alamofire.xcframework",
              "identifier" : "ios-arm64_i386_x86_64-simulator"
            },
            {
              "swiftToolchainVersion" : "5.4 (swiftlang-1205.0.26.9 clang-1205.0.19.55)",
              "hash" : "615afccd6819b4d613bf80375d08a39b15beea9e00698b8f3a83d35fb4e7be1c",
              "name" : "Alamofire",
              "container" : "Alamofire.xcframework",
              "identifier" : "ios-arm64_armv7"
            }
          ]
        }
        """
    }

    /// A snapshot of `.RxSwift.version` file
    /// that was generated by `Carthage` in` `0.37.0` version
    /// using `carthage bootstrap --platform iOS,macOS,tvOS,watchOS --use-xcframeworks --no-use-binaries --use-netrc --cache-builds --new-resolver` command
    static var testRxSwiftJson: String {
        """
        {
          "Mac" : [
            {
              "swiftToolchainVersion" : "5.4 (swiftlang-1205.0.26.9 clang-1205.0.19.55)",
              "hash" : "86b1f3a3476db7b35180336876c2731a49b546899d647ab99d52909a6635c883",
              "name" : "RxBlocking",
              "container" : "RxBlocking.xcframework",
              "identifier" : "macos-arm64_x86_64"
            },
            {
              "swiftToolchainVersion" : "5.4 (swiftlang-1205.0.26.9 clang-1205.0.19.55)",
              "hash" : "f7b73b8a44fd2992b330e6c9d044be3873aa9195cb98990dd041abc86622b359",
              "name" : "RxCocoa",
              "container" : "RxCocoa.xcframework",
              "identifier" : "macos-arm64_x86_64"
            },
            {
              "swiftToolchainVersion" : "5.4 (swiftlang-1205.0.26.9 clang-1205.0.19.55)",
              "hash" : "55ce7c5d0f4fe9df7a609d23174dd4ae62a66333f30051d880285f58967ef415",
              "name" : "RxRelay",
              "container" : "RxRelay.xcframework",
              "identifier" : "macos-arm64_x86_64"
            },
            {
              "swiftToolchainVersion" : "5.4 (swiftlang-1205.0.26.9 clang-1205.0.19.55)",
              "hash" : "a9ff6e3d6213ea912c3136173af678bd4bb1840057ce88c0b451b30962ccb0bd",
              "name" : "RxSwift",
              "container" : "RxSwift.xcframework",
              "identifier" : "macos-arm64_x86_64"
            },
            {
              "swiftToolchainVersion" : "5.4 (swiftlang-1205.0.26.9 clang-1205.0.19.55)",
              "hash" : "3a81b7ea565c01a2663cb3d970bc8411c13f43c092bdb515432d49fc12ea3c72",
              "name" : "RxTest",
              "container" : "RxTest.xcframework",
              "identifier" : "macos-arm64_x86_64"
            }
          ],
          "watchOS" : [
            {
              "swiftToolchainVersion" : "5.4 (swiftlang-1205.0.26.9 clang-1205.0.19.55)",
              "hash" : "fa387e94a430ae1a2185b00d2e71d7c837adf11646ba036fa0800b08ed3db154",
              "name" : "RxBlocking",
              "container" : "RxBlocking.xcframework",
              "identifier" : "watchos-arm64_i386_x86_64-simulator"
            },
            {
              "swiftToolchainVersion" : "5.4 (swiftlang-1205.0.26.9 clang-1205.0.19.55)",
              "hash" : "c6c6e1483df5fa04a8192c1bd4a3eb9f8d2db46d4b77659aa05e0102548c072d",
              "name" : "RxBlocking",
              "container" : "RxBlocking.xcframework",
              "identifier" : "watchos-arm64_32_armv7k"
            },
            {
              "swiftToolchainVersion" : "5.4 (swiftlang-1205.0.26.9 clang-1205.0.19.55)",
              "hash" : "e614a6a4c2cfb6547753381d3638302e8955ad21893cb5d2f6e07b46946dbe36",
              "name" : "RxCocoa",
              "container" : "RxCocoa.xcframework",
              "identifier" : "watchos-arm64_i386_x86_64-simulator"
            },
            {
              "swiftToolchainVersion" : "5.4 (swiftlang-1205.0.26.9 clang-1205.0.19.55)",
              "hash" : "69ffb2f2502a30e7b4bcd5258fd39b97fdc9c81a2e9e49d8770703dd4c07e0ee",
              "name" : "RxCocoa",
              "container" : "RxCocoa.xcframework",
              "identifier" : "watchos-arm64_32_armv7k"
            },
            {
              "swiftToolchainVersion" : "5.4 (swiftlang-1205.0.26.9 clang-1205.0.19.55)",
              "hash" : "79091465303a53417f13caa34c6f5c16713d1888f2c7620a2790574d772bc6c2",
              "name" : "RxRelay",
              "container" : "RxRelay.xcframework",
              "identifier" : "watchos-arm64_32_armv7k"
            },
            {
              "swiftToolchainVersion" : "5.4 (swiftlang-1205.0.26.9 clang-1205.0.19.55)",
              "hash" : "d9c5f13754933b994beaded1c5ff0edde45efb86ca13aebc08bae7e567727c18",
              "name" : "RxRelay",
              "container" : "RxRelay.xcframework",
              "identifier" : "watchos-arm64_i386_x86_64-simulator"
            },
            {
              "swiftToolchainVersion" : "5.4 (swiftlang-1205.0.26.9 clang-1205.0.19.55)",
              "hash" : "2cb6d5c3c02b778610b0ce1d8af2ff5f69fca80cf2c6382da4f14fb936735689",
              "name" : "RxSwift",
              "container" : "RxSwift.xcframework",
              "identifier" : "watchos-arm64_i386_x86_64-simulator"
            },
            {
              "swiftToolchainVersion" : "5.4 (swiftlang-1205.0.26.9 clang-1205.0.19.55)",
              "hash" : "f65a096e38c6940c1b1fdbc5c24f11e8d8af9cafb219723b1e4e2041da6c81c0",
              "name" : "RxSwift",
              "container" : "RxSwift.xcframework",
              "identifier" : "watchos-arm64_32_armv7k"
            }
          ],
          "tvOS" : [
            {
              "swiftToolchainVersion" : "5.4 (swiftlang-1205.0.26.9 clang-1205.0.19.55)",
              "hash" : "acc2a71bb7bc9c27a0ec95385f048a0040d88bab44deddcb9a1a3b61320c4e6f",
              "name" : "RxBlocking",
              "container" : "RxBlocking.xcframework",
              "identifier" : "tvos-arm64"
            },
            {
              "swiftToolchainVersion" : "5.4 (swiftlang-1205.0.26.9 clang-1205.0.19.55)",
              "hash" : "12c36aea3712976f34d25e0337ba8f6393b76ecfc3e1351a2ab3023c99018b33",
              "name" : "RxBlocking",
              "container" : "RxBlocking.xcframework",
              "identifier" : "tvos-arm64_x86_64-simulator"
            },
            {
              "swiftToolchainVersion" : "5.4 (swiftlang-1205.0.26.9 clang-1205.0.19.55)",
              "hash" : "4420a6279e55e2c5c3f4b6aa7567eda56aa81a162315b028d6ac7b5689266ef3",
              "name" : "RxCocoa",
              "container" : "RxCocoa.xcframework",
              "identifier" : "tvos-arm64_x86_64-simulator"
            },
            {
              "swiftToolchainVersion" : "5.4 (swiftlang-1205.0.26.9 clang-1205.0.19.55)",
              "hash" : "a4f7428701da909fb88bdcda602f1a9d1526de20914702dc1519565aa41135eb",
              "name" : "RxCocoa",
              "container" : "RxCocoa.xcframework",
              "identifier" : "tvos-arm64"
            },
            {
              "swiftToolchainVersion" : "5.4 (swiftlang-1205.0.26.9 clang-1205.0.19.55)",
              "hash" : "c312b7732b52838109e93404db33a8693a5f86384c6de054d7878bd98f64f780",
              "name" : "RxRelay",
              "container" : "RxRelay.xcframework",
              "identifier" : "tvos-arm64"
            },
            {
              "swiftToolchainVersion" : "5.4 (swiftlang-1205.0.26.9 clang-1205.0.19.55)",
              "hash" : "b73a59d4a73bfdffb3c382588ee48fc74a3d0c5f4fe87242a0588a597ac289d0",
              "name" : "RxRelay",
              "container" : "RxRelay.xcframework",
              "identifier" : "tvos-arm64_x86_64-simulator"
            },
            {
              "swiftToolchainVersion" : "5.4 (swiftlang-1205.0.26.9 clang-1205.0.19.55)",
              "hash" : "e4d95e41cdc6a5e624f1dfc649935a93e6f9eb6a979ace621a8afbd4e9ea6389",
              "name" : "RxSwift",
              "container" : "RxSwift.xcframework",
              "identifier" : "tvos-arm64_x86_64-simulator"
            },
            {
              "swiftToolchainVersion" : "5.4 (swiftlang-1205.0.26.9 clang-1205.0.19.55)",
              "hash" : "9665ba98bde33d0fb8e77d0f70a2950421104b555942375d15515d6c63585eac",
              "name" : "RxSwift",
              "container" : "RxSwift.xcframework",
              "identifier" : "tvos-arm64"
            },
            {
              "swiftToolchainVersion" : "5.4 (swiftlang-1205.0.26.9 clang-1205.0.19.55)",
              "hash" : "6e281b30953f1c8db38d9f1652926e3466188a633cd16bf74339715d931759ec",
              "name" : "RxTest",
              "container" : "RxTest.xcframework",
              "identifier" : "tvos-arm64_x86_64-simulator"
            }
          ],
          "commitish" : "6.2.0",
          "iOS" : [
            {
              "swiftToolchainVersion" : "5.4 (swiftlang-1205.0.26.9 clang-1205.0.19.55)",
              "hash" : "5cb314834422a56915d9404d12e072600665eeba5815b89ca547032eaa7b372e",
              "name" : "RxBlocking",
              "container" : "RxBlocking.xcframework",
              "identifier" : "ios-arm64_i386_x86_64-simulator"
            },
            {
              "swiftToolchainVersion" : "5.4 (swiftlang-1205.0.26.9 clang-1205.0.19.55)",
              "hash" : "4ed2e9c1871c5338a481fa0b73cf7a71e92ded5f7477292e116742c543431101",
              "name" : "RxBlocking",
              "container" : "RxBlocking.xcframework",
              "identifier" : "ios-arm64_armv7"
            },
            {
              "swiftToolchainVersion" : "5.4 (swiftlang-1205.0.26.9 clang-1205.0.19.55)",
              "hash" : "5c1719d1c61658eddba8809440b809fb23ab64e24f196db24797627683fd5485",
              "name" : "RxCocoa",
              "container" : "RxCocoa.xcframework",
              "identifier" : "ios-arm64_i386_x86_64-simulator"
            },
            {
              "swiftToolchainVersion" : "5.4 (swiftlang-1205.0.26.9 clang-1205.0.19.55)",
              "hash" : "c3492a3348d7a20396c185dbee479fa19f601b77f0f627608ff67cc029e06e3c",
              "name" : "RxCocoa",
              "container" : "RxCocoa.xcframework",
              "identifier" : "ios-arm64_armv7"
            },
            {
              "swiftToolchainVersion" : "5.4 (swiftlang-1205.0.26.9 clang-1205.0.19.55)",
              "hash" : "3725a226c968c7331363377e4e4e2d8b218ae27391ea815263c840e5a66da76a",
              "name" : "RxRelay",
              "container" : "RxRelay.xcframework",
              "identifier" : "ios-arm64_i386_x86_64-simulator"
            },
            {
              "swiftToolchainVersion" : "5.4 (swiftlang-1205.0.26.9 clang-1205.0.19.55)",
              "hash" : "4dbc43707ed1bde34abec38f4cf1e903604a20dcd4937130e27922ad6f98caac",
              "name" : "RxRelay",
              "container" : "RxRelay.xcframework",
              "identifier" : "ios-arm64_armv7"
            },
            {
              "swiftToolchainVersion" : "5.4 (swiftlang-1205.0.26.9 clang-1205.0.19.55)",
              "hash" : "d2e8ba83ea1e99dc8a22fcc94650e6d8f915293fd811ef1d9a34a3ccb84d4d93",
              "name" : "RxSwift",
              "container" : "RxSwift.xcframework",
              "identifier" : "ios-arm64_i386_x86_64-simulator"
            },
            {
              "swiftToolchainVersion" : "5.4 (swiftlang-1205.0.26.9 clang-1205.0.19.55)",
              "hash" : "0c2f64086afd5835576d820cd9671b42659a7612afb42d44149757b93d39119c",
              "name" : "RxSwift",
              "container" : "RxSwift.xcframework",
              "identifier" : "ios-arm64_armv7"
            },
            {
              "swiftToolchainVersion" : "5.4 (swiftlang-1205.0.26.9 clang-1205.0.19.55)",
              "hash" : "8a2f2e875b174a68c1330791d12e65119f912ad660fd08c14c831a9e6ecd7cfb",
              "name" : "RxTest",
              "container" : "RxTest.xcframework",
              "identifier" : "ios-arm64_armv7"
            },
            {
              "swiftToolchainVersion" : "5.4 (swiftlang-1205.0.26.9 clang-1205.0.19.55)",
              "hash" : "6b863d8e43e0831195b03fc0bcb8f84d7d652b0565966f9a890839c45365bf61",
              "name" : "RxTest",
              "container" : "RxTest.xcframework",
              "identifier" : "ios-arm64_i386_x86_64-simulator"
            }
          ]
        }
        """
    }

    /// A snapshot of `.realm-cocoa.version` file
    /// that was generated by `Carthage` in` `0.37.0` version
    /// using `carthage bootstrap --platform iOS --use-xcframeworks --no-use-binaries --use-netrc --cache-builds --new-resolver` command
    static var testRealmCocoaJson: String {
        """
        {
          "commitish" : "v10.7.6",
          "iOS" : [
            {
              "hash" : "acf910bcb59a82ea4d5c5ecd8358ed4c8438ec4052374e36421bf2c7863a7c51",
              "name" : "Realm",
              "container" : "Realm.xcframework",
              "identifier" : "ios-i386_x86_64-simulator"
            },
            {
              "hash" : "eca5d0e7fd94e459b73c2d80d35dbbb198cdc460bb656d5912a34e04c4dad45d",
              "name" : "Realm",
              "container" : "Realm.xcframework",
              "identifier" : "ios-arm64_armv7"
            },
            {
              "swiftToolchainVersion" : "5.4 (swiftlang-1205.0.26.9 clang-1205.0.19.55)",
              "hash" : "31c09fb27b44ed77915be0cab1e9364570d806f0cf2b7f962c94488c51f20d29",
              "name" : "RealmSwift",
              "container" : "RealmSwift.xcframework",
              "identifier" : "ios-i386_x86_64-simulator"
            },
            {
              "swiftToolchainVersion" : "5.4 (swiftlang-1205.0.26.9 clang-1205.0.19.55)",
              "hash" : "8b749ef640129c1c56aac21d71c1358ddfc2e27d465e500cce048c1d19131425",
              "name" : "RealmSwift",
              "container" : "RealmSwift.xcframework",
              "identifier" : "ios-arm64_armv7"
            }
          ]
        }
        """
    }

    /// A snapshot of `.CarthageAhoyRTC-bitcode.version` file
    /// that was generated by `Carthage` in` `0.37.0` version
    /// using `carthage bootstrap --platform iOS --use-xcframeworks --no-use-binaries --use-netrc --cache-builds --new-resolver` command
    static var testAhoyRTCJson: String {
        """
        {
          "Mac" : [

          ],
          "watchOS" : [

          ],
          "tvOS" : [

          ],
          "commitish" : "2.1",
          "iOS" : [
            {
              "name" : "AhoyKit",
              "hash" : "c963ec94999f3fe64f75880ba394338d5c694a5cec8f756bc35481f3b8c8b4d2",
              "linking" : "dynamic"
            },
            {
              "name" : "WebRTC",
              "hash" : "3a9ced64f6f8ccca46dc0038bdbf3efd8cf98f73cbc29ee1b00d98757b7fab33",
              "linking" : "dynamic"
            }
          ],
          "visionOS": [

          ]
        }
        """
    }
}

extension CarthageVersionFile.Product {
    static func test(
        name: String = "",
        container: String? = ""
    ) -> Self {
        .init(
            name: name,
            container: container
        )
    }
}
