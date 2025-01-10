defmodule Tuist.Registry.Swift.Workers.UpdatePackageReleasesWorker do
  @moduledoc """
  A worker that updates Swift package releases.
  """
  alias Tuist.Environment
  import Environment, only: [run_if_error_tracking_enabled: 1]

  use Oban.Worker,
    unique: [
      period: :infinity,
      states: [:available, :scheduled, :executing, :retryable]
    ],
    max_attempts: 3

  alias Tuist.Time
  alias Tuist.Registry.Swift.Packages

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    limit = Map.get(args, :limit, 350)

    {packages, _meta} =
      Packages.paginated_packages(%{
        first: limit,
        order_by: [:last_updated_releases_at],
        order_directions: [:asc_nulls_first]
      })

    for package <- packages do
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
