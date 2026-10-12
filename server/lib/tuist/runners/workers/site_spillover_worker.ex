defmodule Tuist.Runners.Workers.SiteSpilloverWorker do
  @moduledoc """
  Makes the rented fleet the backup of a site's. An account on the
  `runner_site` flag has its profile jobs queued on the site's catalog pool
  (`Tuist.Runners.Catalog.site_pool_name/1`). A job no site runner has
  claimed within `@spill_after_seconds` moves to the rented pool for the
  same Xcode and shape, whose autoscaler then counts it and whose runners
  claim it, so a site that is dark, full or slow to boot delays its jobs
  by that long instead of holding them.

  The wait covers a site runner's cold boot, so a burst the site can take
  stays there. A job a site runner claims in the meantime is no longer
  `queued` and is left alone (`Tuist.Runners.WorkflowJobs.move_queued/3`).
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  alias Tuist.Environment
  alias Tuist.Runners.Catalog
  alias Tuist.Runners.WorkflowJobs

  require Logger

  @spill_after_seconds 120

  @impl Oban.Worker
  def perform(_job) do
    enqueued_before = DateTime.add(DateTime.utc_now(), -@spill_after_seconds, :second)

    for {site_pool, _} <- Environment.runners_site_pools(),
        rented_pool = Catalog.rented_pool_name(site_pool),
        is_binary(rented_pool),
        moved = WorkflowJobs.move_queued(site_pool, rented_pool, enqueued_before),
        moved > 0 do
      Logger.info("runners: moved #{moved} queued site jobs from #{site_pool} to #{rented_pool}")
    end

    :ok
  end
end
