defmodule Atlas.MCP.Tools.GetTuistAccount do
  @moduledoc "Resolves a Tuist organization or user handle to its Tuist account ID."

  use Atlas.MCP.Tool,
    name: "get_tuist_account",
    schema: Atlas.TuistAccounts.lookup_schema(),
    output_schema: Atlas.TuistAccounts.account_schema()

  alias Atlas.MCP.Tool
  alias Atlas.TuistAccounts
  alias Atlas.TuistFeatureFlags

  @impl EMCP.Tool
  def description do
    "Resolve a Tuist organization or user handle (case-insensitive) to its positive Tuist account_id. Requires feature_flags:read. " <>
      "Use account_id for account-scoped feature flags (gates read account:<account_id>) and runner concurrency limits. " <>
      "An organization ID, such as the one tuist__get_organization returns, is a different number and is not an account ID. " <>
      "Atlas CRM account UUIDs and handles are separate records too."
  end

  def execute(conn, args) do
    TuistAccounts.lookup(Tool.current_user(conn), args, TuistFeatureFlags.execution_opts(conn))
  end
end
