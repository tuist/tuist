defmodule Tuist.Registry.Swift.Workers.UpdatePackageReleasesWorker do
  @moduledoc """
  A worker that updates Swift package releases.
  """
  use Oban.Worker,
    unique: [
      period: :infinity,
      states: [:available, :scheduled, :executing, :retryable]
    ],
    max_attempts: 10

  import Tuist.Environment, only: [run_if_error_tracking_enabled: 1]

  alias Tuist.Environment
  alias Tuist.Registry.Swift.Packages
  alias Tuist.Time

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    limit = Map.get(args, :limit, 350)

    {packages, _meta} =
      Packages.paginated_packages(
        %{
          first: limit,
          order_by: [:last_updated_releases_at],
          order_directions: [:asc_nulls_first]
        },
        preload: [:package_releases]
      )

    for package <- packages do
      Logger.info("Updating package releases for #{package.scope}/#{package.name}")

      run_if_error_tracking_enabled do
        Appsignal.Span.set_sample_data(
          Appsignal.Tracer.root_span(),
          "tags",
          %{
            package: package.scope <> "/" <> package.name
          }
        )
      end

      Packages.create_missing_package_releases(%{
        package: package,
        token: Environment.github_token_update_package_releases()
      })

      Packages.update_package(package, %{last_updated_releases_at: Time.utc_now()})
    end

    :ok
  end
end
