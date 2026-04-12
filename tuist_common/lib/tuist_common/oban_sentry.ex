defmodule TuistCommon.ObanSentry do
  @moduledoc """
  Reports Oban job failures to Sentry only when all retry attempts have been exhausted.
  """

  def attach do
    :telemetry.attach(
      "oban-sentry-discard",
      [:oban, :job, :exception],
      &handle_event/4,
      :no_config
    )
  end

  def handle_event(
        [:oban, :job, :exception],
        _measurements,
        %{job: %{attempt: attempt, max_attempts: max_attempts} = job, kind: kind, reason: reason, stacktrace: stacktrace},
        :no_config
      )
      when attempt >= max_attempts do
    exception = Exception.normalize(kind, reason, stacktrace)

    Sentry.capture_exception(exception,
      stacktrace: stacktrace,
      tags: %{oban_worker: job.worker, oban_queue: job.queue},
      fingerprint: [job.worker, "{{ default }}"],
      extra: Map.take(job, [:args, :attempt, :id, :max_attempts, :queue, :worker])
    )
  end

  def handle_event([:oban, :job, :exception], _measurements, _metadata, :no_config), do: :ok
end
