defmodule Tuist.Runners.Workers.SiteSpilloverWorker do
  @moduledoc """
  Makes the rented fleet the backup of a site's. While a site pool is down
  (`Tuist.Runners.Sites.status/1`), its queued jobs move to the rented pool for
  the same Xcode and shape, whose runners then claim them. While it is up, its
  jobs stay however long they queue, so a rented runner never picks up a job
  the site would have run. A job a site runner claims is no longer `queued`
  and is left alone (`Tuist.Runners.WorkflowJobs.move_queued/3`). In an env
  that rents no macOS fleet (`Tuist.Environment.runners_rented_macos_fleet?/0`)
  there is no backup, so site jobs wait for the site.
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  alias Tuist.Environment
  alias Tuist.Runners.Catalog
  alias Tuist.Runners.Sites
  alias Tuist.Runners.WorkflowJobs

  require Logger

  @impl Oban.Worker
  def perform(_job) do
    if Environment.runners_rented_macos_fleet?(), do: spill_over()

    :ok
  end

  defp spill_over do
    queued_fleets = WorkflowJobs.queue_stats_by_fleet(~U[1970-01-01 00:00:00Z])

    for {site_pool, _} <- Environment.runners_site_pools(),
        Map.has_key?(queued_fleets, site_pool),
        rented_pool = Catalog.rented_pool_name(site_pool),
        is_binary(rented_pool),
        {:down, reason} <- [Sites.status(site_pool)],
        moved = WorkflowJobs.move_queued(site_pool, rented_pool, DateTime.utc_now()),
        moved > 0 do
      Logger.warning("runners: moved #{moved} queued site jobs from #{site_pool} to #{rented_pool}",
        reason: reason
      )
    end
  end
end
