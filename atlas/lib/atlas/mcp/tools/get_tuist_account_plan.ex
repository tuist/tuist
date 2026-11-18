defmodule Atlas.MCP.Tools.GetTuistAccountPlan do
  @moduledoc "Reads a Tuist account's effective plan, subscriptions and plan revision."

  use Atlas.MCP.Tool,
    name: "get_tuist_account_plan",
    schema: Atlas.TuistAccounts.plan_schema(),
    output_schema: Atlas.TuistAccounts.plan_output_schema()

  alias Atlas.MCP.Tool
  alias Atlas.TuistAccounts
  alias Atlas.TuistFeatureFlags

  @impl EMCP.Tool
  def description do
    "Read one Tuist account's billing plan. effective_plan is the plan Tuist enforces: air whenever no subscription is live " <>
      "(active, trialing or past_due), which is what sends Air usage emails and cuts off the cache at the free tier, even " <>
      "for a customer whose contract is invoiced separately. Also returns the live subscription it comes from, the 10 most " <>
      "recent subscriptions of any status (to spot one that ended), whether a failed payment lapsed the plan, whether cache " <>
      "access is blocked, the Stripe customer ID, and the revision to pass to update_tuist_account_plan. " <>
      "Requires feature_flags:read. account_id is the positive Tuist account ID from get_tuist_account."
  end

  def execute(conn, args) do
    TuistAccounts.get_plan(Tool.current_user(conn), args, TuistFeatureFlags.execution_opts(conn))
  end
end
