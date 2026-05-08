defmodule Tuist.Oban.PromExPlugin do
  @moduledoc """
  Oban metrics plugin emitting job event metrics (with extended
  duration histogram buckets), queue length polling metrics, a
  per-worker recent-terminal-state polling metric (so alerts can see
  failures from workers that run on pods Alloy can't scrape), and
  producer event metrics.
  """
  use PromEx.Plugin

  import Ecto.Query, only: [from: 2, group_by: 3, select: 3]

  @job_complete_event [:oban, :job, :stop]
  @job_exception_event [:oban, :job, :exception]
  @producer_complete_event [:oban, :producer, :stop]
  @producer_exception_event [:oban, :producer, :exception]

  @metric_prefix [:tuist, :oban]

  @job_duration_buckets [10, 100, 500, 1_000, 5_000, 20_000, 60_000, 300_000, 600_000, 1_800_000]
  @job_attempt_buckets [1, 5, 10]
  @producer_duration_buckets [10, 100, 500, 1_000, 5_000, 10_000]
  @producer_dispatch_buckets [5, 10, 50, 100]

  # Lookback window for the per-worker terminal-state poll. Anything
  # older drops out of the gauge so a single discard doesn't keep an
  # alert firing for the full 7-day Pruner retention.
  @recent_terminal_window_seconds 30 * 60
  @recent_terminal_states ~w(discarded cancelled)

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
            event_name: [:prom_ex, :plugin, :oban, :queue, :length, :count],
            description: "The total number of jobs in the queue in the designated state.",
            measurement: :count,
            tags: [:name, :queue, :state]
          )
        ]
      ),
      # Per-worker counts of jobs that landed in a terminal failure
      # state recently. Polled from oban_jobs so the metric is emitted
      # by every PromEx-enabled pod regardless of which pod processed
      # the job. That matters for workers like ProcessXcresultWorker
      # that only run on the macOS xcresult-processor fleet, where the
      # Tart VM pods aren't reachable from the in-cluster Alloy
      # scrapers — alerts can read this gauge from a web pod instead.
      Polling.build(
        :oban_recent_terminal_poll_metrics,
        60_000,
        {__MODULE__, :execute_recent_terminal_metrics, []},
        [
          last_value(
            @metric_prefix ++ [:jobs, :recent, :terminal, :count],
            event_name: [:prom_ex, :plugin, :oban, :jobs, :recent, :terminal, :count],
            description:
              "Jobs that entered a terminal failure state (discarded, cancelled) in the last #{div(@recent_terminal_window_seconds, 60)} minutes, grouped by queue, state, and worker.",
            measurement: :count,
            tags: [:name, :queue, :state, :worker]
          )
        ]
      )
    ]
  end

  def execute_queue_metrics do
    case Oban.Registry.whereis(Oban) do
      oban_pid when is_pid(oban_pid) ->
        config = Oban.Registry.config(Oban)

        query =
          Oban.Job
          |> group_by([j], [j.queue, j.state])
          |> select([j], {j.queue, j.state, count(j.id)})

        config
        |> Oban.Repo.all(query)
        |> include_zeros_for_missing_queue_states()
        |> Enum.each(fn {{queue, state}, count} ->
          :telemetry.execute(
            [:prom_ex, :plugin, :oban, :queue, :length, :count],
            %{count: count},
            %{name: normalize_module_name(Oban), queue: queue, state: state}
          )
        end)

      _ ->
        :ok
    end
  end

  def execute_recent_terminal_metrics do
    case Oban.Registry.whereis(Oban) do
      oban_pid when is_pid(oban_pid) ->
        config = Oban.Registry.config(Oban)
        cutoff = DateTime.add(DateTime.utc_now(), -@recent_terminal_window_seconds, :second)

        # Group over every (queue, state, worker) that has at least one
        # row in a terminal state (bounded by the Pruner retention) and
        # use FILTER to count just the rows whose discard/cancel
        # timestamp is inside the lookback window. That keeps the
        # labelset universe stable across polls so a count drops cleanly
        # to 0 when the last in-window row ages out — without that, the
        # last_value gauge would hold the previous positive sample
        # forever and the alert would never clear.
        query =
          from j in Oban.Job,
            where: j.state in ^@recent_terminal_states,
            group_by: [j.queue, j.state, j.worker],
            select:
              {j.queue, j.state, j.worker,
               fragment(
                 "COUNT(*) FILTER (WHERE COALESCE(?, ?) > ?)",
                 j.discarded_at,
                 j.cancelled_at,
                 ^cutoff
               )}

        config
        |> Oban.Repo.all(query)
        |> Enum.each(fn {queue, state, worker, count} ->
          :telemetry.execute(
            [:prom_ex, :plugin, :oban, :jobs, :recent, :terminal, :count],
            %{count: count},
            %{name: normalize_module_name(Oban), queue: queue, state: state, worker: worker}
          )
        end)

      _ ->
        :ok
    end
  end

  defp include_zeros_for_missing_queue_states(query_result) do
    {_, opts} =
      Enum.find(Oban.config().plugins, {nil, [queues: Oban.config().queues]}, fn {plugin, _} ->
        plugin == Oban.Pro.Plugins.DynamicQueues
      end)

    all_queues =
      opts
      |> Keyword.get(:queues, [])
      |> Keyword.keys()

    all_states = Oban.Job.states()

    zeros = for queue <- all_queues, state <- all_states, into: %{}, do: {{to_string(queue), to_string(state)}, 0}
    counts = for {queue, state, count} <- query_result, into: %{}, do: {{queue, state}, count}

    Map.merge(zeros, counts)
  end

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
