defmodule TuistCommon.ObanTelemetry do
  @moduledoc """
  Shared Oban telemetry handlers for Tuist services.
  """

  def attach do
    :telemetry.attach(
      "oban-exception-reporter",
      [:oban, :job, :exception],
      &__MODULE__.handle_exception/4,
      :no_config
    )
  end

  def handle_exception(
        [:oban, :job, :exception],
        _measurements,
        %{state: state, job: job, kind: kind, reason: reason, stacktrace: stacktrace},
        :no_config
      )
      when state in [:failure, :discard] do
    exception = Exception.normalize(kind, reason, stacktrace)

    Sentry.capture_exception(exception,
      stacktrace: stacktrace,
      tags: %{oban_worker: job.worker, oban_queue: job.queue, oban_state: to_string(state)},
      fingerprint: [job.worker, "{{ default }}"],
      extra:
        job
        |> Map.take([:args, :attempt, :id, :max_attempts, :queue, :worker])
        |> Map.put(:oban_state, state)
    )
  end

  def handle_exception([:oban, :job, :exception], _measurements, _metadata, :no_config), do: :ok
end
