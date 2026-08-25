defmodule TuistWeb.Plugs.RunnersEnabledPlug do
  @moduledoc false

  @behaviour Plug

  import Plug.Conn

  alias Tuist.Environment

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    if Environment.runners_enabled?() do
      conn
    else
      conn
      |> send_resp(404, "")
      |> halt()
    end
  end
end
