defmodule Tuist.Runners.Shadow.Snapshot do
  @moduledoc """
  Bounded, read-only inputs for the controller's shadow assignment policy.

  These are observations, not reservations. Demand is read before claims so
  the controller can discard jobs claimed during collection. Reads across
  PostgreSQL and Kubernetes are not atomic; the policy must never authorize
  execution. No credentials, repository names, or workflow contents leave
  this endpoint. A truncated snapshot is unusable, not a fair sample.
  """

  import Ecto.Query

  alias Tuist.Repo
  alias Tuist.Runners.Claim
  alias Tuist.Runners.ConcurrencyLimit
  alias Tuist.Runners.Jobs
  alias Tuist.Runners.WorkflowJob

  @max_demand 1000
  @max_claims 10_000

  def capture do
    captured_at = DateTime.utc_now()
    enqueued_floor = Jobs.queued_lookback_floor()

    demand =
      Repo.all(
        from(j in WorkflowJob,
          where: j.status == "queued" and j.enqueued_at > ^enqueued_floor,
          order_by: [asc: j.enqueued_at, asc: j.workflow_job_id],
          limit: ^(@max_demand + 1),
          select: %{
            job_id: j.workflow_job_id,
            account_id: j.account_id,
            pool: j.fleet_name,
            platform: j.platform,
            resources: %{vcpus: j.vcpus, memory_gb: j.memory_gb},
            enqueued_at: j.enqueued_at
          }
        )
      )

    claims =
      Repo.all(
        from(c in Claim,
          order_by: [asc: c.pod_name],
          limit: ^(@max_claims + 1),
          select: %{
            pod: c.pod_name,
            job_id: c.workflow_job_id,
            executed_job_id: c.executed_workflow_job_id,
            account_id: c.account_id,
            platform: c.platform,
            resources: %{vcpus: c.vcpus, memory_gb: c.memory_gb},
            claimed_at: c.claimed_at
          }
        )
      )

    complete = length(demand) <= @max_demand and length(claims) <= @max_claims

    if complete do
      account_ids = Enum.uniq(Enum.map(demand ++ claims, & &1.account_id))

      accounts =
        Repo.all(
          from(l in ConcurrencyLimit,
            where: l.account_id in ^account_ids,
            order_by: [asc: l.account_id, asc: l.platform],
            select: %{
              account_id: l.account_id,
              platform: l.platform,
              limit: %{vcpus: l.vcpus, memory_gb: l.memory_gb}
            }
          )
        )

      %{version: 1, captured_at: captured_at, complete: true, demand: demand, claims: claims, accounts: accounts}
    else
      %{version: 1, captured_at: captured_at, complete: false, demand: [], claims: [], accounts: []}
    end
  end
end
