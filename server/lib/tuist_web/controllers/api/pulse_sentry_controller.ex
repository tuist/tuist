defmodule TuistWeb.API.PulseSentryController do
  @moduledoc """
  Sentry's envelope endpoint for an account enrolled in Pulse.

  A Sentry SDK configured with the DSN
  `https://<account token>@<host>/api/accounts/<handle>/pulse/sentry/<service>/1`
  posts here; `TuistWeb.SentryAuthPlug` presents the DSN key as the bearer
  token, so the ordinary API authentication verifies it, and the token needs
  the `account:pulse:write` scope. The envelope is forwarded to Pulse, which
  groups and scrubs its events into the account's errors under `<service>`.
  """
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Accounts
  alias Tuist.Authorization
  alias Tuist.Pulse
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.Authentication
  alias TuistWeb.Plugs.DeflateBodyReader

  # Sentry's own limit for an envelope's event item, held to the whole
  # envelope once decompressed (attachments and other items included).
  @max_body_bytes 1_048_576
  @service ~r/\A[A-Za-z0-9._-]{1,64}\z/
  @project_id ~r/\A[0-9]{1,20}\z/

  tags ["Pulse"]

  operation(:envelope,
    summary: "Send a Sentry envelope to the account's Pulse errors.",
    description:
      "Sentry SDKs post here when their DSN is `https://<account token>@<host>/api/accounts/<handle>/pulse/sentry/<service>/1`. The token goes in the DSN key, which SDKs send in `X-Sentry-Auth` (or the `sentry_key` query parameter), and needs the `account:pulse:write` scope. Event items become errors of `<service>`; other items are accepted and dropped.",
    operation_id: "sendPulseSentryEnvelope",
    parameters: [
      account_handle: [in: :path, type: :string, required: true, description: "The account handle."],
      service: [
        in: :path,
        required: true,
        description: "The producer the errors belong to.",
        schema: %Schema{type: :string, pattern: "^[A-Za-z0-9._-]{1,64}$"}
      ],
      project_id: [
        in: :path,
        required: true,
        description: "The DSN's project number, which Sentry SDKs require. It is not used.",
        schema: %Schema{type: :string, pattern: "^[0-9]{1,20}$"}
      ]
    ],
    request_body:
      {"A Sentry envelope, optionally gzip- or deflate-encoded", "application/x-sentry-envelope",
       %Schema{type: :string, format: :binary}},
    responses: %{
      ok:
        {"Envelope accepted", "application/json",
         %Schema{
           title: "PulseSentryEnvelopeResponse",
           type: :object,
           properties: %{id: %Schema{type: :string, description: "The envelope's event ID, without dashes."}}
         }},
      bad_request: {"Invalid service, project number or envelope", "application/json", Error},
      unauthorized: {"Authentication required", "application/json", Error},
      forbidden: {"An account:pulse:write token of an account enrolled in Pulse is required", "application/json", Error},
      not_found: {"Account not found", "application/json", Error},
      request_entity_too_large: {"Envelope larger than 1 MiB", "application/json", Error},
      too_many_requests: {"Pulse rate limited", "application/json", Error},
      bad_gateway: {"Pulse rejected the forwarded envelope", "application/json", Error},
      service_unavailable: {"Pulse unavailable", "application/json", Error}
    }
  )

  def envelope(conn, %{"account_handle" => handle, "service" => service, "project_id" => project_id}) do
    with true <- Regex.match?(@service, service) and Regex.match?(@project_id, project_id),
         account when not is_nil(account) <- Accounts.get_account_by_handle(handle),
         :ok <- Authorization.authorize(:pulse_write, Authentication.authenticated_subject(conn), account),
         true <- Pulse.available?(account) || :not_enrolled,
         {:ok, body, headers, conn} <- read_envelope(conn),
         {:ok, status, response, headers} <- Pulse.forward_sentry_envelope(service, project_id, body, headers) do
      conn = Enum.reduce(headers, conn, fn {name, value}, conn -> put_resp_header(conn, name, value) end)
      respond(conn, status, response)
    else
      false ->
        error(conn, :bad_request, "The service or project number in the DSN path is invalid.")

      nil ->
        error(conn, :not_found, "Account not found.")

      {:error, :too_large, conn} ->
        error(conn, :request_entity_too_large, "The envelope is larger than 1 MiB.")

      {:error, :unsupported_encoding} ->
        error(conn, :bad_request, "The envelope must be uncompressed, or gzip-, br- or zstd-encoded.")

      {:error, :undecodable} ->
        error(conn, :bad_request, "The envelope could not be decompressed.")

      {:error, :not_configured} ->
        error(conn, :service_unavailable, "Pulse is not configured.")

      {:error, :unavailable} ->
        error(conn, :service_unavailable, "Pulse is unavailable. Try again later.")

      _ ->
        error(conn, :forbidden, "Sending errors to Pulse requires an account:pulse:write token of an enrolled account.")
    end
  end

  # The endpoint's parsers pass this content type through unread. Returns the
  # body and the headers to forward it with. Gzip bodies are inflated here,
  # holding the inflated size to the limit. The server has no brotli or zstd
  # decoder, so those bodies (brotli is sentry-python's default when the
  # `brotli` module is installed) are forwarded encoded, and Pulse's Sentry
  # route holds their decoded size to the same limit.
  defp read_envelope(conn) do
    content_type = Enum.filter(conn.req_headers, fn {name, _} -> name == "content-type" end)

    case get_req_header(conn, "content-encoding") do
      encoding when encoding in [[], ["identity"], ["gzip"]] ->
        conn |> DeflateBodyReader.read_body(length: @max_body_bytes) |> read_result(content_type)

      [encoding] when encoding in ["br", "zstd"] ->
        conn
        |> read_body(length: @max_body_bytes)
        |> read_result([{"content-encoding", encoding} | content_type])

      _ ->
        {:error, :unsupported_encoding}
    end
  end

  defp read_result({:ok, body, conn}, headers), do: {:ok, body, headers, conn}
  defp read_result({:more, _partial, conn}, _headers), do: {:error, :too_large, conn}
  defp read_result({:error, :invalid_deflate_body}, _headers), do: {:error, :undecodable}
  defp read_result({:error, _reason}, _headers), do: {:error, :unavailable}

  # Pulse's answer passes through when it describes the envelope; anything
  # else is the server's own writer failing, not the caller's request.
  defp respond(conn, 413, _body), do: error(conn, :request_entity_too_large, "The envelope is larger than 1 MiB.")

  # Pulse describes envelopes it rejects in JSON; a plain-text 400 is its HTTP
  # layer failing to read the body, such as a corrupt br or zstd stream.
  defp respond(conn, 400, body) do
    case JSON.decode(body) do
      {:ok, _} -> conn |> put_resp_content_type("application/json") |> send_resp(400, body)
      {:error, _} -> error(conn, :bad_request, "The envelope could not be read.")
    end
  end

  defp respond(conn, status, body) when status in 200..299 or status == 429 do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, body)
  end

  defp respond(conn, _status, _body), do: error(conn, :bad_gateway, "Pulse rejected the envelope.")

  defp error(conn, status, message), do: conn |> put_status(status) |> json(%{message: message})
end
