defmodule Tuist.Oban.PromExPlugin do
  @moduledoc """
  Oban metrics plugin emitting job event metrics (with extended
  duration histogram buckets), queue length and queue age polling
  metrics, and producer event metrics.

  The polled gauges are read from the shared `oban_jobs` table rather
  than from this node's own producers, so a queue consumed by a
  separate deployment (`:process_xcresult` on the macOS fleet,
  `:process_build` on the Linux processors) is still reported by every
  node that runs this plugin. That is deliberate: it makes "the only
  consumer of this queue is gone" observable from a node that is
  itself healthy.

  Those queue-level gauges answer "is this queue being drained at all".
  They cannot answer "is every consumer of it healthy": one broken
  consumer beside a working one leaves the queue draining normally. The
  `node_last_attempt/completion_timestamp_seconds` pair covers that case
  from the opposite direction, reported by each consumer about itself.

  Both of those only turn positive once a consumer has already stopped
  finishing work. `node_executing_jobs_count` against `node_queue_limit`
  is the earlier signal: a consumer that has lost slots keeps completing
  jobs on the ones it still holds, so every other gauge reads healthy
  while its capacity decays. On 2026-08-31 both production xcresult
  processors sat at 3 in-flight jobs against a configured limit of 6,
  with a 3000-job backlog available to fill them; a restart restored
  both to 6. A node below its own limit while the queue has work is
  losing capacity, and it is visible long before throughput reaches zero.
  """
  use PromEx.Plugin

  import Ecto.Query, only: [group_by: 3, select: 3, where: 3]

  alias Tuist.Environment

  @job_start_event [:oban, :job, :start]
  @job_complete_event [:oban, :job, :stop]
  @job_exception_event [:oban, :job, :exception]
  @producer_complete_event [:oban, :producer, :stop]
  @producer_exception_event [:oban, :producer, :exception]

  @metric_prefix [:tuist, :oban]

  @queue_length_event [:prom_ex, :plugin, :oban, :queue, :length, :count]
  @queue_age_event [:prom_ex, :plugin, :oban, :queue, :oldest, :available, :age, :seconds]
  @node_slots_event [:prom_ex, :plugin, :oban, :node, :slots]

  # Process-dict key holding the set of queues reported on the previous
  # poll, so a queue that drains to nothing still gets an explicit zero.
  @queues_seen_key :tuist_oban_queue_metrics_seen_queues

  @job_duration_buckets [10, 100, 500, 1_000, 5_000, 20_000, 60_000, 300_000, 600_000, 1_800_000]
  @job_attempt_buckets [1, 5, 10]
  @producer_duration_buckets [10, 100, 500, 1_000, 5_000, 10_000]
  @producer_dispatch_buckets [5, 10, 50, 100]

  @impl true
  def event_metrics(_opts) do
    [
      Event.build(
        :oban_job_event_metrics,
        [
          distribution(
            @metric_prefix ++ [:job, :processing, :duration, :milliseconds],
            event_name: @job_complete_event,
            measurement: :duration,
            description: "The amount of time it takes to process an Oban job.",
            reporter_options: [buckets: @job_duration_buckets],
            tag_values: &job_complete_tag_values/1,
            tags: [:name, :queue, :state, :worker],
            unit: {:native, :millisecond}
          ),
          distribution(
            @metric_prefix ++ [:job, :queue, :time, :milliseconds],
            event_name: @job_complete_event,
            measurement: :queue_time,
            description: "The amount of time that the Oban job was waiting in queue for processing.",
            reporter_options: [buckets: @job_duration_buckets],
            tag_values: &job_complete_tag_values/1,
            tags: [:name, :queue, :state, :worker],
            unit: {:native, :millisecond}
          ),
          distribution(
            @metric_prefix ++ [:job, :complete, :attempts],
            event_name: @job_complete_event,
            measurement: fn _measurement, %{attempt: attempt} -> attempt end,
            description: "The number of times a job was attempted prior to completing.",
            reporter_options: [buckets: @job_attempt_buckets],
            tag_values: &job_complete_tag_values/1,
            tags: [:name, :queue, :state, :worker]
          ),
          distribution(
            @metric_prefix ++ [:job, :exception, :duration, :milliseconds],
            event_name: @job_exception_event,
            measurement: :duration,
            description: "The amount of time it took to process a job that encountered an exception.",
            reporter_options: [buckets: @job_duration_buckets],
            tag_values: &job_exception_tag_values/1,
            tags: [:name, :queue, :state, :worker, :kind, :error],
            unit: {:native, :millisecond}
          ),
          distribution(
            @metric_prefix ++ [:job, :exception, :queue, :time, :milliseconds],
            event_name: @job_exception_event,
            measurement: :queue_time,
            description: "The amount of time that the Oban job was waiting in queue prior to an exception.",
            reporter_options: [buckets: @job_duration_buckets],
            tag_values: &job_exception_tag_values/1,
            tags: [:name, :queue, :state, :worker, :kind, :error],
            unit: {:native, :millisecond}
          ),
          distribution(
            @metric_prefix ++ [:job, :exception, :attempts],
            event_name: @job_exception_event,
            measurement: fn _measurement, %{attempt: attempt} -> attempt end,
            description: "The number of times a job was attempted prior to throwing an exception.",
            reporter_options: [buckets: @job_attempt_buckets],
            tag_values: &job_exception_tag_values/1,
            tags: [:name, :queue, :state, :worker]
          )
        ]
      ),
      Event.build(
        :oban_node_liveness_metrics,
        [
          last_value(
            @metric_prefix ++ [:node, :last, :attempt, :timestamp, :seconds],
            event_name: @job_start_event,
            measurement: &current_unix_second/2,
            description: "Unix timestamp of the last job this node started on the queue.",
            tag_values: &node_liveness_tag_values/1,
            tags: [:name, :queue, :node]
          ),
          last_value(
            @metric_prefix ++ [:node, :last, :completion, :timestamp, :seconds],
            event_name: @job_complete_event,
            measurement: &current_unix_second/2,
            description: "Unix timestamp of the last job this node completed on the queue.",
            tag_values: &node_liveness_tag_values/1,
            tags: [:name, :queue, :node]
          )
        ]
      ),
      Event.build(
        :oban_producer_event_metrics,
        [
          distribution(
            @metric_prefix ++ [:producer, :duration, :milliseconds],
            event_name: @producer_complete_event,
            measurement: :duration,
            description: "How long it took to dispatch the job.",
            reporter_options: [buckets: @producer_duration_buckets],
            unit: {:native, :millisecond},
            tag_values: &producer_tag_values/1,
            tags: [:queue, :name]
          ),
          distribution(
            @metric_prefix ++ [:producer, :dispatched, :count],
            event_name: @producer_complete_event,
            measurement: fn _measurement, %{dispatched_count: count} -> count end,
            description: "The number of jobs that were dispatched.",
            reporter_options: [buckets: @producer_dispatch_buckets],
            tag_values: &producer_tag_values/1,
            tags: [:queue, :name]
          ),
          distribution(
            @metric_prefix ++ [:producer, :exception, :duration, :milliseconds],
            event_name: @producer_exception_event,
            measurement: :duration,
            description: "How long it took for the producer to raise an exception.",
            reporter_options: [buckets: @producer_duration_buckets],
            unit: {:native, :millisecond},
            tag_values: &producer_tag_values/1,
            tags: [:queue, :name]
          )
        ]
      )
    ]
  end

  @impl true
  def polling_metrics(_opts) do
    [
      Polling.build(
        :oban_queue_poll_metrics,
        5_000,
        {__MODULE__, :execute_queue_metrics, []},
        [
          last_value(
            @metric_prefix ++ [:queue, :length, :count],
            event_name: @queue_length_event,
            description: "The total number of jobs in the queue in the designated state.",
            measurement: :count,
            tags: [:name, :queue, :state]
          ),
          # Rides the same scan as the length gauge. Depth alone reads
          # identically for a queue that is never empty because arrivals
          # are served promptly and a queue with no consumer at all:
          # both sit at a non-zero count. Age separates them, and it is
          # the signal that keeps climbing while nothing drains.
          last_value(
            @metric_prefix ++ [:queue, :oldest, :available, :age, :seconds],
            event_name: @queue_age_event,
            description:
              "Age in seconds of the oldest job sitting in the `available` state for a queue (0 when nothing is available).",
            measurement: :age_seconds,
            tags: [:name, :queue]
          ),
          last_value(
            @metric_prefix ++ [:node, :executing, :jobs, :count],
            event_name: @node_slots_event,
            description: "Number of jobs this node currently holds in the `executing` state for a queue.",
            measurement: :executing,
            tags: [:name, :queue, :node]
          ),
          # Emitted beside the count rather than baked into an alert
          # threshold: the limit is per environment (production runs
          # `queueConcurrency: 6`, the in-code default is 4), so a rule
          # comparing the two stays correct when an environment is
          # retuned.
          last_value(
            @metric_prefix ++ [:node, :queue, :limit],
            event_name: @node_slots_event,
            description: "Configured concurrency limit of a queue this node runs.",
            measurement: :limit,
            tags: [:name, :queue, :node]
          )
        ]
      )
    ]
  end

  def execute_queue_metrics do
    case Oban.Registry.whereis(Oban) do
      oban_pid when is_pid(oban_pid) ->
        config = Oban.Registry.config(Oban)
        now = DateTime.utc_now()

        query =
          Oban.Job
          |> group_by([j], [j.queue, j.state])
          |> select([j], {j.queue, j.state, count(j.id), min(j.scheduled_at)})

        rows = Oban.Repo.all(config, query)
        name = normalize_module_name(Oban)
        queues = observed_queues(rows)

        rows
        |> include_zeros_for_missing_queue_states(queues)
        |> Enum.each(fn {{queue, state}, count} ->
          :telemetry.execute(@queue_length_event, %{count: count}, %{name: name, queue: queue, state: state})
        end)

        oldest_available = oldest_available_scheduled_at(rows)

        Enum.each(queues, fn queue ->
          :telemetry.execute(
            @queue_age_event,
            %{age_seconds: age_seconds(now, Map.get(oldest_available, queue))},
            %{name: name, queue: queue}
          )
        end)

        execute_node_slot_metrics(config, name)

        Process.put(@queues_seen_key, queues)

      _ ->
        :ok
    end
  end

  # Counted from `oban_jobs` rather than from this node's producers so
  # the number means "work this node is credited with" — the same
  # `attempted_by` a stuck-consumer investigation greps for. A slot lost
  # inside a stalled NIF stops producing rows here while the producer
  # still believes it is occupied, which is exactly the divergence the
  # gauge exists to expose.
  defp execute_node_slot_metrics(config, name) do
    limits = configured_queue_limits()

    executing =
      config
      |> Oban.Repo.all(
        Oban.Job
        |> where([j], j.state == "executing")
        |> where([j], fragment("?[1]", j.attempted_by) == ^config.node)
        |> group_by([j], j.queue)
        |> select([j], {j.queue, count(j.id)})
      )
      |> Map.new()

    limits
    |> Map.keys()
    |> MapSet.new()
    |> MapSet.union(MapSet.new(Map.keys(executing)))
    |> Enum.each(fn queue ->
      measurements =
        case Map.fetch(limits, queue) do
          {:ok, limit} -> %{executing: Map.get(executing, queue, 0), limit: limit}
          :error -> %{executing: Map.get(executing, queue, 0)}
        end

      :telemetry.execute(@node_slots_event, measurements, %{name: name, queue: queue, node: config.node})
    end)
  end

  # Keyed by the queue's string name to match what the `oban_jobs` scan
  # returns; `String.to_existing_atom/1` on a queue name read back from
  # the table would raise for a queue this node does not run.
  # A queue can be configured as a bare integer, as opts carrying
  # `:limit`, or as `false` to disable it. Only the ones that resolve to
  # a number get a limit gauge; the rest still report their executing
  # count, just without anything to compare it against.
  defp configured_queue_limits do
    configured_queue_opts()
    |> Enum.flat_map(fn {queue, opts} ->
      case queue_limit(opts) do
        limit when is_integer(limit) -> [{to_string(queue), limit}]
        _ -> []
      end
    end)
    |> Map.new()
  end

  defp queue_limit(limit) when is_integer(limit), do: limit
  defp queue_limit(opts) when is_list(opts), do: Keyword.get(opts, :limit)
  defp queue_limit(_opts), do: nil

  # Every queue the gauges must report on this tick: the ones this node
  # runs, the ones the scan saw rows for (a queue delegated to another
  # deployment still has rows in the shared `oban_jobs` table), and the
  # ones reported on the previous tick. The last set is load-bearing: a
  # queue that fully drains stops appearing in the scan, and without an
  # explicit zero `last_value` would hold its final non-zero sample
  # forever, leaving a queue-age alert that never clears once it fires.
  defp observed_queues(rows) do
    configured = MapSet.new(configured_queues() ++ delegated_queues(), &to_string/1)
    scanned = MapSet.new(rows, fn {queue, _state, _count, _oldest} -> queue end)

    @queues_seen_key
    |> Process.get(MapSet.new())
    |> MapSet.union(configured)
    |> MapSet.union(scanned)
    |> MapSet.delete(nil)
  end

  # Queues this node deliberately does not run because a dedicated
  # deployment consumes them. Reporting on them anyway is the point: a
  # node that delegates is the one best placed to observe that the
  # delegate has gone away, and it keeps the gauge present even during a
  # window where the queue happens to hold no rows at all. Otherwise the
  # series would simply be absent, which a threshold alert reads as
  # healthy.
  defp delegated_queues do
    [
      {:process_build, Environment.delegate_process_build?()},
      {:process_bazel_tests, Environment.delegate_process_bazel_tests?()},
      {:process_xcresult, Environment.delegate_process_xcresult?()}
    ]
    |> Enum.filter(&elem(&1, 1))
    |> Enum.map(&elem(&1, 0))
  end

  defp configured_queues, do: Keyword.keys(configured_queue_opts())

  defp configured_queue_opts do
    {_, opts} =
      Enum.find(Oban.config().plugins, {nil, [queues: Oban.config().queues]}, fn {plugin, _} ->
        plugin == Oban.Pro.Plugins.DynamicQueues
      end)

    Keyword.get(opts, :queues, [])
  end

  defp include_zeros_for_missing_queue_states(query_result, queues) do
    all_states = Oban.Job.states()

    zeros = for queue <- queues, state <- all_states, into: %{}, do: {{queue, to_string(state)}, 0}
    counts = for {queue, state, count, _oldest} <- query_result, into: %{}, do: {{queue, state}, count}

    Map.merge(zeros, counts)
  end

  # `available` is the only state whose `scheduled_at` is a "ready since"
  # timestamp. `scheduled` and `retryable` carry a future run-at, and
  # `executing` jobs are by definition being drained, so including them
  # would report a healthy queue as stalled or a stalled one as healthy.
  defp oldest_available_scheduled_at(rows) do
    for {queue, "available", _count, oldest} <- rows, not is_nil(oldest), into: %{}, do: {queue, oldest}
  end

  # Clamped at 0 so clock skew between the node that inserted the job and
  # the node polling cannot report a negative age, which would read as a
  # healthy queue.
  defp age_seconds(_now, nil), do: 0
  defp age_seconds(now, %DateTime{} = scheduled_at), do: now |> DateTime.diff(scheduled_at, :second) |> max(0)

  defp age_seconds(now, %NaiveDateTime{} = scheduled_at),
    do: age_seconds(now, DateTime.from_naive!(scheduled_at, "Etc/UTC"))

  # Absolute timestamps rather than a "seconds since" gauge, so the pair
  # needs no state between events and no scan of `oban_jobs`. The elapsed
  # time is `time() - <gauge>` at query time, which is also what makes a
  # node that stops reporting fall out of the alert as absent rather than
  # as a stale healthy-looking sample.
  #
  # Reported per node because the failure this pair exists to catch is
  # per-consumer, not per-queue: on 2026-08-25 one of two xcresult
  # processors took jobs for 14 hours and completed none, while its
  # sibling kept `available` at 0. Every queue-level gauge, including
  # `queue_oldest_available_age_seconds`, read perfectly healthy
  # throughout.
  #
  # `node` is Oban's own node name, the same value it writes into
  # `oban_jobs.attempted_by`, so a firing alert names the row you can go
  # and query.
  defp node_liveness_tag_values(metadata) do
    config = config_from_metadata(metadata)

    %{
      name: normalize_module_name(config.name),
      queue: metadata.job.queue,
      node: config.node
    }
  end

  defp current_unix_second(_measurements, _metadata), do: System.system_time(:second)

  defp job_complete_tag_values(metadata) do
    config = config_from_metadata(metadata)

    %{
      name: normalize_module_name(config.name),
      queue: metadata.job.queue,
      state: metadata.state,
      worker: metadata.worker
    }
  end

  defp job_exception_tag_values(metadata) do
    config = config_from_metadata(metadata)

    error =
      case metadata.error do
        %error_type{} -> normalize_module_name(error_type)
        _ -> "Undefined"
      end

    %{
      name: normalize_module_name(config.name),
      queue: metadata.job.queue,
      state: metadata.state,
      worker: metadata.worker,
      kind: metadata.kind,
      error: error
    }
  end

  defp producer_tag_values(metadata) do
    %{
      queue: metadata.queue,
      name: normalize_module_name(metadata.conf.name)
    }
  end

  defp config_from_metadata(%{config: config}), do: config
  defp config_from_metadata(%{conf: config}), do: config

  defp normalize_module_name(name) when is_atom(name) do
    name |> Atom.to_string() |> String.trim_leading("Elixir.")
  end

  defp normalize_module_name(name), do: name
end
