defmodule TuistWeb.SandboxNodeWebSock do
  @moduledoc """
  Server side of a sandboxd node connection (protocol in
  `infra/sandboxd/AGENTS.md`). Registers the node in
  `Tuist.Sandboxes.Nodes` on `hello`, turns `{:sandbox_command, ...}`
  messages from `Nodes.call/4` into `command` frames and routes the
  node's `result`/`stream` frames back to the waiting caller by id.
  Events and reports go straight to the `Tuist.Sandboxes` context.
  """

  @behaviour WebSock

  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.Nodes

  require Logger

  @impl WebSock
  def init(%{node_name: node_name}) do
    {:ok, %{node_name: node_name, registered?: false, pending: %{}, next_id: 1, info: empty_info()}}
  end

  defp empty_info do
    %{capacity: %{}, memory: %{}, templates: [], sandboxes: [], daemon_version: nil, firecracker_version: nil}
  end

  @impl WebSock
  def handle_in({payload, [opcode: :text]}, state) do
    case JSON.decode(payload) do
      {:ok, %{"type" => type} = frame} when is_binary(type) ->
        handle_frame(type, frame, state)

      _ ->
        Logger.warning("sandboxes: node sent an undecodable frame", node: state.node_name)
        {:ok, state}
    end
  end

  def handle_in({_payload, [opcode: :binary]}, state), do: {:ok, state}

  defp handle_frame("hello", frame, state) do
    info = merge_info(state.info, frame)

    case register(state, info) do
      :ok ->
        Logger.info("sandboxes: node connected",
          node: state.node_name,
          daemon_version: info.daemon_version,
          firecracker_version: info.firecracker_version,
          sandboxes: length(info.sandboxes),
          templates: Enum.map(info.templates, &"#{&1.name}:#{&1.tag}#{if &1.ready, do: "", else: " (building)"}")
        )

        :ok = Sandboxes.reconcile_node_report(state.node_name, frame)
        {:ok, %{state | registered?: true, info: info}}

      {:error, reason} ->
        Logger.warning("sandboxes: node registration failed", node: state.node_name, reason: inspect(reason))
        {:stop, {:registration_failed, reason}, {1011, "registration failed"}, state}
    end
  end

  defp handle_frame("result", %{"id" => id} = frame, state) do
    case Map.pop(state.pending, id) do
      {nil, _pending} ->
        Logger.warning("sandboxes: node answered an unknown command", node: state.node_name, command_id: id)
        {:ok, state}

      {{ref, from}, pending} ->
        send(from, {:sandbox_result, ref, result(frame)})
        {:ok, %{state | pending: pending}}
    end
  end

  defp handle_frame("stream", %{"id" => id} = frame, state) do
    with {ref, from} <- Map.get(state.pending, id),
         {:ok, stream} <- stream_name(frame["stream"]),
         {:ok, data} <- Base.decode64(frame["data_b64"] || "") do
      send(from, {:sandbox_stream, ref, stream, data})
    end

    {:ok, state}
  end

  defp handle_frame("event", %{"event" => "template_ready", "name" => name} = frame, state) when is_binary(name) do
    template = %{name: name, tag: frame["tag"], ready: true}
    templates = [template | Enum.reject(state.info.templates, &(&1.name == name))]
    state = put_info(state, %{state.info | templates: templates})
    :ok = Sandboxes.handle_node_event(state.node_name, frame)
    {:ok, state}
  end

  defp handle_frame("event", frame, state) do
    :ok = Sandboxes.handle_node_event(state.node_name, frame)
    {:ok, state}
  end

  defp handle_frame("report", frame, state) do
    state = put_info(state, merge_info(state.info, frame))
    :ok = Sandboxes.reconcile_node_report(state.node_name, frame)
    {:ok, state}
  end

  defp handle_frame(type, _frame, state) do
    Logger.warning("sandboxes: node sent an unknown frame", node: state.node_name, frame_type: type)
    {:ok, state}
  end

  @impl WebSock
  def handle_info({:sandbox_command, ref, op, args, from}, state) do
    id = "c#{state.next_id}"
    frame = JSON.encode!(%{type: "command", id: id, op: op, args: args})
    pending = Map.put(state.pending, id, {ref, from})
    {:push, {:text, frame}, %{state | next_id: state.next_id + 1, pending: pending}}
  end

  def handle_info(:sandbox_node_superseded, state) do
    Logger.info("sandboxes: node connection superseded by a reconnect", node: state.node_name)
    {:stop, :normal, {1000, "superseded"}, state}
  end

  def handle_info(_message, state), do: {:ok, state}

  @impl WebSock
  def terminate(reason, state) do
    node_name = Map.get(state, :node_name)
    pending = Map.get(state, :pending, %{})

    if Map.get(state, :registered?) and is_binary(node_name), do: Nodes.unregister(node_name)

    Enum.each(pending, fn {_id, {ref, from}} ->
      send(from, {:sandbox_result, ref, {:error, :node_disconnected}})
    end)

    Logger.info("sandboxes: node disconnected",
      node: node_name,
      reason: inspect(reason),
      pending_commands: map_size(pending)
    )

    :ok
  end

  defp register(%{registered?: true} = state, info), do: Nodes.update(state.node_name, info)
  defp register(state, info), do: Nodes.register(state.node_name, info)

  defp put_info(%{registered?: true} = state, info) do
    _ = Nodes.update(state.node_name, info)
    %{state | info: info}
  end

  defp put_info(state, info), do: %{state | info: info}

  defp result(%{"ok" => true} = frame), do: {:ok, Map.get(frame, "data") || %{}}
  defp result(%{"ok" => false} = frame), do: {:error, Map.get(frame, "error") || "unknown node error"}
  defp result(frame), do: {:error, "malformed result frame: #{inspect(Map.delete(frame, "data"))}"}

  defp stream_name("stdout"), do: {:ok, :stdout}
  defp stream_name("stderr"), do: {:ok, :stderr}
  defp stream_name(_stream), do: :error

  defp merge_info(info, frame) do
    info
    |> maybe_merge(:capacity, frame["capacity"], &capacity/1)
    |> maybe_merge(:memory, frame["memory"], &memory/1)
    |> maybe_merge(:templates, frame["templates"], &templates/1)
    |> maybe_merge(:sandboxes, frame["sandboxes"], &sandboxes/1)
    |> maybe_merge(:daemon_version, frame["daemon_version"], & &1)
    |> maybe_merge(:firecracker_version, frame["firecracker_version"], & &1)
  end

  defp maybe_merge(info, _key, nil, _normalize), do: info
  defp maybe_merge(info, key, value, normalize), do: Map.put(info, key, normalize.(value))

  defp capacity(%{} = capacity), do: %{memory_bytes: capacity["memory_bytes"], cpus: capacity["cpus"]}
  defp capacity(_capacity), do: %{}

  defp memory(%{} = memory), do: %{used_bytes: memory["used_bytes"]}
  defp memory(_memory), do: %{}

  defp templates(templates) when is_list(templates) do
    for %{"name" => name} = template <- templates, is_binary(name) do
      %{name: name, tag: template["tag"], ready: template["ready"] == true}
    end
  end

  defp templates(_templates), do: []

  defp sandboxes(sandboxes) when is_list(sandboxes) do
    for %{"id" => id} = sandbox <- sandboxes, is_binary(id) do
      %{
        id: id,
        state: sandbox["state"],
        template: sandbox["template"],
        template_tag: sandbox["template_tag"],
        vcpus: sandbox["vcpus"],
        memory_mb: sandbox["memory_mb"],
        worker_running: sandbox["worker_running"] == true
      }
    end
  end

  defp sandboxes(_sandboxes), do: []
end
