defmodule Tuist.Registry.Swift.Workers.CreatePackageReleaseWorker do
  @moduledoc """
  A worker that creates a single Swift package release.
  """
  use Oban.Worker,
    queue: :registry,
    unique: [
      period: 60,
      states: [:available, :scheduled, :executing, :retryable],
      keys: [:scope, :name, :version]
    ],
    max_attempts: 3

  import Tuist.Environment, only: [run_if_error_tracking_enabled: 1]

  alias Tuist.Environment
  alias Tuist.Registry.Swift.Packages

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"scope" => scope, "name" => name, "version" => version}}) do
    Logger.info("Creating package release for #{scope}/#{name}@#{version}")

    run_if_error_tracking_enabled do
      Appsignal.Span.set_sample_data(
        Appsignal.Tracer.root_span(),
        "tags",
        %{
          package: scope <> "/" <> name,
          version: version
        }
      )
    end

    case Packages.get_package_by_scope_and_name(%{scope: scope, name: name}) do
      {:error, :not_found} ->
        Logger.error("Package #{scope}/#{name} not found")
        {:error, :package_not_found}

      {:ok, package} ->
        case Packages.get_package_release_by_version(%{package: package, version: Packages.semantic_version(version)}) do
          nil ->
            case Packages.create_package_release(%{
                   package: package,
                   version: version,
                   token: Environment.github_token_update_package_releases()
                 }) do
              {:error, reason} ->
                Logger.error("Failed to create package release for #{scope}/#{name}@#{version}: #{reason}")
                {:error, reason}

              _package_release ->
                :ok
            end

          _existing_release ->
            Logger.info("Package release #{scope}/#{name}@#{version} already exists, skipping")
            :ok
        end
    end
  rescue
    error ->
      Logger.error("Failed to create package release for #{scope}/#{name}@#{version}: #{Exception.message(error)}")
      {:error, error}
  end
end
