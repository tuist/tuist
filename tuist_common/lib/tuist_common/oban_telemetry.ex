defmodule TuistCommon.ObanTelemetry do
  @moduledoc """
  Shared Oban telemetry handlers for Tuist services.
  """

  def attach do
    :telemetry.attach(
      "oban-discard-error-reporter",
      [:oban, :job, :exception],
      &__MODULE__.handle_exception/4,
      :no_config
    )
  end

  def handle_exception(
        [:oban, :job, :exception],
        _measurements,
        %{state: :discard, job: job, kind: kind, reason: reason, stacktrace: stacktrace},
        :no_config
      ) do
    exception = Exception.normalize(kind, reason, stacktrace)

    Sentry.capture_exception(exception,
      stacktrace: stacktrace,
      tags: %{oban_worker: job.worker, oban_queue: job.queue},
      fingerprint: [job.worker, "{{ default }}"],
      extra: Map.take(job, [:args, :attempt, :id, :max_attempts, :queue, :worker])
    )
  end

  def handle_exception([:oban, :job, :exception], _measurements, _metadata, :no_config), do: :ok
end
