defmodule Tuist do
  @moduledoc """
  Tuist keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """
  use Boundary,
    deps: [],
    exports: [
      # Marketing
      # -----
      # These modules contain utilities that are used for the marketing-related
      # routes and features.
      Marketing.Blog,
      Marketing.Content,
      Marketing.Pages,
      Docs,
      Docs.OgImage,
      Docs.Page,
      Docs.Paths,
      Locale,
      Docs.Sidebar,
      Marketing.Changelog,
      Marketing.Changelog.OgImage,
      Marketing.OgImages,
      Marketing.OpenGraph,
      Marketing.Newsletter,
      Marketing.BlogContentProcessor,
      Marketing.Customers,
      Marketing.Stats,
      # App
      # -----
      # This module contains Tuist features that are not expected to have inter-dependencies
      # among them. They must only depend on core and utility modules.
      Bundles,
      Bundles.Bundle,
      Bundles.BundleThreshold,
      Bundles.Workers.BundleThresholdWorker,
      Cache,
      Cache.Analytics,
      CacheEndpoints,
      Gradle,
      Gradle.Analytics,
      Gradle.Build,
      Gradle.Task,
      Gradle.CacheEvent,
      CacheActionItems,
      CommandEvents,
      CommandEvents.Event,
      Registry,
      Builds,
      Builds.Build,
      Builds.CASOutput,
      Builds.Analytics,
      Builds.Workers.ProcessBuildWorker,
      Runs.Analytics,
      Tests,
      Tests.Test,
      Tests.TestCase,
      Tests.TestRunDestination,
      Tests.Analytics,
      Tests.Workers.ProcessXcresultWorker,
      Shards,
      Shards.Analytics,
      Shards.ShardPlan,
      Shards.ShardPlanModule,
      Shards.ShardPlanTestSuite,
      Shards.ShardRun,
      MCP.Server,
      # App
      # -----
      # They are modules that are core to the Tuist domain (e.g. accounts) and that other
      # features build upon.
      API.Pipeline,
      Accounts,
      Accounts.Account,
      Accounts.AccountCacheEndpoint,
      Accounts.Organization,
      Accounts.AuthenticatedAccount,
      Accounts.AccountToken,
      Accounts.User,
      Authentication,
      Authorization,
      Guardian,
      OIDC,
      Authorization.Checks,
      Billing,
      Billing.Subscription,
      AppBuilds,
      AppBuilds.Preview,
      AppBuilds.AppBuild,
      Projects,
      Projects.Project,
      Projects.Workers.CleanProjectWorker,
      Apple,
      Xcode,
      Xcode.XcodeGraph,
      Xcode.XcodeProject,
      Xcode.XcodeTarget,
      Loops,
      Namespace,
      Namespace.JWTToken,
      VCS.GitHubAppInstallation,
      Alerts,
      Alerts.Alert,
      Alerts.AlertRule,
      Alerts.Workers.AlertWorker,
      Slack,
      Slack.Client,
      Slack.Installation,
      Slack.Reports,
      Slack.Workers.ReportWorker,
      # Support
      # -----
      # These modules represent Tuist-agnostic utilities that are used by other features.
      # As of today, some of these utilities still have knowledge of the Tuist domain,
      # but we should aim to make them domain-agnostic. To know if they are Tuist-agnostic
      # a good rule of thumb is to ask if they can work as a standalone library.
      Analytics,
      Environment,
      Ecto.Utils,
      GitHub.Releases,
      Incidents,
      License,
      PubSub,
      KeyValueStore,
      ClickHouseRepo,
      ClickHouseFlop,
      Markdown,
      Cldr,
      Cldr.Number,
      # We should not be exposing this one
      Repo,
      Storage,
      Tasks,
      Time,
      URL,
      Utilities.ByteFormatter,
      Utilities.DateFormatter,
      Utilities.ThroughputFormatter,
      VCS,
      UUIDv7,
      OAuth.Apple,
      OAuth2.SSOClient,
      OAuth2.SSRFGuard
    ]
end
