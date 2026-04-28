defmodule Tuist.Orchard.WorkerNotifier do
  @moduledoc """
  In-memory pub/sub of WatchInstruction messages destined for individual
  Orchard workers.

  Each worker holds a long-lived WebSocket open via the watch RPC
  endpoint (`GET /api/orchard/v1/rpc/watch?workerName=X`). The watch
  process subscribes to `worker:<name>` on the Phoenix PubSub bus; the
  scheduler / VM lifecycle code calls `notify/2` to push instructions
  to that subscriber.

  The instructions match Cirrus's `v1.WatchInstruction` JSON shape:

      {"syncVMsAction": {}}
      {"resolveIPAction": {"session": "...", "vmUID": "..."}}
      {"portForwardAction": {"session": "...", "vmUID": "...", "port": 8080}}

  We currently only emit `syncVMsAction`; the others are wired up when
  port-forward / IP resolution land.
  """

  @doc """
  Subscribe the calling process to instructions for `worker_name`.
  Called by the WebSocket handler that fronts a worker's connection.
  """
  def subscribe(worker_name) when is_binary(worker_name) do
    Phoenix.PubSub.subscribe(Tuist.PubSub, topic(worker_name))
  end

  def unsubscribe(worker_name) when is_binary(worker_name) do
    Phoenix.PubSub.unsubscribe(Tuist.PubSub, topic(worker_name))
  end

  @doc """
  Broadcast a `WatchInstruction`-shaped map to whichever subscribers
  currently hold the watch for `worker_name`. No-op if the worker
  isn't connected — they'll pick up the side-effect on their next
  reconnect via the regular VM list.
  """
  def notify(worker_name, instruction) when is_binary(worker_name) and is_map(instruction) do
    Phoenix.PubSub.broadcast(
      Tuist.PubSub,
      topic(worker_name),
      {:watch_instruction, normalize(instruction)}
    )
  end

  defp topic(worker_name), do: "orchard:worker:" <> worker_name

  # Translate our internal {action: "syncVMs"} shape to the JSON
  # Cirrus's worker daemon expects on the wire.
  defp normalize(%{action: "syncVMs"}), do: %{"syncVMsAction" => %{}}

  defp normalize(%{action: "resolveIP", session: session, vm_uid: uid}) do
    %{"resolveIPAction" => %{"session" => session, "vmUID" => uid}}
  end

  defp normalize(%{action: "portForward", session: session, vm_uid: uid, port: port}) do
    %{
      "portForwardAction" => %{
        "session" => session,
        "vmUID" => uid,
        "port" => port
      }
    }
  end

  defp normalize(other), do: other
end
