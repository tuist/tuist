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

  # Sentry's own limit for an envelope's event item.
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
         {:ok, body, conn} <- read_envelope(conn),
         {:ok, status, response} <- Pulse.forward_sentry_envelope(service, project_id, body, conn.req_headers) do
      respond(conn, status, response)
    else
      false ->
        error(conn, :bad_request, "The service or project number in the DSN path is invalid.")

      nil ->
        error(conn, :not_found, "Account not found.")

      {:error, :too_large, conn} ->
        error(conn, :request_entity_too_large, "The envelope is larger than 1 MiB.")

      {:error, :not_configured} ->
        error(conn, :service_unavailable, "Pulse is not configured.")

      {:error, :unavailable} ->
        error(conn, :service_unavailable, "Pulse is unavailable. Try again later.")

      _ ->
        error(conn, :forbidden, "Sending errors to Pulse requires an account:pulse:write token of an enrolled account.")
    end
  end

  # The endpoint's parsers pass this content type through unread.
  defp read_envelope(conn) do
    case read_body(conn, length: @max_body_bytes) do
      {:ok, body, conn} -> {:ok, body, conn}
      {:more, _partial, conn} -> {:error, :too_large, conn}
      {:error, _reason} -> {:error, :unavailable}
    end
  end

  # Pulse's answer passes through when it describes the envelope; anything
  # else is the server's own writer failing, not the caller's request.
  defp respond(conn, status, body) when status in 200..299 or status in [400, 413, 429] do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, body)
  end

  defp respond(conn, _status, _body), do: error(conn, :bad_gateway, "Pulse rejected the envelope.")

  defp error(conn, status, message), do: conn |> put_status(status) |> json(%{message: message})
end
