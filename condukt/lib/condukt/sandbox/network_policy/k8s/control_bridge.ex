defmodule Condukt.Sandbox.NetworkPolicy.K8s.ControlBridge do
  @moduledoc false

  # GenServer that owns the bidirectional NDJSON control channel between
  # the BEAM and the sidecar `condukt-egress` proxy running in a session
  # pod.
  #
  # Transport is a `pods/portforward` WebSocket to the proxy's control
  # port (`Condukt.Sandbox.NetworkPolicy.K8s.PortForward`): a real
  # socket, not a command's stdout. The bridge is transport agnostic:
  # PortForward feeds it `{:control_bridge_data, binary}` for inbound
  # NDJSON and `{:control_bridge_eof}` when the channel drops; the
  # bridge writes decisions back through an injected `send_fn`.
  #
  # The channel is supervised: if it drops, the bridge re-dials with
  # capped exponential backoff instead of taking the session down with
  # it. A request in flight when the channel dies still gets denied
  # (the sidecar's decide_timeout fires), but subsequent requests
  # recover once the channel is back. Decisions are computed
  # synchronously inside the bridge process, so a reconnect can never
  # interleave with an in-progress decision: no decision can be sent
  # over a stale channel.
  #
  # Per-host decision caching, decider invocation, telemetry emission,
  # and context assembly all live here. The owning K8s sandbox starts one
  # bridge per session at init and tears it down on shutdown.

  use GenServer

  alias Condukt.Sandbox.NetworkPolicy
  alias Condukt.Sandbox.NetworkPolicy.Context
  alias Condukt.Sandbox.NetworkPolicy.Decider
  alias Condukt.Sandbox.NetworkPolicy.Event
  alias Condukt.Sandbox.NetworkPolicy.K8s.PortForward
  alias Condukt.Sandbox.NetworkPolicy.Request

  require Logger

  @control_port 15_002
  @max_reconnects 10
  @backoff_base_ms 500
  @backoff_max_ms 15_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  # Supervised directly by the control-channel DynamicSupervisor.
  # `:transient` so a crash is restarted but a clean stop (owner gone,
  # or graceful give-up) is left dropped, never restarted.
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient,
      shutdown: 5_000,
      type: :worker
    }
  end

  def stop(pid) do
    if Process.alive?(pid), do: GenServer.stop(pid, :normal, 5_000), else: :ok
  end

  @impl true
  def init(opts) do
    conn = Keyword.fetch!(opts, :conn)
    namespace = Keyword.fetch!(opts, :namespace)
    pod_name = Keyword.fetch!(opts, :pod_name)
    session_id = Keyword.fetch!(opts, :session_id)
    policy = Keyword.fetch!(opts, :policy)
    owner_pid = Keyword.get(opts, :owner_pid)
    port = Keyword.get(opts, :control_port, @control_port)

    Process.flag(:trap_exit, true)

    # Bind the bridge's lifetime to the gated session: when the owner
    # goes away there is nothing left to gate, so stop `:normal`. As a
    # `:transient` child of the control-channel DynamicSupervisor, a
    # `:normal` stop is not restarted and the child is dropped, so no
    # bridge or portforward socket is orphaned on an abnormal session
    # exit, independent of any explicit sandbox teardown. The bridge is
    # not linked to the session, so neither can take the other down.
    owner_ref = if is_pid(owner_pid), do: Process.monitor(owner_pid)

    # Injectable so the reconnect logic is unit-testable without a
    # cluster. Production default dials a real pods/portforward.
    connector =
      Keyword.get(opts, :connector) ||
        fn owner ->
          PortForward.start_link(
            conn: conn,
            namespace: namespace,
            pod_name: pod_name,
            port: port,
            owner: owner
          )
        end

    state = %{
      session_id: session_id,
      policy: policy,
      decide_spec: Decider.policy_spec(policy),
      owner_pid: owner_pid,
      owner_ref: owner_ref,
      connector: connector,
      max_reconnects: Keyword.get(opts, :max_reconnects, @max_reconnects),
      pf: nil,
      pf_ref: nil,
      send_fn: nil,
      buffer: "",
      cache: %{},
      attempts: 0
    }

    # A control port that is not up yet (or a transient apiserver blip)
    # at session start must not fail sandbox init or crash the bridge:
    # enter the same backoff/reconnect loop a mid-session drop uses. A
    # genuinely unreachable port eventually gives up `:normal` (see
    # :reconnect), which is not restarted and fails closed.
    case open_channel(state) do
      {:ok, state} ->
        {:ok, state}

      {:error, reason} ->
        Logger.warning(fn ->
          "[sandbox.network_policy.k8s] control bridge initial connect failed: #{inspect(reason)}; retrying"
        end)

        Process.send_after(self(), :reconnect, backoff(0))
        {:ok, state}
    end
  end

  @impl true
  def handle_info({:control_bridge_data, data}, state) do
    {state, lines} = drain_lines(state, data)
    state = Enum.reduce(lines, state, &handle_line/2)
    {:noreply, state}
  end

  def handle_info({:control_bridge_eof}, state) do
    schedule_reconnect(state)
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{owner_ref: ref} = state) when is_reference(ref) do
    # The gated session is gone. Stop `:normal` so the transient +
    # significant child is not restarted and the per-session
    # ControlChannel subtree auto-shuts-down with it.
    {:stop, :normal, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{pf_ref: ref} = state) do
    schedule_reconnect(state)
  end

  def handle_info(:reconnect, state) do
    case open_channel(state) do
      {:ok, state} ->
        Logger.info(fn -> "[sandbox.network_policy.k8s] control bridge reconnected" end)
        {:noreply, state}

      {:error, reason} ->
        attempts = state.attempts + 1

        if attempts >= state.max_reconnects do
          give_up(state, attempts, reason)
        else
          Process.send_after(self(), :reconnect, backoff(attempts))
          {:noreply, %{state | attempts: attempts}}
        end
    end
  end

  def handle_info(_other, state), do: {:noreply, state}

  # Give up gracefully: stop `:normal` so the transient child is
  # dropped (not restarted) and a permanently dead control port cannot
  # crash-loop the shared supervisor. `:decide` then fails closed via
  # the sidecar's decide timeout.
  defp give_up(state, attempts, reason) do
    Logger.warning(fn ->
      "[sandbox.network_policy.k8s] control bridge giving up after #{attempts} attempts: #{inspect(reason)}"
    end)

    {:stop, :normal, state}
  end

  @impl true
  def terminate(_reason, state) do
    if state.send_fn, do: state.send_fn.(:close)
    :ok
  end

  defp open_channel(state) do
    case state.connector.(self()) do
      {:ok, pf} ->
        ref = Process.monitor(pf)

        {:ok, %{state | pf: pf, pf_ref: ref, send_fn: build_send_fn(pf), buffer: "", attempts: 0}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_send_fn(pf) do
    fn
      {:stdin, payload} -> PortForward.send_payload(pf, payload)
      :close -> PortForward.close(pf)
    end
  end

  defp schedule_reconnect(state) do
    if state.pf_ref, do: Process.demonitor(state.pf_ref, [:flush])
    Process.send_after(self(), :reconnect, backoff(state.attempts))
    {:noreply, %{state | pf: nil, pf_ref: nil, send_fn: nil, buffer: ""}}
  end

  defp backoff(attempts) do
    min(@backoff_max_ms, @backoff_base_ms * Integer.pow(2, min(attempts, 5)))
  end

  defp drain_lines(state, data) do
    combined = state.buffer <> data

    case String.split(combined, "\n") do
      [single] -> {%{state | buffer: single}, []}
      parts -> {%{state | buffer: List.last(parts)}, Enum.drop(parts, -1)}
    end
  end

  defp handle_line("", state), do: state

  defp handle_line(line, state) do
    case JSON.decode(line) do
      {:ok, %{"type" => "event"} = frame} ->
        deliver_event(state.policy, frame)
        state

      {:ok, %{"type" => "decision_request"} = frame} ->
        respond_to_decision_request(state, frame)

      {:ok, other} ->
        Logger.warning(fn -> "[sandbox.network_policy.k8s] unknown frame type: #{inspect(other)}" end)
        state

      {:error, reason} ->
        Logger.warning(fn -> "[sandbox.network_policy.k8s] bad frame: #{inspect(reason)} line=#{inspect(line)}" end)
        state
    end
  end

  defp deliver_event(policy, frame) do
    with {:ok, request} <- Request.from_json(frame["request"] || %{}),
         {:ok, kind} <- decode_kind(frame["kind"]) do
      NetworkPolicy.deliver(policy, kind, request,
        reason: frame["reason"],
        matched_rule: Event.decode_matched_rule(frame["matched_rule"])
      )
    end
  end

  defp decode_kind("request_opened"), do: {:ok, :request_opened}
  defp decode_kind("request_closed"), do: {:ok, :request_closed}
  defp decode_kind("request_allowed"), do: {:ok, :request_allowed}
  defp decode_kind("request_denied"), do: {:ok, :request_denied}
  defp decode_kind("request_failed"), do: {:ok, :request_failed}
  defp decode_kind(other), do: {:error, {:invalid_kind, other}}

  defp respond_to_decision_request(state, %{"id" => id, "host" => host, "port" => port} = frame) do
    request = %Request{
      id: id,
      session_id: frame["session_id"] || state.session_id,
      host: host,
      port: port,
      scheme: frame["scheme"] || "https",
      started_at: DateTime.utc_now()
    }

    context = %Context{
      session_id: state.session_id,
      recent_messages: recent_messages(state),
      request: request,
      metadata: context_metadata(state)
    }

    {decision, cache} = Decider.decide(state.policy, context, request, state.cache)
    send_decision(state.send_fn, id, decision)
    %{state | cache: cache}
  end

  defp recent_messages(%{owner_pid: pid, decide_spec: %{context_messages: limit}}) when is_pid(pid) do
    if Process.alive?(pid), do: fetch_history(pid, limit), else: []
  end

  defp recent_messages(_), do: []

  defp context_metadata(%{decide_spec: %{context_metadata: meta}}) when is_map(meta), do: meta
  defp context_metadata(_), do: %{}

  # Isolate the call: a session crash or timeout should not take the
  # bridge down with it. We spawn a probe process that does the
  # GenServer.call, then either get the result or fall through after a
  # bounded wait.
  defp fetch_history(pid, limit) do
    parent = self()
    ref = make_ref()

    {probe_pid, monitor_ref} =
      spawn_monitor(fn ->
        result =
          pid
          |> Condukt.Session.history()
          |> Enum.take(-limit)
          |> Enum.map(&serialise_message/1)

        send(parent, {ref, result})
      end)

    receive do
      {^ref, result} ->
        Process.demonitor(monitor_ref, [:flush])
        result

      {:DOWN, ^monitor_ref, :process, ^probe_pid, _reason} ->
        []
    after
      1_000 ->
        Process.exit(probe_pid, :kill)
        []
    end
  end

  defp serialise_message(%Condukt.Message{} = msg) do
    %{
      role: msg.role,
      content: Condukt.Message.text(msg),
      timestamp: msg.timestamp
    }
  end

  defp serialise_message(other), do: other

  defp send_decision(nil, _id, _decision), do: :ok

  defp send_decision(send_fn, id, :allow) do
    payload =
      JSON.encode!(%{
        type: "decision",
        id: id,
        action: "allow"
      }) <> "\n"

    send_fn.({:stdin, payload})
  end

  defp send_decision(send_fn, id, {:deny, reason}) do
    payload =
      JSON.encode!(%{
        type: "decision",
        id: id,
        action: "deny",
        reason: stringify_reason(reason)
      }) <> "\n"

    send_fn.({:stdin, payload})
  end

  defp stringify_reason(reason) when is_binary(reason), do: reason
  defp stringify_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp stringify_reason(reason), do: inspect(reason)

  # Public for tests
  @doc false
  def __decode_event_line__(line) do
    case JSON.decode(line) do
      {:ok, %{"type" => "event"} = frame} ->
        with {:ok, request} <- Request.from_json(frame["request"] || %{}),
             {:ok, kind} <- decode_kind(frame["kind"]) do
          {:ok,
           %Event{
             kind: kind,
             request: request,
             reason: frame["reason"],
             matched_rule: Event.decode_matched_rule(frame["matched_rule"]),
             at: DateTime.utc_now()
           }}
        end

      other ->
        {:error, {:unexpected_frame, other}}
    end
  end
end
