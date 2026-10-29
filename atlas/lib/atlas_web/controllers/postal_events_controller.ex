defmodule AtlasWeb.PostalEventsController do
  use AtlasWeb, :controller

  alias Atlas.Letters
  alias Atlas.Letters.Config
  alias Atlas.Letters.Webhook

  require Logger

  def handle(conn, params) do
    raw_body = conn.private[:raw_body]
    signature = get_req_header(conn, "signature") |> List.first()
    signing_key = conn.private[:postal_webhook_signing_key] || Config.webhook_signing_key()

    with signing_key when is_binary(signing_key) and signing_key != "" <- signing_key,
         :ok <- Webhook.verify_signature(raw_body, signature, signing_key) do
      case Letters.record_webhook(params) do
        {:ok, _letter} ->
          json(conn, %{ok: true})

        {:error, :letter_not_found} ->
          json(conn, %{ok: true, ignored: true})

        {:error, reason} ->
          Logger.error("Could not persist verified postal delivery webhook: #{inspect(reason)}")
          conn |> put_status(:internal_server_error) |> json(%{error: "webhook not persisted"})
      end
    else
      missing_key when missing_key in [nil, ""] ->
        Logger.warning("Postal delivery webhook received without a signing key")
        conn |> put_status(:unauthorized) |> json(%{error: "not configured"})

      {:error, :invalid_signature} ->
        conn |> put_status(:unauthorized) |> json(%{error: "invalid signature"})
    end
  end
end
