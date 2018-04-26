// Reference: https://github.com/CocoaPods/Xcodeproj/blob/master/lib/xcodeproj/constants.rb
import Foundation

/// Provides default build settings for generating projects.
protocol BuildSettingsProviding: AnyObject {

    /// Returns the default project settings for any given build configuration.
    ///
    /// - Parameter config: build configuration.
    /// - Returns: build settings.
    func project(config: BuildConfiguration?) -> [String: Any]
    
    /// Returns the default target build settings.
    ///
    /// - Parameters:
    ///   - product: product.
    ///   - platform: product platform.
    ///   - config: build configuration.
    /// - Returns: default settings.
    func target(product: Product, platform: Platform, config: BuildConfiguration?) -> [String: Any]
    
    /// Returns the default build settings for a framework target.
    ///
    /// - Parameters:
    ///   - platform: framework platform.
    ///   - config: build configuration.
    /// - Returns: build settings.
    func framework(platform: Platform, config: BuildConfiguration?) -> [String: Any]
    
    /// Returns the default build settings for a library target.
    ///
    /// - Parameters:
    ///   - platform: library platform.
    ///   - config: build configuration.
    /// - Returns: build settings.
    func library(platform: Platform, config: BuildConfiguration?) -> [String: Any]
}

/// Provides default build settings for generating projects.
class BuildSettingsProvider: BuildSettingsProviding {
    
    /// Returns the default project settings for any given build configuration.
    ///
    /// - Parameter config: build configuration.
    /// - Returns: build settings.
    func project(config: BuildConfiguration?) -> [String: Any] {
        if config == .release {
            return ["DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
                    "ENABLE_NS_ASSERTIONS": "NO",
                    "MTL_ENABLE_DEBUG_INFO": "NO"]
        } else if config == .debug {
            return ["DEBUG_INFORMATION_FORMAT": "dwarf",
                    "ENABLE_TESTABILITY": "YES",
                    "GCC_DYNAMIC_NO_PIC": "NO",
                    "GCC_OPTIMIZATION_LEVEL": "0",
                    "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1", "$(inherited)"],
                    "MTL_ENABLE_DEBUG_INFO": "YES",
                    "ONLY_ACTIVE_ARCH": "YES"]
        } else {
            return ["ALWAYS_SEARCH_USER_PATHS": "NO",
                    "CLANG_ANALYZER_NONNULL": "YES",
                    "CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION": "YES_AGGRESSIVE",
                    "CLANG_CXX_LANGUAGE_STANDARD": "gnu++14",
                    "CLANG_CXX_LIBRARY": "libc++",
                    "CLANG_ENABLE_MODULES": "YES",
                    "CLANG_ENABLE_OBJC_ARC": "YES",
                    "CLANG_ENABLE_OBJC_WEAK": "YES",
                    "CLANG_WARN__DUPLICATE_METHOD_MATCH": "YES",
                    "CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING": "YES",
                    "CLANG_WARN_BOOL_CONVERSION": "YES",
                    "CLANG_WARN_COMMA": "YES",
                    "CLANG_WARN_CONSTANT_CONVERSION": "YES",
                    "CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS": "YES",
                    "CLANG_WARN_DIRECT_OBJC_ISA_USAGE": "YES_ERROR",
                    "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
                    "CLANG_WARN_EMPTY_BODY": "YES",
                    "CLANG_WARN_ENUM_CONVERSION": "YES",
                    "CLANG_WARN_INFINITE_RECURSION": "YES",
                    "CLANG_WARN_INT_CONVERSION": "YES",
                    "CLANG_WARN_NON_LITERAL_NULL_CONVERSION": "YES",
                    "CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF": "YES",
                    "CLANG_WARN_OBJC_LITERAL_CONVERSION": "YES",
                    "CLANG_WARN_OBJC_ROOT_CLASS": "YES_ERROR",
                    "CLANG_WARN_RANGE_LOOP_ANALYSIS": "YES",
                    "CLANG_WARN_STRICT_PROTOTYPES": "YES",
                    "CLANG_WARN_SUSPICIOUS_MOVE": "YES",
                    "CLANG_WARN_UNGUARDED_AVAILABILITY": "YES_AGGRESSIVE",
                    "CLANG_WARN_UNREACHABLE_CODE": "YES",
                    "COPY_PHASE_STRIP": "NO",
                    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
                    "GCC_C_LANGUAGE_STANDARD": "gnu11",
                    "GCC_NO_COMMON_BLOCKS": "YES",
                    "GCC_WARN_64_TO_32_BIT_CONVERSION": "YES",
                    "GCC_WARN_ABOUT_RETURN_TYPE": "YES_ERROR",
                    "GCC_WARN_UNDECLARED_SELECTOR": "YES",
                    "GCC_WARN_UNINITIALIZED_AUTOS": "YES_AGGRESSIVE",
                    "GCC_WARN_UNUSED_FUNCTION": "YES",
                    "GCC_WARN_UNUSED_VARIABLE": "YES",
                    "PRODUCT_NAME": "$(TARGET_NAME)"]
        }
    }
    
    
    func target(product: Product, platform: Platform, config: BuildConfiguration? = nil) -> [String: Any] {
        var settings: [String: Any] = [:]
        if platform == .ios {
            merge(into: &settings, ["SDKROOT": "iphoneos",
                                    "CODE_SIGN_IDENTITY": "iPhone Developer"])
        }
        if platform == .macos {
            merge(into: &settings, ["SDKROOT": "macosx",
                                    "CODE_SIGN_IDENTITY": "-"])
        }
        if platform == .tvos {
            merge(into: &settings, ["SDKROOT": "appletvos"])
        }
        if platform == .watchos {
            merge(into: &settings, ["SDKROOT": "watchos"])
        }
        if config == .release && platform != .macos {
            merge(into: &settings, ["VALIDATE_PRODUCT": "YES"])
        }
        if config == .debug {
            merge(into: &settings, ["SWIFT_OPTIMIZATION_LEVEL": "-Onone",
                                    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG"])
        }
        if config == .release {
            merge(into: &settings, ["SWIFT_OPTIMIZATION_LEVEL": "-Owholemodule"])
        }
        if product == .app {
            merge(into: &settings, ["ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon"])
        }
        if platform == .ios && product == .app {
            merge(into: &settings, ["LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks",
                                    "TARGETED_DEVICE_FAMILY": "1,2"])
        }
        if platform == .macos && product == .app {
            merge(into: &settings, ["COMBINE_HIDPI_IMAGES": "YES",
                                    "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/../Frameworks"])
        }
        if platform == .watchos && product == .app {
            merge(into: &settings, ["SKIP_INSTALL": "YES",
                                    "TARGETED_DEVICE_FAMILY": "4",
                                    "ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES": "YES"])
        }
        if platform == .tvos && product == .app {
            merge(into: &settings, ["ASSETCATALOG_COMPILER_APPICON_NAME": "App Icon & Top Shelf Image",
                                    "ASSETCATALOG_COMPILER_LAUNCHIMAGE_NAME": "LaunchImage",
                                    "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks",
                                    "TARGETED_DEVICE_FAMILY": "3"])
        }
        return settings
    }
    
    func framework(platform: Platform, config: BuildConfiguration?) -> [String: Any] {
        var settings: [String: Any] = [:]
        // TODO
        return settings
    }
    
    func library(platform: Platform, config: BuildConfiguration?) -> [String : Any] {
        var settings: [String: Any] = [:]
        // TODO
        return settings
    }
    
    fileprivate func merge(into: inout [String: Any], _ settings: [String: Any]) {
        settings.forEach({ into[$0.key] = $0.value })
    }
    
}


//[:framework] => {
//    'CODE_SIGN_IDENTITY' => '',
//    'CURRENT_PROJECT_VERSION'           => '1',
//    'DEFINES_MODULE'                    => 'YES',
//    'DYLIB_COMPATIBILITY_VERSION'       => '1',
//    'DYLIB_CURRENT_VERSION'             => '1',
//    'DYLIB_INSTALL_NAME_BASE'           => '@rpath',
//    'INSTALL_PATH'                      => '$(LOCAL_LIBRARY_DIR)/Frameworks',
//    'PRODUCT_NAME'                      => '$(TARGET_NAME:c99extidentifier)',
//    'SKIP_INSTALL'                      => 'YES',
//    'VERSION_INFO_PREFIX'               => '',
//    'VERSIONING_SYSTEM'                 => 'apple-generic',
//}.freeze,
//[:ios, :framework] => {
//    'LD_RUNPATH_SEARCH_PATHS'           => '$(inherited) @executable_path/Frameworks @loader_path/Frameworks',
//    'TARGETED_DEVICE_FAMILY'            => '1,2',
//}.freeze,
//[:osx, :framework] => {
//    'COMBINE_HIDPI_IMAGES'              => 'YES',
//    'FRAMEWORK_VERSION'                 => 'A',
//    'LD_RUNPATH_SEARCH_PATHS'           => '$(inherited) @executable_path/../Frameworks @loader_path/Frameworks',
//}.freeze,
//[:watchos, :framework] => {
//    'APPLICATION_EXTENSION_API_ONLY'    => 'YES',
//    'LD_RUNPATH_SEARCH_PATHS'           => '$(inherited) @executable_path/Frameworks @loader_path/Frameworks',
//    'TARGETED_DEVICE_FAMILY'            => '4',
//}.freeze,
//[:tvos, :framework] => {
//    'LD_RUNPATH_SEARCH_PATHS'           => '$(inherited) @executable_path/Frameworks @loader_path/Frameworks',
//    'TARGETED_DEVICE_FAMILY'            => '3',
//}.freeze,
//[:framework, :swift] => {
//    'DEFINES_MODULE'                    => 'YES',
//}.freeze,
//[:osx, :static_library] => {
//    'EXECUTABLE_PREFIX'                 => 'lib',
//    'SKIP_INSTALL'                      => 'YES',
//}.freeze,
//[:ios, :static_library] => {
//    'OTHER_LDFLAGS'                     => '-ObjC',
//    'SKIP_INSTALL'                      => 'YES',
//    'TARGETED_DEVICE_FAMILY'            => '1,2',
//}.freeze,
//[:watchos, :static_library] => {
//    'OTHER_LDFLAGS'                     => '-ObjC',
//    'SKIP_INSTALL'                      => 'YES',
//    'TARGETED_DEVICE_FAMILY'            => '4',
//}.freeze,
//[:tvos, :static_library] => {
//    'OTHER_LDFLAGS'                     => '-ObjC',
//    'SKIP_INSTALL'                      => 'YES',
//    'TARGETED_DEVICE_FAMILY'            => '3',
//}.freeze,
//[:osx, :dynamic_library] => {
//    'DYLIB_COMPATIBILITY_VERSION'       => '1',
//    'DYLIB_CURRENT_VERSION'             => '1',
//    'EXECUTABLE_PREFIX'                 => 'lib',
//    'SKIP_INSTALL'                      => 'YES',
//}.freeze,
