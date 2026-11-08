defmodule Pulse.Loki.TailDeliveryTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Loki.TailDelivery

  test "concurrent senders reserve before enqueue and never exceed 64 batches" do
    tasks = start_supervised!(Task.Supervisor)
    credit = TailDelivery.new()
    owner = self()

    results =
      Task.Supervisor.async_stream_nolink(
        tasks,
        1..256,
        fn n ->
          TailDelivery.deliver(owner, credit, :batch, [n], :close)
        end,
        max_concurrency: 8
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &(&1 == :ok)) == 64
    assert :atomics.get(credit, 1) == 64
    assert_receive :tail_overloaded
    refute_received :tail_overloaded

    for _ <- 1..64 do
      assert_receive {:batch, ^credit, bytes, [_]}
      assert :ok = TailDelivery.release(credit, bytes)
    end

    assert :atomics.get(credit, 1) == 0
    assert :atomics.get(credit, 2) == 0
  end

  test "one bounded ingest-sized batch can exceed ordinary queue credit without closing an idle tail" do
    credit = TailDelivery.new()
    records = [String.duplicate("x", 18 * 1024 * 1024)]
    assert :ok = TailDelivery.deliver(self(), credit, :batch, records, :close)
    assert_receive {:batch, ^credit, bytes, ^records}
    refute_received :tail_overloaded
    assert :dropped = TailDelivery.deliver(self(), credit, :batch, ["next"], :close)
    assert_receive :tail_overloaded
    TailDelivery.release(credit, bytes)
    assert :atomics.get(credit, 2) == 0
  end

  test "serialized input bytes and current processing are separate bounded lifetimes" do
    credit = TailDelivery.new()
    records = [String.duplicate("x", 9 * 1024 * 1024)]
    assert :ok = TailDelivery.deliver(self(), credit, :batch, records)
    assert :dropped = TailDelivery.deliver(self(), credit, :batch, records)
    assert :atomics.get(credit, 1) == 1
    assert :atomics.get(credit, 2) <= 16 * 1024 * 1024
    assert_receive {:batch, ^credit, bytes, ^records}
    assert :ok = TailDelivery.release(credit, bytes)
    assert :ok = TailDelivery.deliver(self(), credit, :batch, records)
  end
end
