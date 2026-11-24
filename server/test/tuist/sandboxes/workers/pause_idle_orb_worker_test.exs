defmodule Tuist.Sandboxes.Workers.PauseIdleOrbWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import TuistTestSupport.Fixtures.SandboxesFixtures

  alias Tuist.Repo
  alias Tuist.Sandboxes.Nodes
  alias Tuist.Sandboxes.Workers.PauseIdleOrbWorker

  setup do
    quiet_since = DateTime.truncate(DateTime.add(DateTime.utc_now(), -700, :second), :second)

    sandbox =
      sandbox_fixture(
        amp_orb_id: "amp-thread",
        node_name: "node-a",
        residency_work_id: "amp:amp-thread",
        guest_cpu_ms: 1000,
        last_active_at: quiet_since
      )

    %{sandbox: sandbox, args: %{sandbox_id: sandbox.id, last_active_at: DateTime.to_iso8601(quiet_since)}}
  end

  # Every Orb pause reads the guest's setup log first, then pauses.
  defp stub_pause(result) do
    stub(Nodes, :call, fn
      "node-a", "exec", _args, _opts -> {:ok, %{"exit_code" => 0}}
      "node-a", "pause", _args, _opts -> result
    end)
  end

  test "succeeds when the node disconnects mid-pause, leaving the Orb for its next report", %{
    sandbox: sandbox,
    args: args
  } do
    stub_pause({:error, :node_disconnected})

    assert :ok = perform_job(PauseIdleOrbWorker, args)
    assert Repo.reload!(sandbox).state == :running
  end

  test "fails on a refusal from the node", %{args: args} do
    stub_pause({:error, "exec running"})

    assert {:error, "exec running"} = perform_job(PauseIdleOrbWorker, args)
  end
end
