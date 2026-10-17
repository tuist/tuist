defmodule Tuist.Sandboxes.Anthropic.ManagerTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  import ExUnit.CaptureLog
  import TuistTestSupport.Fixtures.SandboxesFixtures

  alias Tuist.Sandboxes.Anthropic.Client
  alias Tuist.Sandboxes.Anthropic.Manager
  alias Tuist.Sandboxes.Anthropic.Poller
  alias Tuist.Sandboxes.Anthropic.Supervisor, as: AnthropicSupervisor

  setup :set_mimic_global

  setup do
    start_supervised!({Task.Supervisor, name: AnthropicSupervisor.task_supervisor()})
    start_supervised!({DynamicSupervisor, name: AnthropicSupervisor.poller_supervisor(), strategy: :one_for_one})
    stub(Client, :poll, fn _environment_id, _key, _worker_id, 999 -> {:ok, :none} end)
    :ok
  end

  # Stands in for a poller another replica holds under the global name.
  defp poller_elsewhere(agent_environment_id) do
    {:ok, pid} = Agent.start_link(fn -> agent_environment_id end, name: Poller.name(agent_environment_id))
    pid
  end

  test "starts a poller per enabled environment and stops the ones whose environment is gone or disabled" do
    enabled = agent_environment_fixture()
    disabled = agent_environment_fixture(enabled: false)
    stale = poller_elsewhere(disabled.id)
    orphan = poller_elsewhere(0)
    manager = start_supervised!({Manager, interval: to_timeout(hour: 1)})

    assert :ok = Manager.reconcile(manager)

    assert pid = Poller.whereis(enabled.id)
    assert Process.alive?(pid)
    assert %{active: 1} = DynamicSupervisor.count_children(AnthropicSupervisor.poller_supervisor())
    refute Process.alive?(stale)
    refute Process.alive?(orphan)
  end

  test "treats a poller already registered elsewhere as running" do
    agent_environment = agent_environment_fixture()
    elsewhere = poller_elsewhere(agent_environment.id)
    manager = start_supervised!({Manager, interval: to_timeout(hour: 1)})

    log = capture_log(fn -> assert :ok = Manager.reconcile(manager) end)

    refute log =~ "failed to start work poller"
    assert Poller.whereis(agent_environment.id) == elsewhere
    assert Process.alive?(elsewhere)
    assert %{active: 0} = DynamicSupervisor.count_children(AnthropicSupervisor.poller_supervisor())
  end
end
