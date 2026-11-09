defmodule Tuist.Sandboxes.Workers.DispatchWorkItemWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import TuistTestSupport.Fixtures.SandboxesFixtures

  alias Tuist.Sandboxes.Anthropic.Client
  alias Tuist.Sandboxes.Capacity
  alias Tuist.Sandboxes.Router
  alias Tuist.Sandboxes.Workers.DispatchWorkItemWorker

  defp item do
    %{
      "id" => "work_held",
      "type" => "work",
      "data" => %{"id" => "session_held", "type" => "session"},
      "secret" => "s3cret"
    }
  end

  defp args(agent_environment, deadline_offset_ms) do
    agent_environment
    |> DispatchWorkItemWorker.new_for(item())
    |> Ecto.Changeset.get_change(:args)
    |> Map.put(:deadline_ms, System.system_time(:millisecond) + deadline_offset_ms)
  end

  test "dispatches the item with its decrypted secret once a node has room" do
    agent_environment = agent_environment_fixture(anthropic_environment_id: "env_held", environment_key: "sk-held")
    environment_id = agent_environment.id
    expected = item()

    expect(Capacity, :admission, fn %{id: ^environment_id}, "session_held" -> :ok end)
    expect(Router, :dispatch, fn %{id: ^environment_id}, ^expected -> :ok end)
    reject(&Client.stop/4)

    assert :ok = perform_job(DispatchWorkItemWorker, args(agent_environment, 60_000))
  end

  test "waits while no node has room and the deadline has not passed" do
    agent_environment = agent_environment_fixture(anthropic_environment_id: "env_held", environment_key: "sk-held")

    stub(Capacity, :admission, fn _environment, "session_held" -> {:error, :no_room} end)
    reject(&Router.dispatch/2)
    reject(&Client.stop/4)

    assert {:snooze, 5} = perform_job(DispatchWorkItemWorker, args(agent_environment, 60_000))
  end

  test "force-stops the item when no node had room before the deadline" do
    agent_environment = agent_environment_fixture(anthropic_environment_id: "env_held", environment_key: "sk-held")

    stub(Capacity, :admission, fn _environment, "session_held" -> {:error, :no_room} end)
    reject(&Router.dispatch/2)
    expect(Client, :stop, fn "env_held", "sk-held", "work_held", true -> {:ok, %{}} end)

    assert :ok = perform_job(DispatchWorkItemWorker, args(agent_environment, -1))
  end
end
