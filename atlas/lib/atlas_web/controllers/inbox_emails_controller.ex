defmodule AtlasWeb.InboxEmailsController do
  use AtlasWeb, :controller

  alias Atlas.Inbox
  alias Plug.Parsers.RequestTooLargeError

  require Logger

  def create(conn, _params) do
    timestamp = get_req_header(conn, "x-atlas-inbox-timestamp") |> List.first()
    signature = get_req_header(conn, "x-atlas-inbox-signature") |> List.first()

    with {:ok, raw_body, conn} <- read_raw_body(conn),
         :ok <- Inbox.verify_timestamp(timestamp),
         {:ok, webhook_secret} <- find_webhook_secret(conn),
         :ok <- Inbox.verify_signature(raw_body, timestamp, signature, webhook_secret) do
      case Inbox.persist_inbound(raw_body, envelope: envelope_headers(conn)) do
        {:ok, inbox_email} ->
          json(conn, %{ok: true, status: "queued", inbox_email_id: inbox_email.id})

        {:error, reason} ->
          Logger.error("Failed to persist inbound email: #{inspect(reason)}")
          conn |> put_status(:internal_server_error) |> json(%{error: "email not persisted"})
      end
    else
      {:error, :stale_timestamp} ->
        conn |> put_status(:unauthorized) |> json(%{error: "stale timestamp"})

      {:error, :no_webhook_secret} ->
        Logger.warning("Inbox email received but ATLAS_INBOX_WEBHOOK_SECRET is not configured")
        conn |> put_status(:unauthorized) |> json(%{error: "not configured"})

      {:error, :invalid_signature} ->
        conn |> put_status(:unauthorized) |> json(%{error: "invalid signature"})

      {:error, :body_too_large} ->
        conn |> put_status(:request_entity_too_large) |> json(%{error: "body too large"})
    end
  end

  defp read_raw_body(%{private: %{raw_body: raw_body}} = conn) when is_binary(raw_body) do
    {:ok, raw_body, conn}
  end

  defp read_raw_body(conn), do: read_raw_body(conn, [])

  defp read_raw_body(conn, chunks) do
    case Plug.Conn.read_body(conn, length: 10_000_000, read_length: 1_000_000) do
      {:ok, chunk, conn} ->
        {:ok, IO.iodata_to_binary(Enum.reverse([chunk | chunks])), conn}

      {:more, chunk, conn} ->
        read_raw_body(conn, [chunk | chunks])

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    RequestTooLargeError -> {:error, :body_too_large}
  end

  defp find_webhook_secret(conn) do
    case Map.fetch(conn.private, :atlas_inbox_webhook_secret) do
      {:ok, secret} -> secret
      :error -> Inbox.webhook_secret()
    end
    |> case do
      secret when is_binary(secret) and secret != "" -> {:ok, secret}
      _ -> {:error, :no_webhook_secret}
    end
  end

  defp envelope_headers(conn) do
    %{
      "from" => get_req_header(conn, "x-atlas-inbox-envelope-from") |> List.first(),
      "to" => get_req_header(conn, "x-atlas-inbox-envelope-to") |> List.first()
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
    |> Map.new()
  end
end
