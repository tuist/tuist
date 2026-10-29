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

  alias Tuist.GitHub.App
  alias Tuist.Registry.Swift.Metadata
  alias Tuist.Registry.Swift.SwiftPackageIndex
  alias Tuist.Registry.Swift.SyncWorker

  require Logger

  def registry_bucket, do: Application.get_env(:tuist, :registry)[:bucket]
  def registry_s3_config, do: Application.get_env(:tuist, :registry)[:s3_config] || []

  @doc """
  The full public base URL, including the API path prefix, that clients use
  to reach the Swift package registry. Set per environment via
  `TUIST_REGISTRY_URL` so managed deployments and self-hosted installations
  can choose their own base address. `nil` when the deployment exposes no
  registry, in which case the discovery endpoint returns 404.
  """
  def url do
    case Application.get_env(:tuist, :registry)[:url] do
      url when is_binary(url) and url != "" -> String.trim_trailing(url, "/")
      _ -> nil
    end
  end

  @doc """
  The static personal access token the mirror used before it moved to the
  GitHub App. Kept as the fallback for deployments that have not configured an
  App installation for registry synchronization.
  """
  def swift_registry_github_personal_access_token do
    case Application.get_env(:tuist, :registry)[:swift_github_token] do
      token when is_binary(token) and token != "" -> token
      _ -> nil
    end
  end

  @doc """
  The GitHub App installation the mirror authenticates as, when one is
  configured.

  A personal access token spends one user-scoped hourly budget across the whole
  catalog rotation and every release job, which is the budget the July 2026
  incident exhausted. An installation token draws on the App installation's own
  budget instead, and expires on its own rather than living in a secret store.

  Accepts either the numeric installation id or the organization the App is
  installed on, resolved through `Tuist.GitHub.App.get_installation_id_for_org/2`
  and cached there. The organization form is what environments actually
  configure: an installation id is an opaque number an operator has to go and
  look up, and a value nobody can read is a value nobody sets, which is how this
  path would have shipped switched off.
  """
  def swift_registry_github_app_installation_id do
    case Application.get_env(:tuist, :registry)[:swift_github_app_installation] do
      value when is_binary(value) and value != "" -> resolve_installation(value)
      _ -> nil
    end
  end

  defp resolve_installation(value) do
    if numeric?(value) do
      value
    else
      case App.get_installation_id_for_org(value) do
        {:ok, installation_id} ->
          to_string(installation_id)

        {:error, reason} ->
          Logger.error("Registry sync could not resolve the GitHub App installation for #{value}: #{inspect(reason)}")

          nil
      end
    end
  end

  defp numeric?(value), do: match?({_integer, ""}, Integer.parse(value))

  @doc """
  Whether the mirror has some way to authenticate against GitHub.

  Deliberately does not mint a token: this answers a configuration question on
  every worker tick, and minting reaches the network. A misconfigured App is
  reported by `swift_registry_github_token/0` at the point the token is
  actually needed.
  """
  def swift_registry_github_credentials_configured? do
    configured =
      case Application.get_env(:tuist, :registry)[:swift_github_app_installation] do
        value when is_binary(value) and value != "" -> value
        _ -> nil
      end

    github_credentials_configured?(configured, swift_registry_github_personal_access_token())
  end

  @doc """
  Whether the given pair of credentials amounts to a usable configuration.

  Split from `swift_registry_github_credentials_configured?/0` so the rule can
  be exercised without mutating application environment.
  """
  def github_credentials_configured?(installation_id, personal_access_token) do
    not is_nil(installation_id) or not is_nil(personal_access_token)
  end

  @doc """
  Resolves the token the Swift mirror calls GitHub with.

  Prefers a short-lived installation token when an installation is configured,
  and falls back to the personal access token when the App is unavailable, so a
  credential problem degrades synchronization rather than stopping it. Returns
  `nil` when neither is available, which callers treat as "not configured".
  """
  def swift_registry_github_token do
    github_token(
      swift_registry_github_app_installation_id(),
      swift_registry_github_personal_access_token()
    )
  end

  @doc """
  Resolves a token from an explicit pair of credentials.

  Split from `swift_registry_github_token/0` for the same reason as
  `github_credentials_configured?/2`: the resolution rule is the part worth
  testing, and reading it from application environment is not.
  """
  def github_token(nil, personal_access_token), do: personal_access_token

  def github_token(installation_id, personal_access_token) do
    case App.get_installation_token(installation_id) do
      {:ok, %{token: token}} ->
        token

      {:error, reason} ->
        Logger.error("Failed to mint a registry sync installation token: #{inspect(reason)}")

        personal_access_token
    end
  end

  def swift_registry_enabled?, do: registry_bucket() != nil and swift_registry_github_credentials_configured?()

  def swift_registry_sync_enabled? do
    Application.get_env(:tuist, :registry)[:swift_sync_enabled] == true
  end

  def swift_registry_sync_allowlist do
    Application.get_env(:tuist, :registry)[:swift_sync_allowlist]
  end

  def swift_registry_sync_limit do
    Application.get_env(:tuist, :registry)[:swift_sync_limit] || 600
  end

  def list_swift_packages do
    SwiftPackageIndex.list_packages(nil)
  end

  def get_swift_package(scope, name) when is_binary(scope) and is_binary(name) do
    with {:ok, packages} <- list_swift_packages(),
         package when not is_nil(package) <-
           Enum.find(packages, &(&1.scope == scope and &1.name == name)),
         {:ok, metadata} <- get_swift_package_metadata(scope, name) do
      {:ok, Map.put(package, :versions, swift_package_versions(metadata))}
    else
      nil -> {:error, :not_found}
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Rebuilds a published version in place.

  A rebuild that produces different bytes than the version already advertises
  is refused, because it turns a working pin into a checksum mismatch for every
  client that already resolved it. Pass `allow_checksum_change: true` to accept
  that trade, which is the case for a version whose stored archive cannot be
  extracted at all and so was never resolved successfully by anyone.
  """
  def force_resync_swift_package_version(repository_full_handle, version, opts \\ [])
      when is_binary(repository_full_handle) and is_binary(version) do
    %{
      repository_full_handle: repository_full_handle,
      version: version,
      force: true,
      allow_checksum_change: Keyword.get(opts, :allow_checksum_change, false)
    }
    |> SyncWorker.new(unique: [period: 60, keys: [:repository_full_handle, :version, :force, :allow_checksum_change]])
    |> Oban.insert()
  end

  defp get_swift_package_metadata(scope, name) do
    case Metadata.get_package(scope, name) do
      {:ok, metadata} -> {:ok, metadata}
      {:error, :not_found} -> {:ok, %{}}
      {:error, _reason} = error -> error
    end
  end

  defp swift_package_versions(metadata) do
    releases = Map.get(metadata, "releases", %{})

    available_versions =
      Enum.map(releases, fn {version, release} ->
        %{
          version: version,
          status: :available,
          detail: Map.get(release, "checksum")
        }
      end)

    skipped_versions =
      metadata
      |> Map.get("skipped_releases", %{})
      |> Map.drop(Map.keys(releases))
      |> Enum.map(fn {version, release} ->
        %{
          version: version,
          status: :skipped,
          detail: Map.get(release, "reason")
        }
      end)

    Enum.sort_by(
      available_versions ++ skipped_versions,
      &Version.parse!(&1.version),
      {:desc, Version}
    )
  end
end
