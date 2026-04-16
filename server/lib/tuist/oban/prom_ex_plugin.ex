defmodule Tuist.Oban.PromExPlugin do
  @moduledoc """
  Replaces PromEx.Plugins.Oban's :oban_job_event_metrics group with a
  version whose duration histogram buckets extend up to 30 minutes,
  so histogram_quantile can resolve p99/p95 for long-running workers
  (e.g. Tuist.Builds.Workers.ProcessBuildWorker).

  The upstream group is dropped via drop_metrics_groups in Tuist.PromEx
  config; this plugin re-emits the same metric names so the PromEx
  Oban Grafana dashboard continues to work unchanged.
  """
  use PromEx.Plugin

  @job_complete_event [:oban, :job, :stop]
  @job_exception_event [:oban, :job, :exception]

  @impl true
  def event_metrics(opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)
    metric_prefix = PromEx.metric_prefix(otp_app, :oban)

    job_attempt_buckets = [1, 5, 10]
    job_duration_buckets = [10, 100, 500, 1_000, 5_000, 20_000, 60_000, 300_000, 600_000, 1_800_000]

    Event.build(
      :oban_job_event_metrics,
      [
        distribution(
          metric_prefix ++ [:job, :processing, :duration, :milliseconds],
          event_name: @job_complete_event,
          measurement: :duration,
          description: "The amount of time it takes to process an Oban job.",
          reporter_options: [buckets: job_duration_buckets],
          tag_values: &job_complete_tag_values/1,
          tags: [:name, :queue, :state, :worker],
          unit: {:native, :millisecond}
        ),
        distribution(
          metric_prefix ++ [:job, :queue, :time, :milliseconds],
          event_name: @job_complete_event,
          measurement: :queue_time,
          description: "The amount of time that the Oban job was waiting in queue for processing.",
          reporter_options: [buckets: job_duration_buckets],
          tag_values: &job_complete_tag_values/1,
          tags: [:name, :queue, :state, :worker],
          unit: {:native, :millisecond}
        ),
        distribution(
          metric_prefix ++ [:job, :complete, :attempts],
          event_name: @job_complete_event,
          measurement: fn _measurement, %{attempt: attempt} -> attempt end,
          description: "The number of times a job was attempted prior to completing.",
          reporter_options: [buckets: job_attempt_buckets],
          tag_values: &job_complete_tag_values/1,
          tags: [:name, :queue, :state, :worker]
        ),
        distribution(
          metric_prefix ++ [:job, :exception, :duration, :milliseconds],
          event_name: @job_exception_event,
          measurement: :duration,
          description: "The amount of time it took to process a job that encountered an exception.",
          reporter_options: [buckets: job_duration_buckets],
          tag_values: &job_exception_tag_values/1,
          tags: [:name, :queue, :state, :worker, :kind, :error],
          unit: {:native, :millisecond}
        ),
        distribution(
          metric_prefix ++ [:job, :exception, :queue, :time, :milliseconds],
          event_name: @job_exception_event,
          measurement: :queue_time,
          description:
            "The amount of time that the Oban job was waiting in queue for processing prior to resulting in an exception.",
          reporter_options: [buckets: job_duration_buckets],
          tag_values: &job_exception_tag_values/1,
          tags: [:name, :queue, :state, :worker, :kind, :error],
          unit: {:native, :millisecond}
        ),
        distribution(
          metric_prefix ++ [:job, :exception, :attempts],
          event_name: @job_exception_event,
          measurement: fn _measurement, %{attempt: attempt} -> attempt end,
          description: "The number of times a job was attempted prior to throwing an exception.",
          reporter_options: [buckets: job_attempt_buckets],
          tag_values: &job_exception_tag_values/1,
          tags: [:name, :queue, :state, :worker]
        )
      ]
    )
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

  defp config_from_metadata(%{config: config}), do: config
  defp config_from_metadata(%{conf: config}), do: config

  defp normalize_module_name(name) when is_atom(name) do
    name |> Atom.to_string() |> String.trim_leading("Elixir.")
  end

  defp normalize_module_name(name), do: name
end
