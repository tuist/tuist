defmodule PulseWeb.MCPController do
  @moduledoc """
  Streamable HTTP transport for `Pulse.MCP` (MCP revision `2026-07-28`).

  Each POST carries exactly one JSON-RPC request or notification; batches
  are rejected. Notifications are acknowledged with `202 Accepted` and an
  empty body. Requests must carry the mirrored metadata headers validated
  by `PulseWeb.MCPHeaders`. The transport is stateless: it never mints or
  echoes `Mcp-Session-Id`, and ignores `Mcp-Session-Id` and `Last-Event-ID`.
  GET and DELETE return `405 Method Not Allowed` because this revision
  removed the standalone stream and session termination.

  Origin and media-type checks run earlier, before body parsing, in
  `PulseWeb.MCPRequestGate`.
  """

  use PulseWeb, :controller

  alias Pulse.Alerting.Subscriptions
  alias Pulse.MCP
  alias PulseWeb.MCPHeaders

  @header_mismatch -32_020

  def rpc(conn, _params) do
    # Read the parsed body, not merged params, so query strings cannot
    # supply protocol fields.
    message = conn.body_params

    case MCP.classify(message) do
      {:notification, _method} ->
        send_resp(conn, 202, "")

      {:invalid, _id} ->
        respond(conn, MCP.dispatch(message))

      {:request, id, _method, _params} = request ->
        case MCPHeaders.validate(conn, request) do
          :ok -> respond(conn, MCP.dispatch(message, %{conn: conn}))
          {:error, reason} -> respond(conn, {:reply, MCP.error_response(id, @header_mismatch, reason)})
        end
    end
  end

  def method_not_allowed(conn, _params) do
    conn
    |> put_resp_header("allow", "POST")
    |> send_resp(405, "")
  end

  defp respond(conn, {:reply, response}) do
    conn
    |> put_status(status(response))
    |> json(response)
  end

  defp respond(conn, {:stream, messages}) do
    body = Enum.map_join(messages, fn message -> "data: #{Pulse.JSON.encode!(message)}\n\n" end)

    conn
    |> put_resp_content_type("text/event-stream")
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_header("x-accel-buffering", "no")
    |> send_resp(200, body)
  end

  defp respond(conn, {:subscription, subscription}) do
    case Subscriptions.acquire(subscription.descriptor) do
      {:ok, keys} ->
        try do
          Process.flag(:max_heap_size, %{
            size: 8_000_000,
            kill: true,
            error_logger: false,
            include_shared_binaries: true
          })

          conn =
            conn
            |> put_resp_content_type("text/event-stream")
            |> put_resp_header("cache-control", "no-cache")
            |> put_resp_header("x-accel-buffering", "no")
            |> send_chunked(200)

          case send_message(conn, subscription.acknowledgement) do
            {:ok, conn} -> stream(conn, subscription.descriptor, subscription.completion)
            {:error, _} -> conn
          end
        after
          Subscriptions.release(keys)
        end

      {:error, _} ->
        respond(
          conn,
          {:reply, MCP.error_response(subscription.completion["id"], -32_000, "Subscription capacity exceeded")}
        )
    end
  end

  defp stream(conn, descriptor, completion) do
    receive do
      :pulse_subscription_shutdown -> finish(conn, completion)
    after
      Subscriptions.interval() -> poll_stream(conn, descriptor, completion)
    end
  end

  defp poll_stream(conn, descriptor, completion) do
    case Subscriptions.poll(descriptor) do
      {:ok, uris, next} ->
        messages =
          Enum.map(uris, fn uri ->
            %{
              "jsonrpc" => "2.0",
              "method" => "notifications/resources/updated",
              "params" => %{"uri" => uri, "_meta" => completion["result"]["_meta"]}
            }
          end)

        case send_updates(conn, messages) do
          {:ok, conn} -> stream(conn, next, completion)
          {:error, _} -> conn
        end

      :complete ->
        finish(conn, completion)
    end
  end

  defp send_updates(conn, []), do: chunk(conn, ": heartbeat\n\n")
  defp send_updates(conn, messages), do: Enum.reduce_while(messages, {:ok, conn}, &send_update/2)

  defp send_update(message, {:ok, conn}) do
    case send_message(conn, message) do
      {:ok, conn} -> {:cont, {:ok, conn}}
      error -> {:halt, error}
    end
  end

  defp send_message(conn, message), do: chunk(conn, "data: #{Pulse.JSON.encode!(message)}\n\n")

  defp finish(conn, completion) do
    case send_message(conn, completion) do
      {:ok, conn} -> conn
      {:error, _} -> conn
    end
  end

  defp status(%{"error" => %{"code" => -32_001}}), do: 401
  defp status(%{"error" => %{"code" => -32_003}}), do: 403
  defp status(%{"error" => %{"code" => -32_000}}), do: 503
  defp status(%{"error" => %{"code" => -32_601}}), do: 404
  defp status(%{"error" => %{"code" => -32_603}}), do: 500
  defp status(%{"error" => _}), do: 400
  defp status(_response), do: 200
end
