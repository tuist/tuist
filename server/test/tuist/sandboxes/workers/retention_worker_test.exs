defmodule Tuist.Sandboxes.Workers.RetentionWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import Ecto.Query
  import TuistTestSupport.Fixtures.SandboxesFixtures

  alias Tuist.Repo
  alias Tuist.Sandboxes.Nodes
  alias Tuist.Sandboxes.Sandbox
  alias Tuist.Sandboxes.Workers.RetentionWorker

  defp days_ago(days), do: DateTime.add(DateTime.utc_now(), -days, :day)

  test "deletes sandboxes paused for longer than the retention window and keeps the rest" do
    expired =
      sandbox_fixture(
        state: :paused,
        node_name: "node-a",
        paused_at: days_ago(RetentionWorker.paused_retention_days() + 1)
      )

    fresh = sandbox_fixture(state: :paused, node_name: "node-a", paused_at: days_ago(1))
    running = sandbox_fixture(state: :running, node_name: "node-a", last_active_at: days_ago(40))
    expired_id = expired.id

    expect(Nodes, :call, fn "node-a", "delete", %{sandbox_id: ^expired_id}, _opts -> {:ok, %{}} end)

    assert :ok = perform_job(RetentionWorker, %{})
    assert Repo.get(Sandbox, expired.id) == nil
    assert %Sandbox{state: :paused} = Repo.reload!(fresh)
    assert %Sandbox{state: :running} = Repo.reload!(running)
  end

  test "falls back to the row's last update when the node paused the sandbox without the server" do
    sandbox = sandbox_fixture(state: :paused, node_name: "node-b", paused_at: nil)
    Repo.update_all(from(s in Sandbox, where: s.id == ^sandbox.id), set: [updated_at: days_ago(30)])
    sandbox_id = sandbox.id

    expect(Nodes, :call, fn "node-b", "delete", %{sandbox_id: ^sandbox_id}, _opts -> {:ok, %{}} end)

    assert :ok = perform_job(RetentionWorker, %{})
    assert Repo.get(Sandbox, sandbox.id) == nil
  end

  test "removes the row even when the node is away, leaving the jail to the orphan sweep" do
    sandbox = sandbox_fixture(state: :paused, node_name: "node-gone", paused_at: days_ago(30))
    expect(Nodes, :call, fn "node-gone", "delete", _args, _opts -> {:error, :not_connected} end)

    assert :ok = perform_job(RetentionWorker, %{})
    assert Repo.get(Sandbox, sandbox.id) == nil
  end
end
