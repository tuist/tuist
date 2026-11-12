defmodule Pulse.Test.MCPMessages do
  @moduledoc false

  @version "2026-07-28"

  def version, do: @version

  def meta(overrides \\ %{}) do
    Map.merge(
      %{
        "io.modelcontextprotocol/protocolVersion" => @version,
        "io.modelcontextprotocol/clientInfo" => %{"name" => "pulse-test", "version" => "1.0.0"},
        "io.modelcontextprotocol/clientCapabilities" => %{}
      },
      overrides
    )
  end

  def request(id, method, params \\ %{}) do
    %{"jsonrpc" => "2.0", "id" => id, "method" => method, "params" => Map.put(params, "_meta", meta())}
  end
end
