defmodule Tuist.Registry do
  @moduledoc """
  Control-plane namespace for the Swift Package Registry.

  Swift sync workers under `Tuist.Registry.Swift.*` run in the
  swift-registry-sync pod (`TUIST_MODE=swift_registry_sync`) and write
  package metadata + artifacts to the registry S3 bucket. Future
  ecosystems mount their own modules + mode under the same generic
  registry namespace. The standalone `registry` Phoenix app reads back
  from the same bucket and is the only public surface — it does not
  talk to this codebase directly. See `registry/AGENTS.md` for the
  read side and
  `infra/helm/tuist/templates/swift-registry-sync-deployment.yaml` for
  how the Swift mode is deployed.

  Per-download analytics are emitted as PromEx counters on the
  standalone registry pod; nothing is persisted to ClickHouse from the
  new path. The `registry_download_events` table that the legacy
  cache → webhook → ClickHouse pipeline wrote to has no remaining
  reader and will be dropped once cache's registry surface is
  decommissioned.
  """

  def registry_bucket, do: Application.get_env(:tuist, :registry)[:bucket]

  def swift_registry_github_token do
    case Application.get_env(:tuist, :registry)[:swift_github_token] do
      token when is_binary(token) and token != "" -> token
      _ -> nil
    end
  end

  def swift_registry_enabled?, do: registry_bucket() != nil and swift_registry_github_token() != nil

  def swift_registry_sync_enabled? do
    Application.get_env(:tuist, :registry)[:swift_sync_enabled] == true
  end

  def swift_registry_sync_allowlist do
    Application.get_env(:tuist, :registry)[:swift_sync_allowlist]
  end

  def swift_registry_sync_limit do
    Application.get_env(:tuist, :registry)[:swift_sync_limit] || 1_000
  end
end
