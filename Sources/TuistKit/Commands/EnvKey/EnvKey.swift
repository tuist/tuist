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

    // GENERATE
    case generatePath = "TUIST_GENERATE_PATH"
    case generateOpen = "TUIST_GENERATE_OPEN"
    case generateBinaryCache = "TUIST_GENERATE_BINARY_CACHE"

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
    case testPath = "TUIST_TEST_PATH"
    case testDevice = "TUIST_TEST_DEVICE"
    case testPlatform = "TUIST_TEST_PLATFORM"
    case testOS = "TUIST_TEST_OS"
    case testRosetta = "TUIST_TEST_ROSETTA"
    case testConfiguration = "TUIST_TEST_CONFIGURATION"
    case testSkipUITests = "TUIST_TEST_SKIP_UITESTS"
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

    // CLOUD ORGANIZATION BILLING
    case cloudOrganizationBillingOrganizationName = "TUIST_CLOUD_ORGANIZATION_BILLING_ORGANIZATION_NAME"
    case cloudOrganizationBillingPath = "TUIST_CLOUD_ORGANIZATION_BILLING_PATH"

    // CLOUD ORGANIZATION CREATE
    case cloudOrganizationCreateOrganizationName = "TUIST_CLOUD_ORGANIZATION_CREATE_ORGANIZATION_NAME"
    case cloudOrganizationCreatePath = "TUIST_CLOUD_ORGANIZATION_CREATE_PATH"

    // CLOUD ORGANIZATION DELETE
    case cloudOrganizationDeleteOrganizationName = "TUIST_CLOUD_ORGANIZATION_DELETE_ORGANIZATION_NAME"
    case cloudOrganizationDeletePath = "TUIST_CLOUD_ORGANIZATION_DELETE_PATH"

    // CLOUD PROJECT TOKEN
    case cloudProjectTokenProjectName = "TUIST_CLOUD_PROJECT_TOKEN_PROJECT_NAME"
    case cloudProjectTokenOrganizationName = "TUIST_CLOUD_PROJECT_TOKEN_ORGANIZATION_NAME"
    case cloudProjectTokenPath = "TUIST_CLOUD_PROJECT_TOKEN_PATH"

    // CLOUD ORGANIZATION LIST
    case cloudOrganizationListJson = "TUIST_CLOUD_ORGANIZATION_LIST_JSON"
    case cloudOrganizationListPath = "TUIST_CLOUD_ORGANIZATION_LIST_PATH"

    // CLOUD ORGANIZATION REMOVE INVITE
    case cloudOrganizationRemoveInviteOrganizationName = "TUIST_CLOUD_ORGANIZATION_REMOVE_INVITE_ORGANIZATION_NAME"
    case cloudOrganizationRemoveInviteEmail = "TUIST_CLOUD_ORGANIZATION_REMOVE_INVITE_EMAIL"
    case cloudOrganizationRemoveInvitePath = "TUIST_CLOUD_ORGANIZATION_REMOVE_INVITE_PATH"

    // CLOUD ORGANIZATION REMOVE MEMBER
    case cloudOrganizationRemoveMemberOrganizationName = "TUIST_CLOUD_ORGANIZATION_REMOVE_MEMBER_ORGANIZATION_NAME"
    case cloudOrganizationRemoveMemberUsername = "TUIST_CLOUD_ORGANIZATION_REMOVE_MEMBER_USERNAME"
    case cloudOrganizationRemoveMemberPath = "TUIST_CLOUD_ORGANIZATION_REMOVE_MEMBER_PATH"

    // CLOUD ORGANIZATION REMOVE SSO
    case cloudOrganizationRemoveSSOOrganizationName = "TUIST_CLOUD_ORGANIZATION_REMOVE_SSO_ORGANIZATION_NAME"
    case cloudOrganizationRemoveSSOPath = "TUIST_CLOUD_ORGANIZATION_REMOVE_SSO_PATH"

    // CLOUD ORGANIZATION UPDATE SSO
    case cloudOrganizationUpdateSSOOrganizationName = "TUIST_CLOUD_ORGANIZATION_UPDATE_SSO_ORGANIZATION_NAME"
    case cloudOrganizationUpdateSSOProvider = "TUIST_CLOUD_ORGANIZATION_UPDATE_SSO_PROVIDER"
    case cloudOrganizationUpdateSSOOrganizationId = "TUIST_CLOUD_ORGANIZATION_UPDATE_SSO_ORGANIZATION_ID"
    case cloudOrganizationUpdateSSOPath = "TUIST_CLOUD_ORGANIZATION_UPDATE_SSO_PATH"

    // CLOUD PROJECT DELETE
    case cloudProjectDeleteProject = "TUIST_CLOUD_PROJECT_DELETE_PROJECT"
    case cloudProjectDeleteOrganization = "TUIST_CLOUD_PROJECT_DELETE_ORGANIZATION"
    case cloudProjectDeletePath = "TUIST_CLOUD_PROJECT_DELETE_PATH"

    // CLOUD PROJECT CREATE
    case cloudProjectCreateName = "TUIST_CLOUD_PROJECT_CREATE_NAME"
    case cloudProjectCreateOrganization = "TUIST_CLOUD_PROJECT_CREATE_ORGANIZATION"
    case cloudProjectCreatePath = "TUIST_CLOUD_PROJECT_CREATE_PATH"

    // CLOUD INIT
    case cloudInitName = "TUIST_CLOUD_INIT_NAME"
    case cloudInitOrganization = "TUIST_CLOUD_INIT_ORGANIZATION"
    case cloudInitPath = "TUIST_CLOUD_INIT_PATH"

    // CLOUD ORGANIZATION INVITE
    case cloudOrganizationInviteOrganizationName = "TUIST_CLOUD_ORGANIZATION_INVITE_ORGANIZATION_NAME"
    case cloudOrganizationInviteEmail = "TUIST_CLOUD_ORGANIZATION_INVITE_EMAIL"
    case cloudOrganizationInvitePath = "TUIST_CLOUD_ORGANIZATION_INVITE_PATH"

    // CLOUD ORGANIZATION SHOW
    case cloudOrganizationShowOrganizationName = "TUIST_CLOUD_ORGANIZATION_SHOW_ORGANIZATION_NAME"
    case cloudOrganizationShowJson = "TUIST_CLOUD_ORGANIZATION_SHOW_JSON"
    case cloudOrganizationShowPath = "TUIST_CLOUD_ORGANIZATION_SHOW_PATH"

    // CLOUD PROJECT LIST
    case cloudProjectListJson = "TUIST_CLOUD_PROJECT_LIST_JSON"
    case cloudProjectListPath = "TUIST_CLOUD_PROJECT_LIST_PATH"

    // CLOUD ORGANIZATION UPDATE MEMBER
    case cloudOrganizationUpdateMemberOrganizationName = "TUIST_CLOUD_ORGANIZATION_UPDATE_MEMBER_ORGANIZATION_NAME"
    case cloudOrganizationUpdateMemberUsername = "TUIST_CLOUD_ORGANIZATION_UPDATE_MEMBER_USERNAME"
    case cloudOrganizationUpdateMemberRole = "TUIST_CLOUD_ORGANIZATION_UPDATE_MEMBER_ROLE"
    case cloudOrganizationUpdateMemberPath = "TUIST_CLOUD_ORGANIZATION_UPDATE_MEMBER_PATH"

    // CLOUD AUTH
    case cloudAuthPath = "TUIST_CLOUD_AUTH_PATH"

    // CLOUD SESSION
    case cloudSessionPath = "TUIST_CLOUD_SESSION_PATH"

    // CLOUD LOGOUT
    case cloudLogoutPath = "TUIST_CLOUD_LOGOUT_PATH"

    // CLOUD ANALYTICS
    case cloudAnalyticsPath = "TUIST_CLOUD_ANALYTICS_PATH"

    // CLOUD CLEAN
    case cloudCleanPath = "TUIST_CLOUD_CLEAN_PATH"
}

extension EnvKey {
    var envValueString: String? {
        Environment.shared.tuistVariables[rawValue]
    }

    func envValue<T: ExpressibleByArgument>() -> T? {
        guard let envValueString else {
            return nil
        }
        return T(argument: envValueString)
    }

    func envValue<T: ExpressibleByArgument>() -> [T] {
        guard let envValueString else {
            return []
        }
        return envValueString.split(separator: ",").compactMap { T(argument: String($0)) }
    }
}
