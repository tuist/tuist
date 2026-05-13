defmodule TuistWeb.Plugs.OpsHostPlug do
  @moduledoc """
  Restricts ops routes to the configured ops host when one is set.
  """

  alias Tuist.Environment
  alias TuistWeb.Errors.NotFoundError

  def init(opts), do: opts

  def call(conn, _opts) do
    ops_hosts = Environment.ops_hosts()

    if ops_hosts == [] or String.downcase(conn.host) in ops_hosts do
      conn
    else
      raise NotFoundError, "The page you are looking for doesn't exist or has been moved."
    end
  end
end
