defmodule TuistWeb.RedirectToRunsPlug do
  @moduledoc """
  No-op plug kept for backwards compatibility.
  """
  use TuistWeb, :controller

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts), do: conn
end
