defmodule Atlas.MCP.Tools.ListTuistFeatureFlags do
  @moduledoc "Lists the Tuist server's allowlisted feature flags and persisted gates."

  use Atlas.MCP.Tool,
    name: "list_tuist_feature_flags",
    schema: %{"type" => "object", "properties" => %{}, "additionalProperties" => false},
    output_schema: %{
      "type" => "object",
      "properties" => %{"flags" => %{"type" => "array", "items" => Atlas.TuistFeatureFlags.flag_schema()}},
      "required" => ["flags"],
      "additionalProperties" => false
    }

  alias Atlas.MCP.Tool
  alias Atlas.TuistFeatureFlags

  @impl EMCP.Tool
  def description do
    "List allowlisted Tuist feature flags, descriptions, revisions and persisted gates. Requires feature_flags:read. " <>
      "These are persisted rules, not environment-wrapper outcomes. Read descriptions for kill-switch polarity and environment defaults."
  end

  def execute(conn, args) do
    TuistFeatureFlags.list(Tool.current_user(conn), args, interface: Tool.audit_interface(conn))
  end
end
