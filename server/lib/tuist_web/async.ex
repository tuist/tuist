defmodule TuistWeb.Async do
  @moduledoc """
  `assign_async/4` for every LiveView in `TuistWeb`, imported in place of
  `Phoenix.LiveView.assign_async/4`.

  The function runs exactly as it would under `Phoenix.LiveView.assign_async/4`;
  on top, its wall-clock and outcome are emitted as
  `Tuist.Telemetry.event_name_live_view_assign_async/0` with the view module,
  which `Tuist.LiveView.PromExPlugin` turns into a histogram. A function that
  raises is reported as `:exception` and re-raised, so the LiveView still ends
  in `AsyncResult.failed` and the crash still reaches the error tracker.
  """

  alias Tuist.Telemetry

  defmacro assign_async(socket, key_or_keys, func, opts \\ []) do
    quote do
      socket = unquote(socket)
      view = socket.view

      Phoenix.LiveView.assign_async(
        socket,
        unquote(key_or_keys),
        fn -> TuistWeb.Async.measure(view, unquote(func)) end,
        unquote(opts)
      )
    end
  end

  def measure(view, func) do
    started_at = System.monotonic_time()

    try do
      result = func.()
      emit(view, started_at, result_tag(result))
      result
    catch
      kind, reason ->
        emit(view, started_at, :exception)
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  defp emit(view, started_at, result) do
    :telemetry.execute(
      Telemetry.event_name_live_view_assign_async(),
      %{duration: System.monotonic_time() - started_at},
      %{view: view, result: result}
    )
  end

  defp result_tag({:ok, _assigns}), do: :ok
  defp result_tag(_other), do: :error
end
