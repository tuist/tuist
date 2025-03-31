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
      Marketing.Pages,
      Marketing.Changelog,
      Marketing.OpenGraph,
      Marketing.Newsletter,

      # App
      # -----
      # This module contains Tuist features that are not expected to have inter-dependencies
      # among them. They must only depend on core and utility modules.
      Cache,
      CacheActionItems,
      CommandEvents,
      CommandEvents.Event,
      Registry.Swift.Packages,
      Registry.Swift.Packages.Package,
      Registry.Swift.Packages.PackageManifest,
      Registry.Swift.Packages.PackageRelease,
      Runs,
      Runs.Build,
      Runs.Analytics,
      # App
      # -----
      # They are modules that are core to the Tuist domain (e.g. accounts) and that other
      # features build upon.
      API.Pipeline,
      Accounts,
      Accounts.Account,
      Accounts.AuthenticatedAccount,
      Accounts.User,
      Authentication,
      Authorization,
      Billing,
      Billing.Subscription,
      Previews,
      Previews.Preview,
      Projects,
      Projects.Project,
      Xcode,
      Xcode.XcodeGraph,
      Xcode.XcodeProject,
      Xcode.XcodeTarget,
      # Support
      # -----
      # These modules represent Tuist-agnostic utilities that are used by other features.
      # As of today, some of these utilities still have knowledge of the Tuist domain,
      # but we should aim to make them domain-agnostic. To know if they are Tuist-agnostic
      # a good rule of thumb is to ask if they can work as a standalone library.
      Analytics,
      Environment,
      GitHub.Releases,
      Incidents,
      License,
      # We should not be exposing this one
      Repo,
      Storage,
      Time,
      VCS,
      UUIDv7
    ]
end
