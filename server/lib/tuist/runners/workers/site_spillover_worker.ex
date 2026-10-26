defmodule Tuist.Runners.Workers.SiteSpilloverWorker do
  @moduledoc """
  Makes another site, then the rented fleet, the backup of a site's. While a
  site pool is down (`Tuist.Runners.Sites.status/1`), its queued jobs move to
  the same Xcode and shape at the first other site that is up
  (`Tuist.Runners.Catalog.sibling_site_pool_names/1`), else to the rented
  pool, whose runners then claim them. While it is up, its jobs stay however
  long they queue, so a runner elsewhere never picks up a job the site would
  have run. A job a site runner claims is no longer `queued` and is left alone
  (`Tuist.Runners.WorkflowJobs.move_queued/3`). In an env that rents no macOS
  fleet (`Tuist.Environment.runners_rented_macos_fleet?/0`) and racks a pool at
  one site only, there is no backup, so its jobs wait for the site.
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  alias Tuist.Environment
  alias Tuist.Runners.Catalog
  alias Tuist.Runners.Sites
  alias Tuist.Runners.WorkflowJobs

  require Logger

  @impl Oban.Worker
  def perform(_job) do
    queued_fleets = WorkflowJobs.queue_stats_by_fleet(~U[1970-01-01 00:00:00Z])
    rented? = Environment.runners_rented_macos_fleet?()

    for {site_pool, _} <- Environment.runners_site_pools(), Map.has_key?(queued_fleets, site_pool) do
      spill_over(site_pool, Catalog.sibling_site_pool_names(site_pool), rented?)
    end

    :ok
  end

  defp spill_over(site_pool, siblings, rented?) do
    rented_pool = if rented?, do: Catalog.rented_pool_name(site_pool)

    with true <- siblings != [] or is_binary(rented_pool),
         {:down, reason} <- Sites.status(site_pool),
         target when is_binary(target) <- Enum.find(siblings, &(Sites.status(&1) == :up)) || rented_pool,
         moved when moved > 0 <- WorkflowJobs.move_queued(site_pool, target, DateTime.utc_now()) do
      Logger.warning("runners: moved #{moved} queued site jobs from #{site_pool} to #{target}", reason: reason)
    end
  end
end
