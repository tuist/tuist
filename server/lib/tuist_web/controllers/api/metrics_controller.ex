defmodule TuistWeb.API.MetricsController do
  @moduledoc """
  Per-account Prometheus-compatible scrape endpoint.

  Access requires a Bearer-authenticated account token carrying the
  `account:metrics:read` scope. Output is OpenMetrics text when the client
  requests it via `Accept: application/openmetrics-text`, otherwise
  Prometheus 0.0.4 text — both formats are accepted by Prometheus, Grafana
  Agent, and Alloy.
  """

  use TuistWeb, :controller

  alias Tuist.Authorization
  alias Tuist.Metrics
  alias Tuist.Metrics.Exposition
  alias TuistWeb.Authentication
  alias TuistWeb.RateLimit.Metrics, as: MetricsRateLimit

  plug TuistWeb.Plugs.LoaderPlug

  @required_scope "account:metrics:read"

  def show(%{assigns: %{selected_account: account}} = conn, _params) do
    subject = Authentication.authenticated_subject(conn)

    with :ok <- Authorization.authorize(:account_read_metrics, subject, account),
         :ok <- check_rate_limit(account.id) do
      format = conn |> get_req_header("accept") |> List.first() |> Exposition.negotiate()
      snapshot = Metrics.snapshot(account.id)
      body = Exposition.render(snapshot, format)

      conn
      |> put_resp_content_type_raw(Exposition.content_type(format))
      |> send_resp(:ok, body)
    else
      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{
          message:
            "The authenticated token is not authorized to read metrics for account #{account.name}. " <>
              "Grant the #{@required_scope} scope to enable this endpoint."
        })

      {:error, :rate_limited} ->
        conn
        |> put_resp_header("retry-after", "10")
        |> put_status(:too_many_requests)
        |> json(%{
          message:
            "Too many metric scrape requests for account #{account.name}. " <>
              "Reduce the scrape interval to at most one request every 10 seconds."
        })
    end
  end

  defp check_rate_limit(account_id) do
    case MetricsRateLimit.hit(account_id) do
      {:allow, _count} -> :ok
      {:deny, _limit} -> {:error, :rate_limited}
    end
  end

  # `Phoenix.Controller.put_resp_content_type/2` only accepts a registered
  # format. The metric content types include version parameters so we set the
  # header directly.
  defp put_resp_content_type_raw(conn, content_type) do
    Plug.Conn.put_resp_header(conn, "content-type", content_type)
  end
end
