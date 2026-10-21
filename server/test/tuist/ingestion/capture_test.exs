defmodule Tuist.Ingestion.CaptureTest do
  use ExUnit.Case, async: true

  alias Tuist.Ingestion.Capture
  alias Tuist.Tests.Test

  test "capture is process-local and preserves the schema submission and deferred effects" do
    row = %Test{id: Ecto.UUID.generate()}

    assert {:ok, rows, [:effect]} =
             Capture.run(fn ->
               assert Capture.active?()
               assert fn -> Capture.active?() end |> Task.async() |> Task.await() == false
               assert {:ok, ^row} = Test.Buffer.insert(row)
               Capture.defer_or_run(:effect, fn -> flunk("effect ran before publication") end)
               assert :ok = Test.Buffer.flush()
               :ok
             end)

    assert [%{id: id}] = rows[Test]
    assert id == row.id
    refute Capture.active?()
  end

  test "a raised builder always clears capture and deferred effects" do
    assert_raise RuntimeError, fn -> Capture.run(fn -> raise "builder failed" end) end
    refute Capture.active?()
    assert :ran = Capture.defer_or_run(:effect, fn -> :ran end)
  end
end
