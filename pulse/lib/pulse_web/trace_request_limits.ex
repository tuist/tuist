defmodule PulseWeb.TraceRequestLimits do
  @moduledoc false
  @behaviour Plug

  @heap_words 16_000_000

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    if conn.method == "POST" and otlp_path?(conn.path_info) do
      original =
        Process.flag(:max_heap_size, %{
          size: @heap_words,
          kill: true,
          error_logger: false,
          include_shared_binaries: true
        })

      # HTTP/1 connections can reuse their process. Do not leave an OTLP
      # request's cap on subsequent requests, or on ConnTest's caller.
      Plug.Conn.register_before_send(conn, fn conn ->
        Process.flag(:max_heap_size, original)
        conn
      end)
    else
      conn
    end
  end

  defp otlp_path?(path), do: Enum.map(path, &URI.decode/1) in [["v1", "traces"], ["v1", "logs"], ["v1", "metrics"]]
end
