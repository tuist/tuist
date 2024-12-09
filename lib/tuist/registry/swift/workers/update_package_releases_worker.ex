defmodule Tuist.Registry.Swift.Workers.UpdatePackageReleasesWorker do
  @moduledoc """
  A worker that updates Swift package releases.
  """
  alias Tuist.Environment
  use Oban.Worker

  alias Tuist.Time
  alias Tuist.Registry.Swift.Packages

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    limit = Map.get(args, :limit, 500)

    {packages, _meta} =
      Packages.paginated_packages(%{
        first: limit,
        order_by: [:last_updated_releases_at]
      })

    for package <- packages do
      Packages.create_missing_package_releases(%{
        package: package,
        token: Environment.github_token_update_package_releases()
      })

      Packages.update_package(package, %{last_updated_releases_at: Time.utc_now()})
    end

    :ok
  end
end
