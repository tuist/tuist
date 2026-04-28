defmodule TuistWeb.Orchard.RPCController do
  @moduledoc """
  Worker-side RPC endpoints. The only one we implement today is
  `/v1/rpc/watch`, the long-lived WebSocket each Orchard worker keeps
  open to receive scheduling instructions from the controller.

  The wire format is JSON-encoded `WatchInstruction` messages — same
  shape as upstream's `pkg/resource/v1.WatchInstruction`. Today we
  only emit `syncVMsAction`; on receipt the worker re-fetches its VM
  list and brings local Tart state in sync.
  """
  use TuistWeb, :controller

  alias TuistWeb.Orchard.WatchSocket
  alias TuistWeb.Plugs.OrchardAuthPlug

  def watch(conn, params) do
    conn = OrchardAuthPlug.require_role(conn, "compute:read")

    if conn.halted do
      conn
    else
      case Map.get(params, "workerName") do
        worker_name when is_binary(worker_name) and worker_name != "" ->
          # Hand the connection off to WebSockAdapter. The handler
          # subscribes to `orchard:worker:<name>` on the PubSub bus
          # and forwards every {:watch_instruction, payload} message
          # to the WebSocket client as a JSON binary frame.
          conn
          |> WebSockAdapter.upgrade(WatchSocket, %{worker_name: worker_name}, timeout: 60_000)
          |> halt()

        _ ->
          conn
          |> put_status(400)
          |> json(%{"message" => "workerName query parameter is required"})
      end
    end
  end
end
