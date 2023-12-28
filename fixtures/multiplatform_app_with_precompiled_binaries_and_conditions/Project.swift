import ProjectDescription

let appTarget = Target(
    name: "App",
    destinations: [.iPhone, .iPad, .appleWatch],
    product: .app,
    bundleId: "io.tuist.App",
    sources: "App/Sources/**",
    dependencies: [
        .library(path: "Precompiled/watchos/libwatchOSStaticLibrary.a",
                 publicHeaders: "Precompiled/watchos/",
                 swiftModuleMap: "Precompiled/watchos/watchOSStaticLibrary.swiftmodule",
                 condition: .when([.watchos])),
        .library(path: "Precompiled/watchsimulator/libwatchOSStaticLibrary.a",
                 publicHeaders: "Precompiled/watchsimulator/",
                 swiftModuleMap: "Precompiled/watchsimulator/watchOSStaticLibrary.swiftmodule",
                 condition: .when([.watchos])),
        .framework(path: "Precompiled/iphoneos/iOSDynamicFramework.framework",
                   status: .required,
                   condition: .when([.ios])),
        .framework(path: "Precompiled/iphonesimulator/iOSDynamicFramework.framework",
                   status: .required,
                   condition: .when([.ios]))
    ]
)

 let watchOSStaticLibrary = Target(
     name: "watchOSStaticLibrary",
     destinations: [.appleWatch],
     product: .staticLibrary,
     bundleId: "io.tuist.watchOSStaticLibrary",
     sources: "watchOSStaticLibrary/Sources/**"
 )

let iOSDynamicFramework = Target(
    name: "iOSDynamicFramework",
    destinations: [.iPhone],
    product: .framework,
    bundleId: "io.tuist.iOSDynamicFramework",
    sources: "iOSDynamicFramework/Sources/**"
)

let project = Project(
    name: "App",
    targets: [appTarget, watchOSStaticLibrary, iOSDynamicFramework]
)
