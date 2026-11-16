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
    "Inspect one Tuist feature flag's persisted rules and revision before changing it, including a new name you are about to create. " <>
      "Requires feature_flags:read. actor_type any marks a flag outside Tuist's catalog, which takes account or project gates. " <>
      "Does not evaluate environment wrappers; the description explains kill-switch polarity and environment defaults. " <>
      "Use evaluate_tuist_feature_flags for effective decisions for one account or project."
  end

  def execute(conn, args) do
    TuistFeatureFlags.get(Tool.current_user(conn), args, TuistFeatureFlags.execution_opts(conn))
  end
end
