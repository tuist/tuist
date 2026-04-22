defmodule TuistWeb.Plugs.GitHubWebhookLoggingPlug do
  @moduledoc """
  Logs request metadata for GitHub webhook traffic before the body is parsed.

  This helps distinguish real GitHub deliveries from slow or malformed traffic
  that times out while Bandit is still reading the request body.
  """
  @behaviour Plug

  import Plug.Conn

  alias TuistWeb.RemoteIp

  require Logger

  @github_webhook_path "/webhooks/github"

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    if conn.request_path == @github_webhook_path do
      register_before_send(conn, &log_request/1)
    else
      conn
    end
  end

  defp log_request(conn) do
    metadata = github_request_metadata(conn)
    log_message = "GitHub webhook request: #{inspect(Map.new(metadata))}"

    if conn.status && conn.status >= 400 do
      Logger.warning(log_message, metadata)
    else
      Logger.info(log_message, metadata)
    end

    conn
  end

  defp github_request_metadata(conn) do
    [
      request_path: conn.request_path,
      status: conn.status,
      remote_ip: RemoteIp.get(conn),
      peer_ip: format_ip(conn.remote_ip),
      forwarded_for: first_header(conn, "x-forwarded-for"),
      user_agent: first_header(conn, "user-agent"),
      github_event: first_header(conn, "x-github-event"),
      github_delivery: first_header(conn, "x-github-delivery"),
      content_length: first_header(conn, "content-length"),
      has_signature: header_present?(conn, "x-hub-signature-256")
    ]
  end

  defp first_header(conn, header) do
    conn
    |> get_req_header(header)
    |> List.first()
  end

  defp header_present?(conn, header) do
    case first_header(conn, header) do
      nil -> false
      "" -> false
      _value -> true
    end
  end

  defp format_ip(nil), do: nil
  defp format_ip(ip), do: ip |> :inet_parse.ntoa() |> to_string()
end
