defmodule Atlas.MCP.Tools.GetTuistRunnerConcurrencyLimits do
  @moduledoc "Reads a Tuist account's runner concurrency limits, usage and revision."

  use Atlas.MCP.Tool,
    name: "get_tuist_runner_concurrency_limits",
    schema: Atlas.TuistAccounts.limits_schema(),
    output_schema: Atlas.TuistAccounts.limits_output_schema()

  alias Atlas.MCP.Tool
  alias Atlas.TuistAccounts
  alias Atlas.TuistFeatureFlags

  @impl EMCP.Tool
  def description do
    "Read one Tuist account's runner concurrency limits per platform (linux, macos): the vCPU and memory_gb budgets its " <>
      "concurrently running runner jobs may hold, the resources its active claims hold now, the defaults new accounts get, " <>
      "and the revision to pass to update_tuist_runner_concurrency_limits. Requires feature_flags:read. " <>
      "account_id is the positive Tuist account ID from get_tuist_account, not an organization ID or Atlas UUID."
  end

  def execute(conn, args) do
    TuistAccounts.get_limits(Tool.current_user(conn), args, TuistFeatureFlags.execution_opts(conn))
  end
end
