defmodule Tuist.Sandboxes.Workers.ShrinkCarveOutsWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Sandboxes.Capacity
  alias Tuist.Sandboxes.Workers.ShrinkCarveOutsWorker

  test "shrinks the connected nodes' carve-outs" do
    expect(Capacity, :shrink_carve_outs, fn -> [{"node-a", {:ok, 8_589_934_592}}] end)

    assert :ok = ShrinkCarveOutsWorker.perform(%Oban.Job{args: %{}})
  end
end
