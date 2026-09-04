defmodule Tuist.Sandboxes.Anthropic.PollerTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  import TuistTestSupport.Fixtures.SandboxesFixtures

  alias Tuist.Sandboxes.Anthropic.Client
  alias Tuist.Sandboxes.Anthropic.Poller
  alias Tuist.Sandboxes.Anthropic.Supervisor, as: AnthropicSupervisor
  alias Tuist.Sandboxes.Router

  setup :set_mimic_global

  setup do
    start_supervised!({Registry, keys: :unique, name: AnthropicSupervisor.registry()})
    start_supervised!({Task.Supervisor, name: AnthropicSupervisor.task_supervisor()})
    :ok
  end

  # The poller loops in its own process; the stub hands out the queued
  # responses once and answers "no work" afterwards.
  defp queue_poll_responses(responses) do
    {:ok, queue} = Agent.start_link(fn -> responses end)

    stub(Client, :poll, fn _environment_id, _key, _worker_id, 999 ->
      Agent.get_and_update(queue, fn
        [] -> {{:ok, :none}, []}
        [response | rest] -> {response, rest}
      end)
    end)
  end

  defp work_item(id, data) do
    %{"id" => id, "type" => "work", "data" => data, "secret" => "secret", "state" => "queued"}
  end

  test "acknowledges a session item and dispatches it to the router" do
    agent_environment = agent_environment_fixture(anthropic_environment_id: "env_poll", environment_key: "sk-poll")
    test_pid = self()
    item = work_item("work_1", %{"id" => "session_1", "type" => "session"})
    queue_poll_responses([{:ok, item}])

    expect(Client, :ack, fn "env_poll", "sk-poll", "work_1" ->
      send(test_pid, :acked)
      {:ok, Map.put(item, "state", "starting")}
    end)

    stub(Router, :dispatch, fn %{id: id}, dispatched ->
      send(test_pid, {:dispatched, id, dispatched})
      :ok
    end)

    reject(&Client.stop/4)

    start_supervised!({Poller, agent_environment_id: agent_environment.id, idle_delay_ms: 20, worker_id: "tuist-test"})

    assert_receive :acked, 2_000
    assert_receive {:dispatched, environment_id, ^item}, 2_000
    assert environment_id == agent_environment.id
    assert Poller.whereis(agent_environment.id)
  end

  test "force-stops a work item that is not a session" do
    agent_environment = agent_environment_fixture(anthropic_environment_id: "env_stop", environment_key: "sk-stop")
    test_pid = self()
    queue_poll_responses([{:ok, work_item("work_2", %{"id" => "job_1", "type" => "batch"})}])

    expect(Client, :stop, fn "env_stop", "sk-stop", "work_2", true ->
      send(test_pid, :stopped)
      {:ok, %{}}
    end)

    reject(&Client.ack/3)
    reject(&Router.dispatch/2)

    start_supervised!({Poller, agent_environment_id: agent_environment.id, idle_delay_ms: 20})

    assert_receive :stopped, 2_000
  end

  test "keeps polling through errors" do
    agent_environment = agent_environment_fixture(anthropic_environment_id: "env_err", environment_key: "sk-err")
    test_pid = self()
    item = work_item("work_3", %{"id" => "session_3", "type" => "session"})
    queue_poll_responses([{:error, :rate_limited}, {:ok, item}])

    expect(Client, :ack, fn "env_err", "sk-err", "work_3" ->
      send(test_pid, :acked)
      {:ok, item}
    end)

    stub(Router, :dispatch, fn _agent_environment, _item -> :ok end)

    pid = start_supervised!({Poller, agent_environment_id: agent_environment.id, idle_delay_ms: 20})

    assert_receive :acked, 5_000
    assert Process.alive?(pid)
  end

  test "does not start for a disabled environment and stops when its row disappears" do
    disabled = agent_environment_fixture(enabled: false)
    assert :ignore = Poller.start_link(agent_environment_id: disabled.id)

    agent_environment = agent_environment_fixture(anthropic_environment_id: "env_gone", environment_key: "sk-gone")
    queue_poll_responses([])

    pid = start_supervised!({Poller, agent_environment_id: agent_environment.id, idle_delay_ms: 20, refresh_interval: 50})

    ref = Process.monitor(pid)
    Tuist.Repo.delete!(agent_environment)

    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 2_000
  end
end
