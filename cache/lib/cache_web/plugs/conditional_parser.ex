defmodule CacheWeb.Plugs.ConditionalParser do
  @moduledoc """
  Conditionally applies Plug.Parsers only for requests that need it.
  
  Skips parsing for GET requests to optimize the read path, as GET requests
  don't have request bodies and parsing adds unnecessary overhead.
  """

  @parser_opts Plug.Parsers.init(
                 parsers: [:urlencoded, :multipart, :json],
                 pass: ["*/*"],
                 json_decoder: Phoenix.json_library(),
                 body_reader: {CacheWeb.Plugs.CacheBodyReader, :read_body, []}
               )

  def init(_opts), do: @parser_opts

  def call(%Plug.Conn{method: "GET"} = conn, _opts) do
    conn
  end

  def call(conn, parser_opts) do
    Plug.Parsers.call(conn, parser_opts)
  end
end
