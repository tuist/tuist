defmodule CacheWeb.Plugs.ObanAuth do
  @moduledoc false
  def init(opts), do: opts

  def call(conn, _opts) do
    Plug.BasicAuth.basic_auth(conn, Application.fetch_env!(:cache, :oban_web_basic_auth))
  end
end
