defmodule Tuist.Tasks do
  @moduledoc false

  alias Tuist.Observability

  require OpenTelemetry.Tracer

  @task_timeout 60_000

  def run_async(fun) do
    snapshot = Observability.snapshot()

    if sync?() do
      Observability.with_snapshot(snapshot, fun)
      {:ok, self()}
    else
      Task.start(fn ->
        Observability.attach(snapshot)

        OpenTelemetry.Tracer.with_span "tuist.task" do
          Observability.refresh()
          fun.()
        end
      end)
    end
  end

  def parallel_tasks(queries, opts \\ []) do
    max_concurrency = Keyword.get(opts, :max_concurrency, 3)
    snapshot = Observability.snapshot()

    queries
    |> Task.async_stream(
      fn fun ->
        Observability.attach(snapshot)

        OpenTelemetry.Tracer.with_span "tuist.task" do
          Observability.refresh()
          fun.()
        end
      end,
      max_concurrency: max_concurrency,
      timeout: @task_timeout
    )
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, {exception, stacktrace}} when is_exception(exception) -> reraise(exception, stacktrace)
      {:exit, reason} -> exit(reason)
    end)
  end

  defp sync? do
    :tuist
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:sync, false)
  end
end
