defmodule CacheWeb.BodyReader do
  @moduledoc false

  def read_body(conn, opts) do
    Cache.BodyReadTimeout.read_body(conn, opts)
  end
end
