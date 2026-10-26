defmodule Atlas.Automations.TelemetryHandler do
  @moduledoc "Records process-loss diagnostics after Oban acknowledges a failed automation delivery."

  alias Atlas.Automations.Executor
  alias Atlas.Automations.Observability

  require Logger

  def attach do
    :telemetry.attach("atlas-automation-worker-failures", [:oban, :job, :exception], &__MODULE__.handle_event/4, nil)
  end

  def handle_event(
        _event,
        _measurements,
        %{job: %{worker: "Atlas.Automations.Workers.ExecuteRun", id: id} = job} = metadata,
        _config
      )
      when not is_nil(id) do
    diagnostic = Observability.diagnostic(:exit, metadata[:reason], Map.get(metadata, :stacktrace, []))
    Executor.record_transport_failure(job, diagnostic)
  rescue
    _ -> Logger.warning("Automation transport diagnostics could not be persisted.")
  catch
    _, _ -> :ok
  end

  def handle_event(_, _, _, _), do: :ok
end
