defmodule Atlas.MCP.Tools.UpdateTuistFeatureFlag do
  @moduledoc "Updates allowlisted Tuist feature flags through the audited internal domain API."

  use Atlas.MCP.Tool,
    name: "update_tuist_feature_flag",
    schema: Atlas.TuistFeatureFlags.update_schema(),
    output_schema: Atlas.TuistFeatureFlags.flag_schema()

  alias Atlas.MCP.Tool
  alias Atlas.TuistFeatureFlags

  @impl EMCP.Tool
  def description do
    "Change persisted Tuist feature flag rules. Requires feature_flags:write. Inspect first and supply expected_revision, a reason " <>
      "and a unique change_id UUID. Account/project scopes use positive Tuist IDs, not Atlas UUIDs. " <>
      "Percentage enable sets a deterministic actor rollout strictly between 0 and 100; percentage clear takes no percentage. " <>
      "Global disable changes only the boolean gate and PRESERVES actor/percentage overrides; it is not an emergency reset. " <>
      "Clear removes the selected override and restores inheritance. Explicit emergency reset is operation=clear, scope=all, removing ALL gates. " <>
      "Read the flag description for kill-switch polarity and environment defaults; persisted gates do not evaluate environment wrappers. " <>
      "A stale revision is rejected (409): re-inspect before making a new decision. Writes never retry automatically; after an ambiguous failure " <>
      "reconcile using the SAME change_id and original payload. Actor and interface come from the authenticated session, never arguments."
  end

  def execute(conn, args) do
    TuistFeatureFlags.update(Tool.current_user(conn), args, interface: Tool.audit_interface(conn))
  end
end
