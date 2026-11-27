defmodule Atlas.MCP.Tools.GetTuistRunnerBilling do
  @moduledoc "Reads a Tuist account's runner trial, prepaid credit grants and activation state."

  use Atlas.MCP.Tool,
    name: "get_tuist_runner_billing",
    schema: Atlas.TuistAccounts.runner_billing_schema(),
    output_schema: Atlas.TuistAccounts.runner_billing_output_schema()

  alias Atlas.MCP.Tool
  alias Atlas.TuistAccounts
  alias Atlas.TuistFeatureFlags

  @impl EMCP.Tool
  def description do
    "Read a Tuist account's runner billing: runner trial state, Stripe prepaid grants and available credit, " <>
      "latest activation state and revision for activate_tuist_runner_prepaid_pool, top_up_tuist_runner_prepaid_pool and update_tuist_runner_trial. Use this to inspect billing " <>
      "before activation or reconcile a failed activation, which may have partial external effects. " <>
      "Requires feature_flags:read. account_id is the positive Tuist account ID from get_tuist_account. " <>
      "This does not read or change per-platform runner capacity; use get_tuist_runner_concurrency_limits for that."
  end

  def execute(conn, args) do
    TuistAccounts.get_runner_billing(Tool.current_user(conn), args, TuistFeatureFlags.execution_opts(conn))
  end
end
