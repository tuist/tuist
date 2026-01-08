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
      Marketing.Changelog,
      Marketing.OpenGraph,
      Marketing.Newsletter,
      Marketing.BlogContentProcessor,
      Marketing.Customers,
      # App
      # -----
      # This module contains Tuist features that are not expected to have inter-dependencies
      # among them. They must only depend on core and utility modules.
      Bundles,
      Bundles.Bundle,
      Cache,
      Cache.Analytics,
      CacheActionItems,
      CommandEvents,
      CommandEvents.Event,
      Registry.Swift.Packages,
      Registry.Swift.Packages.Package,
      Registry.Swift.Packages.PackageManifest,
      Registry.Swift.Packages.PackageRelease,
      Runs,
      Runs.Build,
      Runs.CASOutput,
      Runs.Analytics,
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
      QA,
      QA.Run,
      QA.Step,
      QA.Screenshot,
      QA.Log,
      QA.Logs.Buffer,
      QA.Workers.TestWorker,
      Apple,
      Xcode,
      Xcode.XcodeGraph,
      Xcode.XcodeProject,
      Xcode.XcodeTarget,
      Loops,
      Namespace,
      Namespace.JWTToken,
      QA,
      QA.LaunchArgumentGroup,
      VCS.GitHubAppInstallation,
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
      # We should not be exposing this one
      Repo,
      Storage,
      Tasks,
      Time,
      Utilities.ByteFormatter,
      Utilities.DateFormatter,
      Utilities.ThroughputFormatter,
      VCS,
      UUIDv7,
      OAuth.Apple,
      OAuth.Okta
    ]
end
