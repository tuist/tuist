defmodule Tuist.MCP.Events do
  @moduledoc """
  The Model Context Protocol event subscription entry point.
  """

  alias Tuist.MCP.Events.Catalog
  alias Tuist.MCP.Events.Subscriptions

  defdelegate list(), to: Catalog
  defdelegate subscribe(conn, params), to: Subscriptions
  defdelegate unsubscribe(conn, params), to: Subscriptions
end
