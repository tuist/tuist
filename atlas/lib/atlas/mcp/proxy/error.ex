defmodule Atlas.MCP.Proxy.Error do
  @moduledoc "Sanitized upstream failures safe to expose in discovery diagnostics."

  defstruct [:code, :message, :stage, :http_status, retryable: false]
end
