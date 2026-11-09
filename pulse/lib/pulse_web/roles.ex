defmodule PulseWeb.Roles do
  @moduledoc """
  Refuses requests for a role this instance does not run (see `Pulse.Roles`)
  with a retryable 503, so a misrouted ingest batch is retried elsewhere
  rather than dropped. Health and self-monitoring endpoints are always served.
  """
  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    role = role(conn.path_info)

    if is_nil(role) or Pulse.Roles.enabled?(role) do
      conn
    else
      conn
      |> put_resp_header("retry-after", "5")
      |> put_resp_content_type("text/plain")
      |> send_resp(503, "this instance does not serve #{role} requests")
      |> halt()
    end
  end

  defp role(path) when path in [["metrics"], ["healthz"], ["readyz"]], do: nil
  defp role(path), do: if(PulseWeb.IngestAdmission.ingest_path(path), do: :ingest, else: :query)
end
