defmodule PulseWeb.IngestAdmission do
  @moduledoc """
  Admits ingest requests through `Pulse.IngestAdmission` before their bodies
  are read, answering 429 with `Retry-After` when the request's signal has no
  reserved or shared slot left, or when a verified tenant is over its
  configured `Pulse.TenantLimits`.
  """
  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{method: "POST"} = conn, _opts) do
    case ingest_path(conn.path_info) do
      nil -> conn
      {format, signal} -> admit(conn, format, signal)
    end
  end

  def call(conn, _opts), do: conn

  defp admit(conn, format, signal) do
    limited = limited_tenant(conn, format)

    with :ok <- rate(conn, limited),
         :ok <- Pulse.IngestAdmission.acquire(signal, tenant(conn), limited) do
      register_before_send(conn, fn conn ->
        Pulse.IngestAdmission.release()
        meter(conn, format, signal)
        conn
      end)
    else
      {:error, reason} -> refuse(conn, format, reason)
    end
  end

  # Fairness key only, before authentication: `PulseWeb.BasicTenant` has
  # already turned a Basic username into this header. Sentry projects map to
  # tenants later, so each project is its own key.
  defp tenant(%Plug.Conn{path_info: ["api", project, _endpoint]}) when project != "v1", do: "sentry:" <> project

  defp tenant(conn) do
    case get_req_header(conn, "x-scope-orgid") do
      [tenant | _] -> tenant
      [] -> "default"
    end
  end

  # Configured tenant limits charge only callers whose credentials verify for
  # the tenant they name, so a spoofed header cannot spend another tenant's
  # allowance. Others pass through to the controller, which rejects them.
  # Sentry requests name their tenant through DSN project bindings and use
  # only the fair share.
  defp limited_tenant(_conn, :sentry), do: nil

  defp limited_tenant(conn, _format) do
    with true <- Pulse.TenantLimits.configured?(),
         {:ok, tenant} <- PulseWeb.OTLPHTTP.single_header(conn, "x-scope-orgid", "default"),
         :ok <- Pulse.Auth.verify(conn, tenant, :ingest) do
      tenant
    else
      _ -> nil
    end
  end

  # A successful response means the controller verified the caller for the
  # tenant it named. Sentry tenants come from project bindings, so Sentry
  # usage is metered by stored records only.
  defp meter(%Plug.Conn{status: status} = conn, format, signal) when status in 200..299 and format != :sentry,
    do: Pulse.Usage.request(signal, tenant(conn), content_length(conn))

  defp meter(_conn, _format, _signal), do: :ok

  defp content_length(conn) do
    with [value] <- get_req_header(conn, "content-length"),
         {n, ""} <- Integer.parse(value) do
      n
    else
      _ -> nil
    end
  end

  defp rate(_conn, nil), do: :ok

  defp rate(conn, tenant) do
    with {:error, :tenant_rate} = error <- Pulse.TenantLimits.take_ingest_bytes(tenant, content_length(conn)) do
      Pulse.SelfMetrics.admission_rejection(:ingest, :tenant_rate)
      error
    end
  end

  defp refuse(conn, format, reason) do
    message =
      case reason do
        :ingest_overloaded -> "ingest capacity exhausted"
        :tenant_concurrency -> "tenant ingest concurrency limit reached"
        :tenant_rate -> "tenant ingest rate limit reached"
      end

    conn = put_resp_header(conn, "retry-after", "1")

    conn =
      if format == :otlp,
        do: PulseWeb.OTLPHTTP.error(conn, 429, message),
        else: conn |> put_resp_content_type("text/plain") |> send_resp(429, message)

    halt(conn)
  end

  @doc "The `{format, signal}` of an ingest path, or nil for any other path."
  def ingest_path(path_info), do: path_info |> Enum.map(&URI.decode/1) |> ingest()

  # Each request is admitted under the signal class it stores; see
  # `Pulse.IngestAdmission` for the per-signal reserves.
  defp ingest(["v1", "traces"]), do: {:otlp, :traces}
  defp ingest(["v1", "metrics"]), do: {:otlp, :metrics}
  defp ingest(["v1", "logs"]), do: {:otlp, :logs}
  defp ingest(["loki", "api", "v1", "push"]), do: {:text, :logs}
  defp ingest(["api", "v1", "write"]), do: {:text, :metrics}
  defp ingest(["api", "store"]), do: {:sentry, :logs}
  defp ingest(["api", _project, endpoint]) when endpoint in ["envelope", "store"], do: {:sentry, :logs}
  defp ingest(_path), do: nil
end
