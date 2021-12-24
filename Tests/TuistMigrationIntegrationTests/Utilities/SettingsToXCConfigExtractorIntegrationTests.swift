import Foundation
import TSCBasic
import TuistSupport
import XCTest

@testable import TuistMigration
@testable import TuistSupportTesting

final class SettingsToXCConfigExtractorIntegrationTests: TuistTestCase {
    var subject: SettingsToXCConfigExtractor!

    override func setUp() {
        super.setUp()
        subject = SettingsToXCConfigExtractor()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_extract_when_target() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let xcodeprojPath = fixturePath(path: RelativePath("Frameworks/Frameworks.xcodeproj"))
        let xcconfigPath = temporaryPath.appending(component: "iOS.xcconfig")

        // When
        try subject.extract(
            xcodeprojPath: xcodeprojPath,
            targetName: "iOS",
            xcconfigPath: xcconfigPath
        )

        // Then
        let expected = """
        BUILD_LIBRARY_FOR_DISTRIBUTION=YES
        CLANG_ENABLE_MODULES=YES
        CODE_SIGN_STYLE=Automatic
        DEFINES_MODULE=YES
        DYLIB_COMPATIBILITY_VERSION=1
        DYLIB_CURRENT_VERSION=1
        DYLIB_INSTALL_NAME_BASE=@rpath
        INFOPLIST_FILE=iOS/Info.plist
        INSTALL_PATH=$(LOCAL_LIBRARY_DIR)/Frameworks
        PRODUCT_BUNDLE_IDENTIFIER=io.tuist.iOS
        PRODUCT_NAME=$(TARGET_NAME:c99extidentifier)
        SKIP_INSTALL=NO
        SWIFT_VERSION=5.0
        TARGETED_DEVICE_FAMILY=1,2
        """
        let content = try FileHandler.shared.readTextFile(xcconfigPath)
        XCTAssertTrue(content.contains(expected))
        XCTAssertPrinterOutputContains("Build settings successfully extracted into \(xcconfigPath.pathString)")
    }

    func test_extract_when_project() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let xcodeprojPath = fixturePath(path: RelativePath("Frameworks/Frameworks.xcodeproj"))
        let xcconfigPath = temporaryPath.appending(component: "Project.xcconfig")

        // When
        try subject.extract(
            xcodeprojPath: xcodeprojPath,
            targetName: nil,
            xcconfigPath: xcconfigPath
        )

        // Then
        let expected = """
        ALWAYS_SEARCH_USER_PATHS=NO
        CLANG_ANALYZER_NONNULL=YES
        CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION=YES_AGGRESSIVE
        CLANG_CXX_LANGUAGE_STANDARD=gnu++14
        CLANG_CXX_LIBRARY=libc++
        CLANG_ENABLE_MODULES=YES
        CLANG_ENABLE_OBJC_ARC=YES
        CLANG_ENABLE_OBJC_WEAK=YES
        CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING=YES
        CLANG_WARN_BOOL_CONVERSION=YES
        CLANG_WARN_COMMA=YES
        CLANG_WARN_CONSTANT_CONVERSION=YES
        CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS=YES
        CLANG_WARN_DIRECT_OBJC_ISA_USAGE=YES_ERROR
        CLANG_WARN_DOCUMENTATION_COMMENTS=YES
        CLANG_WARN_EMPTY_BODY=YES
        CLANG_WARN_ENUM_CONVERSION=YES
        CLANG_WARN_INFINITE_RECURSION=YES
        CLANG_WARN_INT_CONVERSION=YES
        CLANG_WARN_NON_LITERAL_NULL_CONVERSION=YES
        CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF=YES
        CLANG_WARN_OBJC_LITERAL_CONVERSION=YES
        CLANG_WARN_OBJC_ROOT_CLASS=YES_ERROR
        CLANG_WARN_RANGE_LOOP_ANALYSIS=YES
        CLANG_WARN_STRICT_PROTOTYPES=YES
        CLANG_WARN_SUSPICIOUS_MOVE=YES
        CLANG_WARN_UNGUARDED_AVAILABILITY=YES_AGGRESSIVE
        CLANG_WARN_UNREACHABLE_CODE=YES
        CLANG_WARN__DUPLICATE_METHOD_MATCH=YES
        COPY_PHASE_STRIP=NO
        CURRENT_PROJECT_VERSION=1
        ENABLE_STRICT_OBJC_MSGSEND=YES
        GCC_C_LANGUAGE_STANDARD=gnu11
        GCC_NO_COMMON_BLOCKS=YES
        GCC_WARN_64_TO_32_BIT_CONVERSION=YES
        GCC_WARN_ABOUT_RETURN_TYPE=YES_ERROR
        GCC_WARN_UNDECLARED_SELECTOR=YES
        GCC_WARN_UNINITIALIZED_AUTOS=YES_AGGRESSIVE
        GCC_WARN_UNUSED_FUNCTION=YES
        GCC_WARN_UNUSED_VARIABLE=YES
        IPHONEOS_DEPLOYMENT_TARGET=13.2
        MTL_FAST_MATH=YES
        SDKROOT=iphoneos
        VERSIONING_SYSTEM=apple-generic
        VERSION_INFO_PREFIX=

        DEBUG_INFORMATION_FORMAT[config=Debug]=dwarf
        DEBUG_INFORMATION_FORMAT[config=Release]=dwarf-with-dsym
        ENABLE_NS_ASSERTIONS[config=Release]=NO
        ENABLE_TESTABILITY[config=Debug]=YES
        GCC_DYNAMIC_NO_PIC[config=Debug]=NO
        GCC_OPTIMIZATION_LEVEL[config=Debug]=0
        GCC_PREPROCESSOR_DEFINITIONS[config=Debug]=DEBUG=1 $(inherited)
        MTL_ENABLE_DEBUG_INFO[config=Debug]=INCLUDE_SOURCE
        MTL_ENABLE_DEBUG_INFO[config=Release]=NO
        ONLY_ACTIVE_ARCH[config=Debug]=YES
        SWIFT_ACTIVE_COMPILATION_CONDITIONS[config=Debug]=DEBUG
        SWIFT_COMPILATION_MODE[config=Release]=wholemodule
        SWIFT_OPTIMIZATION_LEVEL[config=Debug]=-Onone
        SWIFT_OPTIMIZATION_LEVEL[config=Release]=-O
        VALIDATE_PRODUCT[config=Release]=YES
        """
        let content = try FileHandler.shared.readTextFile(xcconfigPath)
        XCTAssertTrue(content.contains(expected))
        XCTAssertPrinterOutputContains("Build settings successfully extracted into \(xcconfigPath.pathString)")
    }

    func test_extract_when_target_is_not_found() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let xcodeprojPath = fixturePath(path: RelativePath("Frameworks/Frameworks.xcodeproj"))
        let xcconfigPath = temporaryPath.appending(component: "iOS.xcconfig")

        // When
        XCTAssertThrowsSpecific(try subject.extract(
            xcodeprojPath: xcodeprojPath,
            targetName: "UnexistingTarget",
            xcconfigPath: xcconfigPath
        ), SettingsToXCConfigExtractorError.targetNotFound("UnexistingTarget"))
    }

    func test_extract_when_project_is_not_found() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let xcodeprojPath = fixturePath(path: RelativePath("NonExistingProject.xcodeproj"))
        let xcconfigPath = temporaryPath.appending(component: "Project.xcconfig")

        // When
        XCTAssertThrowsSpecific(try subject.extract(
            xcodeprojPath: xcodeprojPath,
            targetName: nil,
            xcconfigPath: xcconfigPath
        ), SettingsToXCConfigExtractorError.missingXcodeProj(xcodeprojPath))
    }
}
