defmodule Atlas.MCP.Tools.GetTuistFeatureFlag do
  @moduledoc "Inspects a Tuist feature flag's persisted gates and revision."

  use Atlas.MCP.Tool,
    name: "get_tuist_feature_flag",
    schema: Atlas.TuistFeatureFlags.name_schema(),
    output_schema: Atlas.TuistFeatureFlags.flag_schema()

  alias Atlas.MCP.Tool
  alias Atlas.TuistFeatureFlags

  @impl EMCP.Tool
  def description do
    "Inspect one allowlisted Tuist feature flag's persisted rules and revision before changing it. Requires feature_flags:read. " <>
      "Does not evaluate environment wrappers; the description explains kill-switch polarity and environment defaults. " <>
      "Use evaluate_tuist_feature_flags for effective decisions for one account or project."
  end

  def execute(conn, args) do
    TuistFeatureFlags.get(Tool.current_user(conn), args, interface: Tool.audit_interface(conn))
  end
end
