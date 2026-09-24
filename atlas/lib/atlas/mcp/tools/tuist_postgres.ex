defmodule Atlas.MCP.Tools.TuistPostgres do
  @moduledoc """
  Shared guard for the Tuist server database MCP tools. Access is governed by the
  "observability" tool group (same as the Grafana/ClickHouse tools), enforced at
  the `tools/list`/dispatch layer; this only checks that the internal Tuist API
  is configured for the environment.
  """

  alias Atlas.TuistServer

  @doc """
  Returns `:ok` when the internal Tuist API is reachable from this environment,
  otherwise `{:error, message}`.
  """
  def ensure_available do
    if TuistServer.configured?() do
      :ok
    else
      {:error, "The Tuist server database is not reachable from this environment."}
    end
  end
end
