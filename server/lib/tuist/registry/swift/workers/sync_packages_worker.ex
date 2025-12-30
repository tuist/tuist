defmodule Tuist.Registry.Swift.Workers.SyncPackagesWorker do
  @moduledoc """
  A unified worker that syncs the Swift package registry by:
  1. Discovering new packages from SwiftPackageIndex
  2. Creating missing packages
  3. Finding missing package releases for existing packages
  4. Spawning individual workers to create missing releases
  """
  use Oban.Worker,
    queue: :registry,
    unique: [
      period: :infinity,
      states: [:available, :scheduled, :executing, :retryable]
    ],
    max_attempts: 10

  import Tuist.Environment, only: [run_if_error_tracking_enabled: 1]

  alias Tuist.Environment
  alias Tuist.Registry.Swift.Packages
  alias Tuist.Registry.Swift.Workers.CreatePackageReleaseWorker
  alias Tuist.Time
  alias Tuist.VCS
  alias Tuist.VCS.Repositories.Content

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    limit = Map.get(args, :limit, 350)
    update_packages = Map.get(args, :update_packages, true)
    update_releases = Map.get(args, :update_releases, true)
    allowlist = Map.get(args, :allowlist, Application.get_env(:tuist, :package_sync_allowlist))

    token_packages = Environment.github_token_update_packages()
    token_releases = Environment.github_token_update_package_releases()

    missing_versions_from_new_packages =
      if update_packages, do: sync_packages_from_spi(token_packages, token_releases, allowlist), else: []

    missing_versions_from_existing_packages =
      if update_releases, do: find_missing_releases_for_existing_packages(limit, token_releases), else: []

    all_missing_versions = missing_versions_from_new_packages ++ missing_versions_from_existing_packages

    spawn_release_workers(all_missing_versions)

    :ok
  end

  defp sync_packages_from_spi(token_packages, token_releases, allowlist) do
    Logger.info("Syncing packages from SwiftPackageIndex")

    {:ok, %Content{content: content}} =
      VCS.get_repository_content(
        %{
          repository_full_handle: "SwiftPackageIndex/PackageList",
          provider: :github,
          token: token_packages
        },
        path: "packages.json"
      )

    packages =
      content
      |> Jason.decode!()
      |> Enum.map(&VCS.get_repository_full_handle_from_url/1)
      |> Enum.map(&elem(&1, 1))
      |> apply_allowlist_filter(allowlist)
      |> Enum.map(&Packages.get_package_scope_and_name_from_repository_full_handle/1)

    # Remove packages no longer present in SwiftPackageIndex
    packages_set = MapSet.new(packages, &Map.take(&1, [:repository_full_handle]))

    removed_count =
      Packages.all_packages()
      |> Enum.filter(
        &(!MapSet.member?(packages_set, %{
            repository_full_handle: &1.repository_full_handle
          }))
      )
      # This is only to ensure we don't accidentally delete all packages in case we introduce a bug in the filtering logic.
      |> Enum.take(100)
      |> Enum.map(&Packages.delete_package/1)
      |> length()

    if removed_count > 0 do
      Logger.info("Removed #{removed_count} packages no longer present in SwiftPackageIndex")
    end

    # Create missing packages and get their missing versions
    existing_packages =
      packages
      |> Packages.get_packages_by_scope_and_name_pairs()
      |> MapSet.new(&{&1.scope, &1.name})

    missing_packages =
      Enum.filter(packages, fn package ->
        not MapSet.member?(existing_packages, {package.scope, package.name})
      end)

    if length(missing_packages) > 0 do
      Logger.info("Creating #{length(missing_packages)} new packages")
    end

    missing_new_package_versions =
      missing_packages
      # We don't want to exhaust the API limit of the token.
      |> Enum.take(100)
      |> Enum.map(&Packages.create_package/1)
      |> Enum.flat_map(&Packages.get_missing_package_versions(%{package: &1, token: token_releases}))

    Logger.info("Found #{length(missing_new_package_versions)} missing versions from new packages")
    missing_new_package_versions
  end

  defp find_missing_releases_for_existing_packages(limit, token_releases) do
    Logger.info("Finding missing releases for existing packages (limit: #{limit})")

    {packages, _meta} =
      Packages.paginated_packages(
        %{
          first: limit,
          order_by: [:last_updated_releases_at],
          order_directions: [:asc_nulls_first]
        },
        preload: [:package_releases]
      )

    missing_versions =
      Enum.flat_map(packages, fn package ->
        Logger.info("Finding missing package releases for #{package.scope}/#{package.name}")

        run_if_error_tracking_enabled do
          Appsignal.Span.set_sample_data(
            Appsignal.Tracer.root_span(),
            "tags",
            %{
              package: package.scope <> "/" <> package.name
            }
          )
        end

        missing_versions =
          Packages.get_missing_package_versions(%{
            package: package,
            token: token_releases
          })

        Packages.update_package(package, %{last_updated_releases_at: Time.utc_now()})

        missing_versions
      end)

    Logger.info("Found #{length(missing_versions)} missing versions from existing packages")
    missing_versions
  end

  defp spawn_release_workers(all_missing_versions) do
    total_missing = length(all_missing_versions)
    Logger.info("Found #{total_missing} total missing package releases, spawning individual workers")

    for %{scope: scope, name: name, version: version} <- all_missing_versions do
      %{
        scope: scope,
        name: name,
        version: version
      }
      |> CreatePackageReleaseWorker.new()
      |> Oban.insert!()
    end

    Logger.info("Spawned #{total_missing} CreatePackageReleaseWorker jobs")
  end

  defp apply_allowlist_filter(packages, nil), do: packages
  defp apply_allowlist_filter(packages, []), do: packages

  defp apply_allowlist_filter(packages, allowlist) when is_list(allowlist) do
    Enum.filter(packages, fn package ->
      Enum.any?(allowlist, fn pattern ->
        matches_pattern?(package, pattern)
      end)
    end)
  end

  defp matches_pattern?(package, pattern) do
    if String.ends_with?(pattern, "*") do
      prefix = String.trim_trailing(pattern, "*")
      String.starts_with?(package, prefix)
    else
      package == pattern
    end
  end
end
