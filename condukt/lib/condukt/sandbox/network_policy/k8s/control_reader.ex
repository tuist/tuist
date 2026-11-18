defmodule Condukt.Sandbox.NetworkPolicy.K8s.ControlReader do
  @moduledoc false

  # GenServer that reads NDJSON events from the `condukt-egress` sidecar's
  # control channel and dispatches them into telemetry events.
  #
  # The wire format is one JSON-encoded `Event` per line. Lines arrive
  # over a `gen_tcp`-style socket that the caller is expected to have
  # already established (typically through a K8s port-forward proxy that
  # the `Condukt.Sandbox.Kubernetes` runtime opened for this session).
  #
  # We accept arbitrary sources via the `:transport` option so this module
  # can be exercised in tests with a plain `:gen_tcp` connection or a
  # programmable mock without depending on the `:k8s` client.

  use GenServer

  alias Condukt.Sandbox.NetworkPolicy
  alias Condukt.Sandbox.NetworkPolicy.Event
  alias Condukt.Sandbox.NetworkPolicy.Request

  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Decode a single NDJSON event line into a `Condukt.Sandbox.NetworkPolicy.Event`.

  The kind field is converted from the snake_case wire format
  (`request_opened`, `request_closed`, etc.) to the matching atom.
  """
  def decode_line(line) when is_binary(line) do
    with {:ok, json} <- decode_json(line),
         {:ok, %{"kind" => kind, "request" => request_map}} <- ensure_shape(json),
         {:ok, request} <- Request.from_json(request_map),
         {:ok, kind} <- decode_kind(kind),
         {:ok, at} <- decode_at(Map.get(json, "at")) do
      {:ok,
       %Event{
         kind: kind,
         request: request,
         reason: Map.get(json, "reason"),
         matched_rule: Event.decode_matched_rule(Map.get(json, "matched_rule")),
         at: at
       }}
    end
  end

  defp ensure_shape(%{"kind" => _, "request" => _} = json), do: {:ok, json}
  defp ensure_shape(other), do: {:error, {:missing_event_fields, other}}

  @impl true
  def init(opts) do
    state = %{
      socket: Keyword.fetch!(opts, :socket),
      policy: Keyword.get(opts, :policy),
      buffer: ""
    }

    {:ok, state}
  end

  @impl true
  def handle_info({:tcp, _socket, data}, state) do
    {:noreply, consume(state, data)}
  end

  def handle_info({:tcp_closed, _socket}, state) do
    {:stop, :normal, state}
  end

  def handle_info({:tcp_error, _socket, reason}, state) do
    {:stop, {:tcp_error, reason}, state}
  end

  def handle_info(_other, state), do: {:noreply, state}

  defp consume(state, data) when is_binary(data) do
    full = state.buffer <> data
    {complete, leftover} = split_lines(full)

    Enum.each(complete, &handle_line(&1, state.policy))

    %{state | buffer: leftover}
  end

  defp handle_line(line, policy) do
    case decode_line(line) do
      {:ok, event} -> deliver(policy, event)
      {:error, reason} -> log_drop(reason)
    end
  end

  defp log_drop(reason) do
    Logger.warning(fn -> "[sandbox.network_policy.k8s] dropping malformed event line: #{inspect(reason)}" end)
  end

  defp deliver(policy, event) do
    NetworkPolicy.deliver(policy, event.kind, event.request,
      reason: event.reason,
      matched_rule: event.matched_rule,
      at: event.at
    )
  end

  defp split_lines(buffer) do
    case String.split(buffer, "\n") do
      [single] -> {[], single}
      multiple -> {Enum.drop(multiple, -1), List.last(multiple)}
    end
  end

  defp decode_json(line) do
    case JSON.decode(line) do
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, {:invalid_json, reason}}
    end
  end

  defp decode_kind("request_opened"), do: {:ok, :request_opened}
  defp decode_kind("request_closed"), do: {:ok, :request_closed}
  defp decode_kind("request_allowed"), do: {:ok, :request_allowed}
  defp decode_kind("request_denied"), do: {:ok, :request_denied}
  defp decode_kind("request_failed"), do: {:ok, :request_failed}
  defp decode_kind(other), do: {:error, {:invalid_kind, other}}

  defp decode_at(nil), do: {:ok, DateTime.utc_now()}

  defp decode_at(binary) when is_binary(binary) do
    case DateTime.from_iso8601(binary) do
      {:ok, dt, _offset} -> {:ok, dt}
      {:error, reason} -> {:error, {:invalid_at, reason}}
    end
  end
end
