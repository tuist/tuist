defmodule TuistWeb.Plugs.BrowserTelemetryPlug do
  @moduledoc """
  Bounded same-origin Faro gateway, ahead of the endpoint's general body parser.
  Forwards only to an operator-configured receiver, without browser credentials.
  """
  @behaviour Plug

  import Plug.Conn

  alias Tuist.Accounts
  alias Tuist.Environment
  alias TuistWeb.BrowserTelemetry.Enrichment
  alias TuistWeb.Plugs.SameOriginCSRFExemptionPlug
  alias TuistWeb.RemoteIp

  @body_limit 262_144

  @impl true
  def init(opts), do: Plug.Session.init(Keyword.fetch!(opts, :session_options))

  @impl true
  def call(%{request_path: "/-/faro/collect"} = conn, session_options) do
    receiver_url = Environment.faro_receiver_url()

    cond do
      receiver_url in [nil, ""] -> respond(conn, 404)
      conn.method != "POST" -> conn |> put_resp_header("allow", "POST") |> respond(405)
      not SameOriginCSRFExemptionPlug.same_origin_request?(conn) -> respond(conn, 403)
      get_req_header(conn, "content-encoding") not in [[], ["identity"]] -> respond(conn, 415)
      true -> read_and_forward(conn, session_options, receiver_url)
    end
  end

  def call(conn, _opts), do: conn

  defp read_and_forward(conn, session_options, receiver_url) do
    case read_body(conn, length: @body_limit, read_length: @body_limit, read_timeout: 5_000) do
      {:ok, body, conn} when byte_size(body) <= @body_limit ->
        conn = conn |> Plug.Session.call(session_options) |> fetch_session()

        with {:ok, payload} <- Jason.decode(body),
             {:ok, payload} <-
               Enrichment.enrich(
                 payload,
                 authentication(conn),
                 RemoteIp.cloudflare_ray_id(conn) || "",
                 Environment.app_url(),
                 to_string(Environment.env())
               ) do
          forward(conn, receiver_url, payload)
        else
          _ -> respond(conn, 400)
        end

      {:ok, _body, conn} ->
        respond(conn, 413)

      {:more, _body, conn} ->
        respond(conn, 413)

      {:error, _reason} ->
        respond(conn, 400)
    end
  end

  defp authentication(conn) do
    # Checking the token avoids touching last-sign-in or refreshing a cookie on
    # every background telemetry POST. Remember-me restoration happens on page
    # navigation; a missing, expired or revoked session is anonymous here.
    case get_session(conn, :user_token) do
      token when is_binary(token) ->
        if Accounts.get_user_by_session_token(token), do: "authenticated", else: "anonymous"

      _ ->
        "anonymous"
    end
  end

  defp forward(conn, receiver_url, payload) do
    # No retries: an ambiguous timeout can mean Alloy accepted the batch. Faro
    # sees the failure; the gateway must not silently multiply measurements.
    case Req.post(receiver_url,
           json: payload,
           retry: false,
           redirect: false,
           connect_options: [timeout: 1_000],
           receive_timeout: 2_000
         ) do
      {:ok, %{status: status}} when status in 200..299 -> respond(conn, 202)
      _ -> respond(conn, 503)
    end
  end

  defp respond(conn, status) do
    conn |> put_resp_header("cache-control", "no-store") |> send_resp(status, "") |> halt()
  end
end
