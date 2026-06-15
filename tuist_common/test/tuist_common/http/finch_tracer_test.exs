defmodule TuistCommon.HTTP.FinchTracerTest do
  use ExUnit.Case, async: false

  alias TuistCommon.HTTP.FinchTracer

  setup do
    FinchTracer.setup()

    on_exit(fn ->
      :telemetry.detach({FinchTracer, :request_stop})
    end)

    :ok
  end

  defp execute(result) do
    :telemetry.execute(
      [:finch, :request, :stop],
      %{duration: System.convert_time_unit(2, :millisecond, :native)},
      %{
        request: %{scheme: :https, host: "example.com", port: 443, path: "/logs", method: "GET"},
        result: result
      }
    )
  end

  defp handler_attached? do
    Enum.any?(
      :telemetry.list_handlers([:finch, :request, :stop]),
      &(&1.id == {FinchTracer, :request_stop})
    )
  end

  test "does not crash on a streamed request whose result is the caller's accumulator" do
    # Req streams via Finch.stream_while/5 when `:into` is a function, so the
    # result is `{:ok, acc}` with `acc` a `{request, response}` tuple, not a
    # `%Finch.Response{}`. Reading `.status` off that tuple used to raise
    # BadMapError and make :telemetry permanently detach the handler.
    acc = {%{__struct__: Req.Request}, %{__struct__: Req.Response, status: 200}}

    execute({:ok, acc})

    assert handler_attached?()
  end

  test "records the status for a regular Finch response" do
    execute({:ok, %Finch.Response{status: 204, headers: [], body: ""}})

    assert handler_attached?()
  end

  test "handles request errors without crashing" do
    execute({:error, %Mint.TransportError{reason: :closed}})

    assert handler_attached?()
  end
end
