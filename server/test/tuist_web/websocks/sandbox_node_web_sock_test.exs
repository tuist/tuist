defmodule TuistWeb.SandboxNodeWebSockTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.Capacity
  alias Tuist.Sandboxes.Nodes
  alias TuistWeb.SandboxNodeWebSock

  # The test process plays the socket process: it runs the callbacks, so
  # it is the process tracked in presence and subscribed to the node's
  # topic, and a `Nodes.call/4` from any other process lands its command
  # message here.
  setup do
    stub(Sandboxes, :reconcile_node_report, fn _node, _report -> :ok end)
    node_name = "node-#{System.unique_integer([:positive])}"
    {:ok, state} = SandboxNodeWebSock.init(%{node_name: node_name})
    %{node_name: node_name, state: state}
  end

  defp text(frame), do: {JSON.encode!(frame), [opcode: :text]}

  defp hello(node_name, overrides \\ %{}) do
    Map.merge(
      %{
        "type" => "hello",
        "node" => node_name,
        "daemon_version" => "1.0.0",
        "firecracker_version" => "1.10.0",
        "capacity" => %{"memory_bytes" => 64_000_000_000, "cpus" => 32},
        "disk" => %{
          "total_bytes" => 2_000_000_000_000,
          "available_bytes" => 1_500_000_000_000,
          "sandboxes_bytes" => 3_000_000_000,
          "templates_bytes" => 6_000_000_000,
          "budget_bytes" => 200_000_000_000
        },
        "templates" => [%{"name" => "default", "tag" => "sha-1", "ready" => true}],
        "sandboxes" => []
      },
      overrides
    )
  end

  # Presence converges asynchronously, so lookups right after a track or
  # an untrack are polled briefly instead of asserted once.
  defp eventually(fun, attempts \\ 50) do
    cond do
      fun.() -> true
      attempts == 0 -> false
      true -> Process.sleep(10) && eventually(fun, attempts - 1)
    end
  end

  test "hello tracks the node with its templates and reconciles its sandboxes", %{
    node_name: node_name,
    state: state
  } do
    test_pid = self()
    report = hello(node_name, %{"sandboxes" => [%{"id" => Ecto.UUID.generate(), "state" => "running"}]})

    expect(Sandboxes, :reconcile_node_report, fn ^node_name, ^report ->
      send(test_pid, :reconciled)
      :ok
    end)

    assert {:ok, state} = SandboxNodeWebSock.handle_in(text(report), state)
    assert state.tracked?
    assert_received :reconciled
    assert eventually(fn -> Nodes.connected?(node_name) end)

    assert [
             %{
               name: ^node_name,
               templates: [%{name: "default", tag: "sha-1", ready: true}],
               capacity: %{cpus: 32},
               disk: %{available_bytes: 1_500_000_000_000, sandboxes_bytes: 3_000_000_000, budget_bytes: 200_000_000_000},
               pid: pid,
               node: erlang_node,
               connected_at: %DateTime{}
             }
           ] = Enum.filter(Nodes.connected_nodes(), &(&1.name == node_name))

    assert pid == self()
    assert erlang_node == node()

    ready = fn template ->
      Enum.filter(Capacity.ready_nodes(template), &(&1.name == node_name))
    end

    assert [%{name: ^node_name}] = ready.("default")
    assert [] = ready.("missing")

    assert :ok = SandboxNodeWebSock.terminate(:normal, state)
    assert eventually(fn -> not Nodes.connected?(node_name) end)
  end

  test "a call from a process that did not track the socket reaches it and stream frames reach the caller", %{
    node_name: node_name,
    state: state
  } do
    {:ok, state} = SandboxNodeWebSock.handle_in(text(hello(node_name)), state)
    test_pid = self()

    task =
      Task.async(fn ->
        on_stream = fn chunk -> send(test_pid, {:chunk, chunk}) end
        Nodes.call(node_name, "exec", %{sandbox_id: "s1", cmd: ["ls"]}, on_stream: on_stream)
      end)

    assert_receive {:sandbox_command, ref, "exec", %{sandbox_id: "s1"}, from}
    assert from == task.pid

    assert {:push, {:text, frame}, state} =
             SandboxNodeWebSock.handle_info(
               {:sandbox_command, ref, "exec", %{sandbox_id: "s1", cmd: ["ls"]}, from},
               state
             )

    assert %{"type" => "command", "id" => "c1", "op" => "exec", "args" => %{"sandbox_id" => "s1", "cmd" => ["ls"]}} =
             JSON.decode!(frame)

    stream = %{"type" => "stream", "id" => "c1", "stream" => "stdout", "data_b64" => Base.encode64("hello\n")}
    assert {:ok, state} = SandboxNodeWebSock.handle_in(text(stream), state)

    result = %{"type" => "result", "id" => "c1", "ok" => true, "data" => %{"exit_code" => 0}}
    assert {:ok, state} = SandboxNodeWebSock.handle_in(text(result), state)

    assert {:ok, %{"exit_code" => 0}} = Task.await(task)
    assert_received {:chunk, {:stdout, "hello\n"}}
    assert state.pending == %{}

    failed = Task.async(fn -> Nodes.call(node_name, "pause", %{sandbox_id: "s1"}, []) end)
    assert_receive {:sandbox_command, ref, "pause", args, from}
    assert {:push, _frame, state} = SandboxNodeWebSock.handle_info({:sandbox_command, ref, "pause", args, from}, state)

    error = %{"type" => "result", "id" => "c2", "ok" => false, "error" => "worker running"}
    assert {:ok, _state} = SandboxNodeWebSock.handle_in(text(error), state)
    assert {:error, "worker running"} = Task.await(failed)
  end

  test "terminate fails the pending commands and releases the node", %{node_name: node_name, state: state} do
    {:ok, state} = SandboxNodeWebSock.handle_in(text(hello(node_name)), state)

    task = Task.async(fn -> Nodes.call(node_name, "create", %{sandbox_id: "s1"}, []) end)
    assert_receive {:sandbox_command, ref, "create", args, from}
    assert {:push, _frame, state} = SandboxNodeWebSock.handle_info({:sandbox_command, ref, "create", args, from}, state)

    assert :ok = SandboxNodeWebSock.terminate(:remote, state)
    assert {:error, :node_disconnected} = Task.await(task)
    assert eventually(fn -> not Nodes.connected?(node_name) end)
    assert {:error, :not_connected} = Nodes.call(node_name, "create", %{}, [])
  end

  test "a socket that dies mid-call fails the call with node_disconnected", %{node_name: node_name} do
    test_pid = self()

    {:ok, socket} =
      Task.start(fn ->
        {:ok, state} = SandboxNodeWebSock.init(%{node_name: node_name})
        {:ok, _state} = SandboxNodeWebSock.handle_in(text(hello(node_name)), state)
        send(test_pid, :tracked)

        receive do
          {:sandbox_command, _ref, "exec", _args, _from} -> :ok
        end
      end)

    assert_receive :tracked
    assert eventually(fn -> match?({:ok, ^socket, _info}, Nodes.lookup(node_name)) end)

    assert {:error, :node_disconnected} = Nodes.call(node_name, "exec", %{sandbox_id: "s1", cmd: ["ls"]}, [])
  end

  test "a reconnect supersedes the previous socket", %{node_name: node_name, state: state} do
    {:ok, state} = SandboxNodeWebSock.handle_in(text(hello(node_name)), state)

    replacement =
      Task.async(fn ->
        {:ok, state} = SandboxNodeWebSock.init(%{node_name: node_name})
        {:ok, state} = SandboxNodeWebSock.handle_in(text(hello(node_name)), state)
        {:ok, pid, _info} = Nodes.lookup(node_name)
        {pid, state}
      end)

    assert_receive :sandbox_node_superseded

    assert {:stop, :normal, {1000, "superseded"}, state} =
             SandboxNodeWebSock.handle_info(:sandbox_node_superseded, state)

    assert :ok = SandboxNodeWebSock.terminate(:normal, state)

    assert {pid, _state} = Task.await(replacement)
    assert pid == replacement.pid
  end

  test "events and reports are handed to the context", %{node_name: node_name, state: state} do
    {:ok, state} = SandboxNodeWebSock.handle_in(text(hello(node_name)), state)
    test_pid = self()

    event = %{"type" => "event", "event" => "worker_exited", "sandbox_id" => "s1", "exit_code" => 0}

    expect(Sandboxes, :handle_node_event, fn ^node_name, ^event ->
      send(test_pid, :event_handled)
      :ok
    end)

    assert {:ok, state} = SandboxNodeWebSock.handle_in(text(event), state)
    assert_received :event_handled

    template_ready = %{"type" => "event", "event" => "template_ready", "name" => "xcode", "tag" => "sha-9"}
    expect(Sandboxes, :handle_node_event, fn ^node_name, ^template_ready -> :ok end)
    assert {:ok, state} = SandboxNodeWebSock.handle_in(text(template_ready), state)
    assert [%{name: ^node_name}] = Enum.filter(Capacity.ready_nodes("xcode"), &(&1.name == node_name))

    report = %{
      "type" => "report",
      "sandboxes" => [%{"id" => "s1", "state" => "running"}],
      "memory" => %{"used_bytes" => 5}
    }

    expect(Sandboxes, :reconcile_node_report, fn ^node_name, ^report ->
      send(test_pid, :report_handled)
      :ok
    end)

    assert {:ok, state} = SandboxNodeWebSock.handle_in(text(report), state)
    assert_received :report_handled

    assert [%{sandboxes: [%{id: "s1", state: "running"}], memory: %{used_bytes: 5}}] =
             Enum.filter(Nodes.connected_nodes(), &(&1.name == node_name))

    assert :ok = SandboxNodeWebSock.terminate(:normal, state)
  end
end
