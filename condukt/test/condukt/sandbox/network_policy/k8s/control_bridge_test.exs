defmodule Condukt.Sandbox.NetworkPolicy.K8s.ControlBridgeTest do
  use ExUnit.Case, async: true

  alias Condukt.Sandbox.NetworkPolicy
  alias Condukt.Sandbox.NetworkPolicy.Decider
  alias Condukt.Sandbox.NetworkPolicy.Event
  alias Condukt.Sandbox.NetworkPolicy.K8s.ControlBridge

  # The GenServer callbacks are plain functions over a map state, so we
  # can drive the frame-handling logic directly without a live
  # pods/exec channel. send_fn is injected to capture what the bridge
  # would have written to the sidecar's stdin.
  defp state(policy, test_pid, overrides \\ %{}) do
    send_fn = fn
      {:stdin, payload} -> send(test_pid, {:stdin, payload})
      :close -> send(test_pid, :closed)
    end

    Map.merge(
      %{
        session_id: "s1",
        policy: policy,
        decide_spec: Decider.policy_spec(policy),
        owner_pid: nil,
        owner_ref: nil,
        connector: fn _owner -> {:error, :stub} end,
        max_reconnects: 10,
        pf: nil,
        pf_ref: make_ref(),
        send_fn: send_fn,
        buffer: "",
        cache: %{},
        attempts: 0
      },
      overrides
    )
  end

  defp event_frame(kind, host, extra \\ %{}) do
    Map.merge(
      %{
        "type" => "event",
        "kind" => kind,
        "request" => %{
          "id" => "r1",
          "host" => host,
          "port" => 443,
          "started_at" => "2026-05-17T10:00:00Z"
        }
      },
      extra
    )
  end

  # Telemetry handlers are VM-wide: this one fires for every network-policy
  # event in the suite, not only the ones this test provokes. The tests below
  # match on `{:telemetry, _, _}` wildcards, and a `refute_received` against a
  # wildcard fails on any foreign event that happens to land first. Tag each
  # message with the handler's own ref so a test only ever sees its own.
  defp attach(event, test_pid) do
    ref = make_ref()
    id = {__MODULE__, event, ref}

    :telemetry.attach(
      id,
      [:condukt, :sandbox, :network_policy, event],
      fn _name, measurements, metadata, %{ref: ref, test_pid: pid} ->
        send(pid, {:telemetry, ref, measurements, metadata})
      end,
      %{ref: ref, test_pid: test_pid}
    )

    on_exit(fn -> :telemetry.detach(id) end)

    ref
  end

  describe "__decode_event_line__/1" do
    test "decodes an event with matched_rule provenance" do
      line =
        JSON.encode!(
          event_frame("request_denied", "evil.com", %{
            "reason" => "matched_deny_list",
            "matched_rule" => %{"index" => 1, "kind" => "deny"}
          })
        )

      assert {:ok, %Event{kind: :request_denied, matched_rule: %{index: 1, kind: :deny}}} =
               ControlBridge.__decode_event_line__(line)
    end

    test "decodes a request_failed event" do
      line = JSON.encode!(event_frame("request_failed", "api.github.com", %{"reason" => "tls_client_rejected_ca"}))

      assert {:ok, %Event{kind: :request_failed, reason: "tls_client_rejected_ca"}} =
               ControlBridge.__decode_event_line__(line)
    end

    test "rejects a non-event frame" do
      assert {:error, {:unexpected_frame, _}} =
               ControlBridge.__decode_event_line__(JSON.encode!(%{"type" => "decision_request"}))
    end
  end

  describe "handle_info/2 event frames" do
    test "delivers an event as telemetry, including matched_rule" do
      ref = attach(:request_allowed, self())
      st = state(%NetworkPolicy{rules: [allow: ["api.github.com"]]}, self())

      line =
        JSON.encode!(
          event_frame("request_allowed", "api.github.com", %{
            "matched_rule" => %{"index" => 0, "kind" => "allow"}
          })
        )

      assert {:noreply, _st} = ControlBridge.handle_info({:control_bridge_data, line <> "\n"}, st)

      assert_receive {:telemetry, ^ref, _measurements, metadata}
      assert metadata.request.host == "api.github.com"
      assert metadata.matched_rule == %{index: 0, kind: :allow}
    end

    test "buffers a partial line until the newline arrives" do
      ref = attach(:request_closed, self())
      st = state(%NetworkPolicy{}, self())

      line = JSON.encode!(event_frame("request_closed", "api.github.com"))
      {head, tail} = String.split_at(line, 12)

      assert {:noreply, st} = ControlBridge.handle_info({:control_bridge_data, head}, st)
      assert st.buffer == head
      refute_received {:telemetry, ^ref, _, _}

      assert {:noreply, st} = ControlBridge.handle_info({:control_bridge_data, tail <> "\n"}, st)
      assert st.buffer == ""
      assert_receive {:telemetry, ^ref, _, _}
    end

    test "ignores an unknown frame type without crashing" do
      st = state(%NetworkPolicy{}, self())
      line = JSON.encode!(%{"type" => "mystery"})
      assert {:noreply, ^st} = ControlBridge.handle_info({:control_bridge_data, line <> "\n"}, st)
    end

    test "ignores a malformed JSON line without crashing" do
      st = state(%NetworkPolicy{}, self())
      assert {:noreply, ^st} = ControlBridge.handle_info({:control_bridge_data, "not json\n"}, st)
    end
  end

  describe "handle_info/2 decision_request frames" do
    defp decision_line(host) do
      JSON.encode!(%{
        "type" => "decision_request",
        "id" => "d1",
        "host" => host,
        "port" => 443,
        "scheme" => "https"
      }) <> "\n"
    end

    test "answers an allow decision on the sidecar stdin" do
      policy = %NetworkPolicy{rules: [decide: fn _ctx, _req -> :allow end]}
      st = state(policy, self())

      assert {:noreply, st} = ControlBridge.handle_info({:control_bridge_data, decision_line("api.example.com")}, st)

      assert_receive {:stdin, payload}
      assert String.ends_with?(payload, "\n")
      assert %{"type" => "decision", "id" => "d1", "action" => "allow"} = JSON.decode!(payload)
      assert st.cache == %{"api.example.com" => :allow}
    end

    test "answers a deny decision with a stringified reason" do
      policy = %NetworkPolicy{rules: [decide: fn _ctx, _req -> {:deny, :nope} end]}
      st = state(policy, self())

      assert {:noreply, _st} = ControlBridge.handle_info({:control_bridge_data, decision_line("evil.com")}, st)

      assert_receive {:stdin, payload}
      assert %{"action" => "deny", "reason" => "nope"} = JSON.decode!(payload)
    end

    test "caches the decision so the decider runs once per host" do
      counter = :counters.new(1, [])

      policy =
        %NetworkPolicy{
          rules: [
            decide: fn _ctx, _req ->
              :counters.add(counter, 1, 1)
              :allow
            end
          ]
        }

      st = state(policy, self())

      data = decision_line("api.example.com") <> decision_line("api.example.com")
      assert {:noreply, st} = ControlBridge.handle_info({:control_bridge_data, data}, st)

      assert :counters.get(counter, 1) == 1
      assert st.cache == %{"api.example.com" => :allow}
    end
  end

  describe "lifecycle / reconnect" do
    test "EOF schedules a reconnect instead of stopping" do
      st = state(%NetworkPolicy{}, self())
      assert {:noreply, st} = ControlBridge.handle_info({:control_bridge_eof}, st)
      assert st.pf == nil
      assert st.send_fn == nil
      assert_receive :reconnect, 1_000
    end

    test "the portforward going down schedules a reconnect" do
      st = state(%NetworkPolicy{}, self())
      msg = {:DOWN, st.pf_ref, :process, self(), :killed}
      assert {:noreply, _st} = ControlBridge.handle_info(msg, st)
      assert_receive :reconnect, 1_000
    end

    test "the owner going down stops :normal (collapses the subtree)" do
      owner_ref = make_ref()
      st = state(%NetworkPolicy{}, self(), %{owner_ref: owner_ref})
      msg = {:DOWN, owner_ref, :process, self(), :shutdown}

      assert {:stop, :normal, ^st} = ControlBridge.handle_info(msg, st)
      # It must NOT try to reconnect: the session is gone.
      refute_receive :reconnect, 200
    end

    test "a DOWN that is neither owner nor portforward is ignored" do
      st = state(%NetworkPolicy{}, self(), %{owner_ref: make_ref()})
      msg = {:DOWN, make_ref(), :process, self(), :normal}
      assert {:noreply, ^st} = ControlBridge.handle_info(msg, st)
    end

    test ":reconnect re-establishes the channel via the connector" do
      pf = spawn(fn -> Process.sleep(:infinity) end)
      st = state(%NetworkPolicy{}, self(), %{connector: fn _owner -> {:ok, pf} end, pf: nil, send_fn: nil})

      assert {:noreply, st} = ControlBridge.handle_info(:reconnect, st)
      assert st.pf == pf
      assert is_function(st.send_fn, 1)
      assert st.attempts == 0
    end

    test ":reconnect backs off and retries while under the attempt cap" do
      st = state(%NetworkPolicy{}, self(), %{connector: fn _ -> {:error, :down} end, attempts: 0})
      assert {:noreply, st} = ControlBridge.handle_info(:reconnect, st)
      assert st.attempts == 1
      assert_receive :reconnect, 2_000
    end

    test ":reconnect gives up :normal once the attempt cap is hit" do
      st =
        state(%NetworkPolicy{}, self(), %{
          connector: fn _ -> {:error, :down} end,
          attempts: 9,
          max_reconnects: 10
        })

      # :normal so the transient child is dropped, not restarted: a dead
      # control port must not crash-loop the shared supervisor.
      assert {:stop, :normal, _st} = ControlBridge.handle_info(:reconnect, st)
    end

    test "an unrelated message is ignored" do
      st = state(%NetworkPolicy{}, self())
      assert {:noreply, ^st} = ControlBridge.handle_info(:something_else, st)
    end

    test "terminate closes the channel" do
      st = state(%NetworkPolicy{}, self())
      assert :ok = ControlBridge.terminate(:normal, st)
      assert_received :closed
    end
  end

  describe "supervised under a DynamicSupervisor" do
    setup do
      %{sup: start_supervised!({DynamicSupervisor, strategy: :one_for_one})}
    end

    # A real gen_server (Agent) stand-in for PortForward: the bridge
    # stops it via PortForward.close -> GenServer.stop on teardown.
    defp fake_pf do
      {:ok, pid} = Agent.start(fn -> :ok end)
      pid
    end

    defp bopts(owner, connector) do
      [
        conn: :stub,
        namespace: "ns",
        pod_name: "pod",
        session_id: "s1",
        policy: %NetworkPolicy{},
        owner_pid: owner,
        connector: connector
      ]
    end

    defp only_child(sup) do
      case DynamicSupervisor.which_children(sup) do
        [{_, pid, _, _}] when is_pid(pid) -> pid
        _ -> nil
      end
    end

    defp wait_for(fun, tries \\ 50) do
      cond do
        tries == 0 ->
          nil

        v = fun.() ->
          v

        true ->
          Process.sleep(20)
          wait_for(fun, tries - 1)
      end
    end

    test "child_spec is a transient worker" do
      spec = ControlBridge.child_spec([])
      assert spec.restart == :transient
      assert spec.type == :worker
    end

    test "init does not crash when the control port is unreachable", %{sup: sup} do
      {:ok, pid} =
        DynamicSupervisor.start_child(
          sup,
          {ControlBridge, bopts(self(), fn _ -> {:error, :unreachable} end)}
        )

      # init returned {:ok} and scheduled a retry rather than crashing,
      # so a control port that is not up yet does not fail the session.
      assert Process.alive?(pid)
    end

    test "a crash is restarted (transient child)", %{sup: sup} do
      {:ok, p1} =
        DynamicSupervisor.start_child(
          sup,
          {ControlBridge, bopts(self(), fn _ -> {:ok, fake_pf()} end)}
        )

      Process.exit(p1, :kill)

      p2 =
        wait_for(fn ->
          case only_child(sup) do
            pid when is_pid(pid) and pid != p1 -> pid
            _ -> nil
          end
        end)

      assert is_pid(p2)
      assert p2 != p1
    end

    test "the owner going away drops the bridge and is not restarted", %{sup: sup} do
      owner = spawn(fn -> Process.sleep(:infinity) end)

      {:ok, pid} =
        DynamicSupervisor.start_child(
          sup,
          {ControlBridge, bopts(owner, fn _ -> {:ok, fake_pf()} end)}
        )

      ref = Process.monitor(pid)
      Process.exit(owner, :kill)

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1_000
      assert [] = wait_for(fn -> if only_child(sup) == nil, do: [] end)
    end

    test "the application supervises a control-channel DynamicSupervisor" do
      name = Condukt.Application.control_channel_supervisor()
      assert is_pid(Process.whereis(name))
    end
  end
end
