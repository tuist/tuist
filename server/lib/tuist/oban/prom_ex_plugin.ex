defmodule Tuist.Oban.PromExPlugin do
  @moduledoc """
  Emits Oban job processing metrics with Tuist-tuned histogram buckets.

  PromEx.Plugins.Oban's processing duration histogram caps at 20s,
  which prevents p99 alerts from firing on workers whose normal
  workload exceeds that (e.g. ProcessBuildWorker). This plugin emits
  a parallel distribution on the same Oban telemetry event with
  buckets extending to 30 minutes.
  """
  use PromEx.Plugin

  @impl true
  def event_metrics(_opts) do
    [
      Event.build(
        :tuist_oban_job_event_metrics,
        [
          distribution(
            [:tuist, :oban, :job, :processing, :duration, :milliseconds],
            event_name: [:oban, :job, :stop],
            measurement: :duration,
            description: "Oban job processing duration with extended buckets for long-running workers.",
            reporter_options: [
              buckets: [10, 100, 500, 1_000, 5_000, 20_000, 60_000, 300_000, 600_000, 1_800_000]
            ],
            tag_values: &job_tag_values/1,
            tags: [:name, :queue, :worker, :state],
            unit: {:native, :millisecond}
          )
        ]
      )
    ]
  end

  defp job_tag_values(metadata) do
    config =
      case metadata do
        %{config: config} -> config
        %{conf: config} -> config
      end

    %{
      name: config.name |> Atom.to_string() |> String.trim_leading("Elixir."),
      queue: metadata.job.queue,
      worker: metadata.worker,
      state: metadata.state
    }
  end
end
