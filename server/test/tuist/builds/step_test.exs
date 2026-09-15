defmodule Tuist.Builds.StepTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Builds.Step
  alias Tuist.IngestRepo

  test "log-heavy input is streamed in byte-bounded writes from the caller" do
    owner = self()

    stub(IngestRepo, :query!, fn _sql, [_header | rows], _opts ->
      assert self() == owner
      assert IO.iodata_length(rows) <= 8 * 1024 * 1024
      send(owner, {:batch, length(rows)})
      %{}
    end)

    entry = %Step{
      build_run_id: Ecto.UUID.generate(),
      event_id: 1,
      title: "Compile",
      target: "App",
      project: "Workspace",
      category: "swiftCompilation",
      start_ms: 0.0,
      duration_ms: 1.0,
      status: "success",
      log: String.duplicate("x", 64 * 1024),
      inserted_at: DateTime.truncate(DateTime.utc_now(), :second)
    }

    Step.insert_all(Stream.map(1..300, &Map.put(entry, :event_id, &1)))

    counts =
      fn ->
        receive do
          {:batch, count} -> count
        after
          0 -> nil
        end
      end
      |> Stream.repeatedly()
      |> Enum.take_while(&is_integer/1)

    assert Enum.sum(counts) == 300
    assert length(counts) == 3
  end

  test "failed writes fail the caller so the job can retry" do
    stub(IngestRepo, :query!, fn _, _, _ -> raise "write failed" end)

    entry = %Step{
      build_run_id: Ecto.UUID.generate(),
      event_id: 1,
      title: "Compile",
      target: "",
      project: "",
      category: "",
      start_ms: 0.0,
      duration_ms: 1.0,
      status: "success",
      inserted_at: DateTime.truncate(DateTime.utc_now(), :second)
    }

    assert_raise RuntimeError, "write failed", fn -> Step.insert_all([entry]) end
  end
end
