defmodule TuistWeb.Plugs.OpsHostPlug do
  @moduledoc """
  Restricts ops routes to the configured ops host.
  """

  alias Tuist.Environment
  alias TuistWeb.Errors.NotFoundError

  def init(opts), do: opts

  def call(conn, _opts) do
    ops_hosts = Environment.ops_hosts()

    cond do
      String.downcase(conn.host) in ops_hosts ->
        conn

      ops_hosts == [] and not Environment.tuist_hosted?() ->
        conn

      true ->
        raise NotFoundError, "The page you are looking for doesn't exist or has been moved."
    end
  end
end
