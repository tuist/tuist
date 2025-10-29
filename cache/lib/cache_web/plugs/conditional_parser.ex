defmodule CacheWeb.Plugs.ConditionalParser do
  @moduledoc """
  Conditionally applies Plug.Parsers only for requests that need it.
  
  Skips parsing for GET requests to optimize the read path, as GET requests
  don't have request bodies and parsing adds unnecessary overhead.
  """

  def init(_opts), do: nil

  def call(%Plug.Conn{method: "GET"} = conn, _opts) do
    conn
  end

  def call(conn, _opts) do
    Plug.Parsers.call(
      conn,
      Plug.Parsers.init(
        parsers: [:urlencoded, :multipart, :json],
        pass: ["*/*"],
        json_decoder: Phoenix.json_library(),
        body_reader: {CacheWeb.Plugs.CacheBodyReader, :read_body, []}
      )
    )
  end
end
