defmodule TuistCommon.HTTP.FinchTracer do
  @moduledoc """
  Creates `OpenTelemetry` client spans for Finch requests.

  This is a hardened replacement for `OpentelemetryFinch.setup/0`
  (opentelemetry_finch 0.2.0). Upstream's `[:finch, :request, :stop]`
  handler assumes `meta.result` is always `{:ok, %Finch.Response{}}` and
  reads `response.status` directly. That holds for `Finch.request/3`, but
  not for `Finch.stream_while/5` — which `Req` uses whenever `:into` is a
  function (e.g. streaming GitHub Actions logs). There the result is
  `{:ok, acc}` where `acc` is the caller's accumulator; for `Req` that is a
  `{request, response}` tuple. Calling `.status` on a tuple raises
  `BadMapError`, the telemetry handler crashes, and `:telemetry`
  permanently detaches it — silently dropping Finch tracing for the rest of
  the node's lifetime (until the next deploy re-attaches and re-crashes it).

  We only read `status` when the payload is an actual `%Finch.Response{}`.
  """

  require OpenTelemetry.Tracer

  def setup do
    :telemetry.attach(
      {__MODULE__, :request_stop},
      [:finch, :request, :stop],
      &__MODULE__.handle_request_stop/4,
      %{}
    )

    :ok
  end

  def handle_request_stop(_event, measurements, meta, _config) do
    duration = measurements.duration
    end_time = :opentelemetry.timestamp()
    start_time = end_time - duration

    status =
      case meta.result do
        {:ok, %Finch.Response{} = response} -> response.status
        _ -> 0
      end

    url = build_url(meta.request.scheme, meta.request.host, meta.request.port, meta.request.path)

    attributes = %{
      "http.url": url,
      "http.scheme": meta.request.scheme,
      "net.peer.name": meta.request.host,
      "net.peer.port": meta.request.port,
      "http.target": meta.request.path,
      "http.method": meta.request.method,
      "http.status_code": status
    }

    span =
      OpenTelemetry.Tracer.start_span("HTTP #{meta.request.method}", %{
        start_time: start_time,
        attributes: attributes,
        kind: :client
      })

    case meta.result do
      {:error, reason} ->
        OpenTelemetry.Span.set_status(span, OpenTelemetry.status(:error, format_error(reason)))

      _ ->
        :ok
    end

    OpenTelemetry.Span.end_span(span)
  end

  defp build_url(scheme, host, port, path), do: "#{scheme}://#{host}:#{port}#{path}"

  defp format_error(%{__exception__: true} = exception), do: Exception.message(exception)
  defp format_error(reason), do: inspect(reason)
end
