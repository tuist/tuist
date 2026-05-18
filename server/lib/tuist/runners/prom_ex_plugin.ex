defmodule Tuist.Runners.PromExPlugin do
  @moduledoc """
  PromEx plugin for the customer-runner dispatch path.

  Two metric families:

    * **Event metrics.** Counters + duration histograms attached to
      the `:tuist, :runners, ...` events emitted by `Tuist.Runners`,
      `Tuist.Runners.Jobs`, `Tuist.Runners.Dispatch`, and the
      recovery workers. Counters cover throughput (`enqueued`,
      `claim`, `running`, `completed`); histograms cover wall-clock
      durations (`queue_time_ms` at claim, `queue_to_running_ms` at
      mint, `run_time_ms` / `total_time_ms` at completion). The
      dispatch endpoint emits its own latency histogram tagged by
      outcome so a saturating poll loop is visible separately from
      a slow CH/PG.

    * **Polling metrics.** Three poll loops at a coarse 30s cadence
      query authoritative state and emit gauges: queue length per
      fleet from CH, inflight claim counts per fleet / lifecycle
      state from PG, RunnerPool desired-vs-observed replica counts
      from the K8s apiserver. Polled gauges are deliberately
      separate from the event counters — `runner_pool_replicas` is
      a level (current capacity), not a flux (boot/teardown rate
      already covered by tart-kubelet's boot duration histogram).

  Cardinality budget: `fleet` is bounded by the number of
  RunnerPool CRs (currently 1 — `default`). Per-account fan-out is
  *not* tagged on event metrics; account-level views are exposed
  as polled aggregates only.
  """

  use PromEx.Plugin

  import Ecto.Query, only: [from: 2]

  alias Tuist.Accounts.Account
  alias Tuist.ClickHouseRepo
  alias Tuist.Environment
  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Repo
  alias Tuist.Runners.Claim
  alias Tuist.Runners.Job
  alias Tuist.Runners.Telemetry
  alias TuistCommon.Repo.PoolMetrics

  require Logger

  @metric_prefix [:tuist, :runners]

  # Buckets cover the realistic wall-clock range for each duration.
  # `queue_time` and `queue_to_running` are sub-minute on the happy
  # path; `run_time` / `total_time` span seconds to the GH-side
  # 6-hour ceiling, so the upper bucket sits at 6 * 3600 * 1000 ms.
  @short_duration_buckets [50, 100, 250, 500, 1_000, 2_500, 5_000, 10_000, 30_000, 60_000, 300_000]
  @long_duration_buckets [
    1_000,
    5_000,
    30_000,
    60_000,
    300_000,
    900_000,
    1_800_000,
    3_600_000,
    7_200_000,
    14_400_000,
    21_600_000
  ]
  @dispatch_duration_buckets [10, 50, 100, 250, 500, 1_000, 2_500, 5_000, 10_000]

  @impl true
  def event_metrics(_opts) do
    [
      Event.build(
        :tuist_runners_lifecycle_event_metrics,
        [
          counter(
            @metric_prefix ++ [:job, :enqueued, :count],
            event_name: Telemetry.event_name_job_enqueued(),
            description: "Workflow jobs enqueued for a Tuist-managed runner fleet.",
            tags: [:fleet]
          ),
          counter(
            @metric_prefix ++ [:job, :claim, :count],
            event_name: Telemetry.event_name_job_claim(),
            description: "Workflow jobs claimed off the queue by a polling runner Pod.",
            tags: [:fleet, :outcome]
          ),
          distribution(
            @metric_prefix ++ [:job, :queue, :time, :milliseconds],
            event_name: Telemetry.event_name_job_claim(),
            measurement: :queue_time_ms,
            description: "Time between webhook enqueue and the first successful claim.",
            reporter_options: [buckets: @short_duration_buckets],
            tags: [:fleet],
            unit: :millisecond
          ),
          counter(
            @metric_prefix ++ [:job, :running, :count],
            event_name: Telemetry.event_name_job_running(),
            description: "Workflow jobs that reached the running state after a successful JIT mint.",
            tags: [:fleet]
          ),
          distribution(
            @metric_prefix ++ [:job, :queue_to_running, :time, :milliseconds],
            event_name: Telemetry.event_name_job_running(),
            measurement: :queue_to_running_ms,
            description: "Time between webhook enqueue and the running transition (queue + claim + mint).",
            reporter_options: [buckets: @short_duration_buckets],
            tags: [:fleet],
            unit: :millisecond
          ),
          counter(
            @metric_prefix ++ [:job, :completed, :count],
            event_name: Telemetry.event_name_job_completed(),
            description: "Workflow jobs that reached a terminal GitHub conclusion.",
            tags: [:fleet, :conclusion]
          ),
          distribution(
            @metric_prefix ++ [:job, :run, :time, :milliseconds],
            event_name: Telemetry.event_name_job_completed(),
            measurement: :run_time_ms,
            description: "Time between running and completed — the actual execution window on the runner.",
            reporter_options: [buckets: @long_duration_buckets],
            tags: [:fleet],
            unit: :millisecond
          ),
          distribution(
            @metric_prefix ++ [:job, :total, :time, :milliseconds],
            event_name: Telemetry.event_name_job_completed(),
            measurement: :total_time_ms,
            description: "End-to-end time from webhook enqueue to completion.",
            reporter_options: [buckets: @long_duration_buckets],
            tags: [:fleet],
            unit: :millisecond
          ),
          counter(
            @metric_prefix ++ [:job, :requeued, :count],
            event_name: Telemetry.event_name_job_requeued(),
            description: "Workflow jobs returned to the queued state via release or recovery.",
            tags: [:fleet]
          )
        ]
      ),
      Event.build(
        :tuist_runners_dispatch_event_metrics,
        [
          counter(
            @metric_prefix ++ [:dispatch, :request, :count],
            event_name: Telemetry.event_name_dispatch_request(),
            description: "Polling Pod dispatch requests bucketed by outcome.",
            tags: [:outcome]
          ),
          distribution(
            @metric_prefix ++ [:dispatch, :request, :duration, :milliseconds],
            event_name: Telemetry.event_name_dispatch_request(),
            measurement: :duration_ms,
            description: "Wall-clock time the dispatch endpoint spent serving a polling Pod.",
            reporter_options: [buckets: @dispatch_duration_buckets],
            tags: [:outcome],
            unit: :millisecond
          )
        ]
      ),
      Event.build(
        :tuist_runners_webhook_event_metrics,
        [
          counter(
            @metric_prefix ++ [:webhook, :count],
            event_name: Telemetry.event_name_webhook(),
            description: "GitHub workflow_job webhook deliveries bucketed by action and outcome.",
            tags: [:action, :outcome]
          )
        ]
      ),
      Event.build(
        :tuist_runners_recovery_event_metrics,
        [
          counter(
            @metric_prefix ++ [:recovery, :count],
            event_name: Telemetry.event_name_recovery(),
            measurement: :count,
            description: "Stale or orphaned rows recovered by the recovery workers, by kind.",
            tags: [:kind]
          )
        ]
      )
    ]
  end

  @impl true
  def polling_metrics(opts) do
    poll_rate = Keyword.get(opts, :poll_rate, to_timeout(second: 30))

    [
      Polling.build(
        :tuist_runners_queue_length_metrics,
        poll_rate,
        {__MODULE__, :execute_queue_length_telemetry_event, []},
        [
          last_value(
            @metric_prefix ++ [:queue, :length],
            event_name: Telemetry.event_name_queue_length(),
            description: "Queued workflow jobs per fleet (ClickHouse runner_jobs).",
            measurement: :count,
            tags: [:fleet]
          )
        ]
      ),
      Polling.build(
        :tuist_runners_claims_metrics,
        poll_rate,
        {__MODULE__, :execute_claims_telemetry_event, []},
        [
          last_value(
            @metric_prefix ++ [:claims, :count],
            event_name: Telemetry.event_name_claims_count(),
            description: "Active PG claims per fleet and lifecycle state (claimed or running).",
            measurement: :count,
            tags: [:fleet, :lifecycle_state]
          )
        ]
      ),
      Polling.build(
        :tuist_runners_pool_replicas_metrics,
        poll_rate,
        {__MODULE__, :execute_pool_replicas_telemetry_event, []},
        [
          last_value(
            @metric_prefix ++ [:pool, :replicas, :desired],
            event_name: Telemetry.event_name_pool_replicas(),
            description: "Desired RunnerPool replicas (spec.replicas).",
            measurement: :desired,
            tags: [:fleet, :dispatch_label]
          ),
          last_value(
            @metric_prefix ++ [:pool, :replicas, :observed],
            event_name: Telemetry.event_name_pool_replicas(),
            description: "Observed RunnerPool replicas (status.observedReplicas).",
            measurement: :observed,
            tags: [:fleet, :dispatch_label]
          )
        ]
      ),
      Polling.build(
        :tuist_runners_accounts_enabled_metrics,
        poll_rate,
        {__MODULE__, :execute_accounts_enabled_telemetry_event, []},
        [
          last_value(
            @metric_prefix ++ [:accounts, :enabled],
            event_name: Telemetry.event_name_accounts_enabled(),
            description: "Accounts with runner_max_concurrent > 0.",
            measurement: :count
          )
        ]
      )
    ]
  end

  @doc false
  def execute_queue_length_telemetry_event do
    if PoolMetrics.running?(ClickHouseRepo) do
      query =
        from(j in Job,
          hints: ["FINAL"],
          where: j.status == "queued",
          group_by: j.fleet_name,
          select: {j.fleet_name, count(j.workflow_job_id)}
        )

      try_result =
        try do
          ClickHouseRepo.all(query)
        rescue
          e ->
            Logger.debug("runners: queue_length poll failed", reason: Exception.message(e))
            []
        end

      Enum.each(try_result, fn {fleet, count} ->
        :telemetry.execute(
          Telemetry.event_name_queue_length(),
          %{count: count},
          %{fleet: fleet || ""}
        )
      end)
    end
  end

  @doc false
  def execute_claims_telemetry_event do
    if PoolMetrics.running?(Repo) do
      query =
        from(c in Claim,
          group_by: [c.fleet_name, c.lifecycle_state],
          select: {c.fleet_name, c.lifecycle_state, count(c.workflow_job_id)}
        )

      try_result =
        try do
          Repo.all(query)
        rescue
          e ->
            Logger.debug("runners: claims poll failed", reason: Exception.message(e))
            []
        end

      Enum.each(try_result, fn {fleet, state, count} ->
        :telemetry.execute(
          Telemetry.event_name_claims_count(),
          %{count: count},
          %{fleet: fleet || "", lifecycle_state: state || ""}
        )
      end)
    end
  end

  @doc false
  def execute_pool_replicas_telemetry_event do
    case safe_list_runner_pools() do
      {:ok, items} ->
        Enum.each(items, &emit_pool_replicas/1)

      _ ->
        :ok
    end
  end

  @doc false
  def execute_accounts_enabled_telemetry_event do
    if PoolMetrics.running?(Repo) do
      count =
        try do
          Repo.one(
            from(a in Account,
              where: not is_nil(a.runner_max_concurrent) and a.runner_max_concurrent > 0,
              select: count(a.id)
            )
          ) || 0
        rescue
          e ->
            Logger.debug("runners: accounts_enabled poll failed", reason: Exception.message(e))
            0
        end

      :telemetry.execute(
        Telemetry.event_name_accounts_enabled(),
        %{count: count},
        %{}
      )
    end
  end

  defp safe_list_runner_pools do
    K8sClient.list_runner_pools(Environment.runners_namespace())
  rescue
    e ->
      Logger.debug("runners: pool replicas poll failed", reason: Exception.message(e))
      :error
  end

  defp emit_pool_replicas(%{"metadata" => %{"name" => name}} = pool) do
    spec = Map.get(pool, "spec", %{})
    status = Map.get(pool, "status", %{})

    :telemetry.execute(
      Telemetry.event_name_pool_replicas(),
      %{
        desired: Map.get(spec, "replicas", 0),
        observed: Map.get(status, "observedReplicas", 0)
      },
      %{
        fleet: name,
        dispatch_label: Map.get(spec, "dispatchLabel", "")
      }
    )
  end

  defp emit_pool_replicas(_), do: :ok
end
