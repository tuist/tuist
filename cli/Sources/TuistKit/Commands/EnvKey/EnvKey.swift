import ArgumentParser
import Foundation
import TuistSupport

public enum EnvKey: String, CaseIterable {
    // BUILD

    case buildBinaryCache = "TUIST_BUILD_BINARY_CACHE"

    // BUILD OPTIONS

    case buildOptionsScheme = "TUIST_BUILD_OPTIONS_SCHEME"
    case buildOptionsGenerate = "TUIST_BUILD_OPTIONS_GENERATE"
    case buildOptionsClean = "TUIST_BUILD_OPTIONS_CLEAN"
    case buildOptionsPath = "TUIST_BUILD_OPTIONS_PATH"
    case buildOptionsDevice = "TUIST_BUILD_OPTIONS_DEVICE"
    case buildOptionsPlatform = "TUIST_BUILD_OPTIONS_PLATFORM"
    case buildOptionsOS = "TUIST_BUILD_OPTIONS_OS"
    case buildOptionsRosetta = "TUIST_BUILD_OPTIONS_ROSETTA"
    case buildOptionsConfiguration = "TUIST_BUILD_OPTIONS_CONFIGURATION"
    case buildOptionsOutputPath = "TUIST_BUILD_OPTIONS_BUILD_OUTPUT_PATH"
    case buildOptionsDerivedDataPath = "TUIST_BUILD_OPTIONS_DERIVED_DATA_PATH"
    case buildOptionsGenerateOnly = "TUIST_BUILD_OPTIONS_GENERATE_ONLY"
    case buildOptionsPassthroughXcodeBuildArguments = "TUIST_BUILD_OPTIONS_PASSTHROUGH_XCODE_BUILD_ARGUMENTS"

    // CLEAN

    case cleanCleanCategories = "TUIST_CLEAN_CLEAN_CATEGORIES"
    case cleanPath = "TUIST_CLEAN_PATH"
    case cleanRemote = "TUIST_CLEAN_REMOTE"

    // DUMP

    case dumpPath = "TUIST_DUMP_PATH"
    case dumpManifest = "TUIST_DUMP_MANIFEST"

    // EDIT

    case editPath = "TUIST_EDIT_PATH"
    case editPermanent = "TUIST_EDIT_PERMANENT"
    case editOnlyCurrentDirectory = "TUIST_EDIT_ONLY_CURRENT_DIRECTORY"

    // INSTALL

    case installPath = "TUIST_INSTALL_PATH"
    case installUpdate = "TUIST_INSTALL_UPDATE"
    case installPassthroughArguments = "TUIST_INSTALL_PASSTHROUGH_ARGUMENTS"

    // GENERATE

    case generatePath = "TUIST_GENERATE_PATH"
    case generateOpen = "TUIST_GENERATE_OPEN"
    case generateBinaryCache = "TUIST_GENERATE_BINARY_CACHE"
    case generateCacheProfile = "TUIST_GENERATE_CACHE_PROFILE"

    // GRAPH

    case graphSkipTestTargets = "TUIST_GRAPH_SKIP_TEST_TARGETS"
    case graphSkipExternalDependencies = "TUIST_GRAPH_SKIP_EXTERNAL_DEPENDENCIES"
    case graphPlatform = "TUIST_GRAPH_PLATFORM"
    case graphFormat = "TUIST_GRAPH_FORMAT"
    case graphOpen = "TUIST_GRAPH_OPEN"
    case graphLayoutAlgorithm = "TUIST_GRAPH_LAYOUT_ALGORITHM"
    case graphTargets = "TUIST_GRAPH_TARGETS"
    case graphPath = "TUIST_GRAPH_PATH"
    case graphOutputPath = "TUIST_GRAPH_OUTPUT_PATH"

    // INIT

    case initPlatform = "TUIST_INIT_PLATFORM"
    case initName = "TUIST_INIT_NAME"
    case initTemplate = "TUIST_INIT_TEMPLATE"
    case initPath = "TUIST_INIT_PATH"
    case initAnswers = "TUIST_INIT_ANSWERS"

    // MIGRATION

    case migrationSettingsToXcconfigXcodeprojPath = "TUIST_MIGRATION_SETTINGS_TO_XCCONFIG_XCODEPROJ_PATH"
    case migrationSettingsToXcconfigXcconfigPath = "TUIST_MIGRATION_SETTINGS_TO_XCCONFIG_XCCONFIG_PATH"
    case migrationSettingsToXcconfigTarget = "TUIST_MIGRATION_SETTINGS_TO_XCCONFIG_TARGET"
    case migrationCheckEmptySettingsXcodeprojPath = "TUIST_MIGRATION_CHECK_EMPTY_SETTINGS_XCODEPROJ_PATH"
    case migrationCheckEmptySettingsTarget = "TUIST_MIGRATION_CHECK_EMPTY_SETTINGS_TARGET"
    case migrationListTargetsXcodeprojPath = "TUIST_MIGRATION_LIST_TARGETS_XCODEPROJ_PATH"

    // PLUGIN

    case pluginArchivePath = "TUIST_PLUGIN_ARCHIVE_PATH"
    case pluginBuildBuildTests = "TUIST_PLUGIN_BUILD_BUILD_TESTS"
    case pluginBuildShowBinPath = "TUIST_PLUGIN_BUILD_SHOW_BIN_PATH"
    case pluginBuildTargets = "TUIST_PLUGIN_BUILD_TARGETS"
    case pluginBuildProducts = "TUIST_PLUGIN_BUILD_PRODUCTS"
    case pluginRunBuildTests = "TUIST_PLUGIN_RUN_BUILD_TESTS"
    case pluginRunSkipBuild = "TUIST_PLUGIN_RUN_SKIP_BUILD"
    case pluginRunTask = "TUIST_PLUGIN_RUN_TASK"
    case pluginRunArguments = "TUIST_PLUGIN_RUN_ARGUMENTS"
    case pluginTestBuildTests = "TUIST_PLUGIN_TEST_BUILD_TESTS"
    case pluginTestTestProducts = "TUIST_PLUGIN_TEST_TEST_PRODUCTS"

    // PLUGIN OPTIONS

    case pluginOptionsConfiguration = "TUIST_PLUGIN_OPTIONS_CONFIGURATION"
    case pluginOptionsPath = "TUIST_PLUGIN_OPTIONS_PATH"

    // LINT

    case lintImplicitDependenciesPath = "TUIST_LINT_IMPLICIT_DEPENDENCIES_PATH"

    // Redundant

    case lintRedundantDependenciesPath = "TUIST_LINT_REDUNDANT_DEPENDENCIES_PATH"

    // INSPECT BUILD

    case inspectBuildPath = "TUIST_INSPECT_BUILD_PATH"
    case inspectBuildDerivedDataPath = "TUIST_INSPECT_BUILD_DERIVED_DATA_PATH"

    // INSPECT BUNDLE

    case inspectBundle = "TUIST_INSPECT_BUNDLE"
    case inspectBundleJSON = "TUIST_INSPECT_BUNDLE_JSON"
    case inspectBundlePath = "TUIST_INSPECT_BUNDLE_PATH"

    // INSPECT TEST

    case inspectTestPath = "TUIST_INSPECT_TEST_PATH"
    case inspectTestDerivedDataPath = "TUIST_INSPECT_TEST_DERIVED_DATA_PATH"
    case inspectTestResultBundlePath = "TUIST_INSPECT_TEST_RESULT_BUNDLE_PATH"

    // RUN

    case runBuildTests = "TUIST_RUN_BUILD_TESTS"
    case runSkipBuild = "TUIST_RUN_SKIP_BUILD"
    case runTask = "TUIST_RUN_TASK"
    case runArguments = "TUIST_RUN_ARGUMENTS"
    case runGenerate = "TUIST_RUN_GENERATE"
    case runClean = "TUIST_RUN_CLEAN"
    case runPath = "TUIST_RUN_PATH"
    case runConfiguration = "TUIST_RUN_CONFIGURATION"
    case runDevice = "TUIST_RUN_DEVICE"
    case runOS = "TUIST_RUN_OS"
    case runRosetta = "TUIST_RUN_ROSETTA"
    case runScheme = "TUIST_RUN_SCHEME"

    // SCAFFOLD

    case scaffoldTemplate = "TUIST_SCAFFOLD_TEMPLATE"
    case scaffoldJson = "TUIST_SCAFFOLD_JSON"
    case scaffoldPath = "TUIST_SCAFFOLD_PATH"
    case scaffoldListJson = "TUIST_SCAFFOLD_LIST_JSON"
    case scaffoldListPath = "TUIST_SCAFFOLD_LIST_PATH"

    // TEST

    case testScheme = "TUIST_TEST_SCHEME"
    case testClean = "TUIST_TEST_CLEAN"
    case testNoUpload = "TUIST_TEST_NO_UPLOAD"
    case testPath = "TUIST_TEST_PATH"
    case testDevice = "TUIST_TEST_DEVICE"
    case testPlatform = "TUIST_TEST_PLATFORM"
    case testOS = "TUIST_TEST_OS"
    case testRosetta = "TUIST_TEST_ROSETTA"
    case testConfiguration = "TUIST_TEST_CONFIGURATION"
    case testSkipUITests = "TUIST_TEST_SKIP_UITESTS"
    case testSkipUnitTests = "TUIST_TEST_SKIP_UNITTESTS"
    case testResultBundlePath = "TUIST_TEST_RESULT_BUNDLE_PATH"
    case testDerivedDataPath = "TUIST_TEST_DERIVED_DATA_PATH"
    case testRetryCount = "TUIST_TEST_RETRY_COUNT"
    case testTestPlan = "TUIST_TEST_TEST_PLAN"
    case testTestTargets = "TUIST_TEST_TEST_TARGETS"
    case testSkipTestTargets = "TUIST_TEST_SKIP_TEST_TARGETS"
    case testConfigurations = "TUIST_TEST_CONFIGURATIONS"
    case testSkipConfigurations = "TUIST_TEST_SKIP_CONFIGURATIONS"
    case testGenerateOnly = "TUIST_TEST_GENERATE_ONLY"
    case testBinaryCache = "TUIST_TEST_BINARY_CACHE"
    case testSelectiveTesting = "TUIST_TEST_SELECTIVE_TESTING"
    case testWithoutBuilding = "TUIST_TEST_WITHOUT_BUILDING"
    case testBuildOnly = "TUIST_TEST_BUILD_ONLY"

    // ORGANIZATION BILLING

    case organizationBillingOrganizationName = "TUIST_ORGANIZATION_BILLING_ORGANIZATION_NAME"
    case organizationBillingPath = "TUIST_ORGANIZATION_BILLING_PATH"

    // ORGANIZATION CREATE

    case organizationCreateOrganizationName = "TUIST_ORGANIZATION_CREATE_ORGANIZATION_NAME"
    case organizationCreatePath = "TUIST_ORGANIZATION_CREATE_PATH"

    // ORGANIZATION DELETE

    case organizationDeleteOrganizationName = "TUIST_ORGANIZATION_DELETE_ORGANIZATION_NAME"
    case organizationDeletePath = "TUIST_ORGANIZATION_DELETE_PATH"

    // PROJECT TOKEN

    case projectTokenFullHandle = "TUIST_PROJECT_TOKEN_FULL_HANDLE"
    case projectTokenPath = "TUIST_PROJECT_TOKEN_PATH"
    case projectTokenId = "TUIST_PROJECT_TOKEN_ID"

    // ACCOUNT TOKENS

    case accountTokensAccountHandle = "TUIST_ACCOUNT_TOKENS_ACCOUNT_HANDLE"
    case accountTokensPath = "TUIST_ACCOUNT_TOKENS_PATH"
    case accountTokensName = "TUIST_ACCOUNT_TOKENS_NAME"
    case accountTokensScopes = "TUIST_ACCOUNT_TOKENS_SCOPES"
    case accountTokensExpires = "TUIST_ACCOUNT_TOKENS_EXPIRES"
    case accountTokensProjects = "TUIST_ACCOUNT_TOKENS_PROJECTS"

    // ORGANIZATION LIST

    case organizationListJson = "TUIST_ORGANIZATION_LIST_JSON"
    case organizationListPath = "TUIST_ORGANIZATION_LIST_PATH"

    // ORGANIZATION REMOVE INVITE

    case organizationRemoveInviteOrganizationName = "TUIST_ORGANIZATION_REMOVE_INVITE_ORGANIZATION_NAME"
    case organizationRemoveInviteEmail = "TUIST_ORGANIZATION_REMOVE_INVITE_EMAIL"
    case organizationRemoveInvitePath = "TUIST_ORGANIZATION_REMOVE_INVITE_PATH"

    // ORGANIZATION REMOVE MEMBER

    case organizationRemoveMemberOrganizationName = "TUIST_ORGANIZATION_REMOVE_MEMBER_ORGANIZATION_NAME"
    case organizationRemoveMemberUsername = "TUIST_ORGANIZATION_REMOVE_MEMBER_USERNAME"
    case organizationRemoveMemberPath = "TUIST_ORGANIZATION_REMOVE_MEMBER_PATH"

    // ORGANIZATION REMOVE SSO

    case organizationRemoveSSOOrganizationName = "TUIST_ORGANIZATION_REMOVE_SSO_ORGANIZATION_NAME"
    case organizationRemoveSSOPath = "TUIST_ORGANIZATION_REMOVE_SSO_PATH"

    // ORGANIZATION UPDATE SSO

    case organizationUpdateSSOOrganizationName = "TUIST_ORGANIZATION_UPDATE_SSO_ORGANIZATION_NAME"
    case organizationUpdateSSOProvider = "TUIST_ORGANIZATION_UPDATE_SSO_PROVIDER"
    case organizationUpdateSSOOrganizationId = "TUIST_ORGANIZATION_UPDATE_SSO_ORGANIZATION_ID"
    case organizationUpdateSSOPath = "TUIST_ORGANIZATION_UPDATE_SSO_PATH"

    // PROJECT DELETE

    case projectDeleteFullHandle = "TUIST_PROJECT_DELETE_FULL_HANDLE"
    case projectDeletePath = "TUIST_PROJECT_DELETE_PATH"

    // PROJECT CREATE

    case projectCreateFullHandle = "TUIST_PROJECT_CREATE_FULL_HANDLE"
    case projectCreatePath = "TUIST_PROJECT_CREATE_PATH"

    // PROJECT SHOW

    case projectShowFullHandle = "TUIST_PROJECT_SHOW_FULL_HANDLE"
    case projectShowPath = "TUIST_PROJECT_SHOW_PATH"
    case projectShowWeb = "TUIST_PROJECT_SHOW_WEB"

    // ORGANIZATION INVITE

    case organizationInviteOrganizationName = "TUIST_ORGANIZATION_INVITE_ORGANIZATION_NAME"
    case organizationInviteEmail = "TUIST_ORGANIZATION_INVITE_EMAIL"
    case organizationInvitePath = "TUIST_ORGANIZATION_INVITE_PATH"

    // ORGANIZATION SHOW

    case organizationShowOrganizationName = "TUIST_ORGANIZATION_SHOW_ORGANIZATION_NAME"
    case organizationShowJson = "TUIST_ORGANIZATION_SHOW_JSON"
    case organizationShowPath = "TUIST_ORGANIZATION_SHOW_PATH"

    // PROJECT LIST

    case projectListJson = "TUIST_PROJECT_LIST_JSON"
    case projectListPath = "TUIST_PROJECT_LIST_PATH"

    // BUNDLE LIST

    case bundleListFullHandle = "TUIST_BUNDLE_LIST_FULL_HANDLE"
    case bundleListPath = "TUIST_BUNDLE_LIST_PATH"
    case bundleListGitBranch = "TUIST_BUNDLE_LIST_GIT_BRANCH"
    case bundleListJson = "TUIST_BUNDLE_LIST_JSON"

    // BUNDLE SHOW

    case bundleShowFullHandle = "TUIST_BUNDLE_SHOW_FULL_HANDLE"
    case bundleShowId = "TUIST_BUNDLE_SHOW_ID"
    case bundleShowPath = "TUIST_BUNDLE_SHOW_PATH"
    case bundleShowJson = "TUIST_BUNDLE_SHOW_JSON"

    // ORGANIZATION UPDATE MEMBER

    case organizationUpdateMemberOrganizationName = "TUIST_ORGANIZATION_UPDATE_MEMBER_ORGANIZATION_NAME"
    case organizationUpdateMemberUsername = "TUIST_ORGANIZATION_UPDATE_MEMBER_USERNAME"
    case organizationUpdateMemberRole = "TUIST_ORGANIZATION_UPDATE_MEMBER_ROLE"
    case organizationUpdateMemberPath = "TUIST_ORGANIZATION_UPDATE_MEMBER_PATH"

    // REGISTRY LOGIN

    case registryLoginPath = "TUIST_REGISTRY_LOGIN_PATH"

    // REGISTRY LOGOUT

    case registryLogoutPath = "TUIST_REGISTRY_LOGOUT_PATH"

    // REGISTRY SETUP

    case registrySetUpPath = "TUIST_REGISTRY_SETUP_PATH"

    // AUTH

    case authPath = "TUIST_AUTH_PATH"
    case authEmail = "TUIST_AUTH_EMAIL"
    case authPassword = "TUIST_AUTH_PASSWORD"

    // SESSION

    case whoamiPath = "TUIST_WHOAMI_PATH"

    // LOGOUT

    case logoutPath = "TUIST_LOGOUT_PATH"

    // AUTH REFRESH-TOKEN

    case authRefreshTokenServerURL = "TUIST_AUTH_REFRESH_TOKEN_SERVER_URL"

    // ANALYTICS

    case analyticsPath = "TUIST_ANALYTICS_PATH"

    // SHARE

    case shareApp = "TUIST_SHARE_APP"
    case shareConfiguration = "TUIST_SHARE_CONFIGURATION"
    case sharePlatform = "TUIST_SHARE_PLATFORM"
    case shareJSON = "TUIST_SHARE_JSON"
    case shareDerivedDataPath = "TUIST_SHARE_DERIVED_DATA_PATH"
    case shareTrack = "TUIST_SHARE_TRACK"

    // CACHE

    case cacheExternalOnly = "TUIST_CACHE_EXTERNAL_ONLY"
    case cacheGenerateOnly = "TUIST_CACHE_GENERATE_ONLY"
    case cachePrintHashes = "TUIST_CACHE_PRINT_HASHES"
    case cacheConfiguration = "TUIST_CACHE_CONFIGURATION"
    case cachePath = "TUIST_CACHE_PATH"
    case cacheTargets = "TUIST_CACHE_TARGETS"

    // HASH CACHE

    case hashCachePath = "TUIST_HASH_CACHE_PATH"
    case hashCacheConfiguration = "TUIST_HASH_CACHE_CONFIGURATION"

    // HASH TEST

    case hashTestPath = "TUIST_HASH_TEST_PATH"
    case hashTestConfiguration = "TUIST_HASH_TEST_CONFIGURATION"

    /// CACHE START
    case cacheStartPath = "TUIST_CACHE_START_PATH"
}

extension EnvKey {
    var envValueString: String? {
        Environment.current.tuistVariables[rawValue]
    }

    func envValue<T: ExpressibleByArgument>() -> T? {
        guard let envValueString else {
            return nil
        }
        return T(argument: envValueString)
    }

    func envValue<T: ExpressibleByArgument>() -> [T]? {
        return envValueString?.split(separator: ",").compactMap { T(argument: String($0)) }
    }
}
