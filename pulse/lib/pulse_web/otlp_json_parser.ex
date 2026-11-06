defmodule PulseWeb.OTLPJSONParser do
  @moduledoc false
  @behaviour Plug.Parsers

  alias Plug.Parsers.JSON

  @impl true
  def init(opts) do
    otlp =
      Map.new([:logs, :metrics, :traces], fn signal ->
        decoder = {Pulse.OTLP.JSON, :decode!, [signal]}
        {Atom.to_string(signal), JSON.init(Keyword.put(opts, :json_decoder, decoder))}
      end)

    {JSON.init(opts), otlp}
  end

  @impl true
  def parse(conn, type, subtype, headers, {generic, otlp}) do
    path = Enum.map(conn.path_info, &URI.decode/1)

    opts =
      case {conn.method, path, type, subtype} do
        {"POST", ["v1", signal], "application", "json"} -> Map.get(otlp, signal, generic)
        _ -> generic
      end

    JSON.parse(conn, type, subtype, headers, opts)
  end
end
