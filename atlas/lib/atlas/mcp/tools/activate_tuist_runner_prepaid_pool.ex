defmodule Atlas.MCP.Tools.ActivateTuistRunnerPrepaidPool do
  @moduledoc "Activates a paid runner credit grant through Tuist's audited internal API."

  use Atlas.MCP.Tool,
    name: "activate_tuist_runner_prepaid_pool",
    schema: Atlas.TuistAccounts.activate_runner_prepaid_pool_schema(),
    output_schema: Atlas.TuistAccounts.runner_billing_output_schema()

  alias Atlas.MCP.Tool
  alias Atlas.TuistAccounts
  alias Atlas.TuistFeatureFlags

  @impl EMCP.Tool
  def description do
    "Activate a prepaid runner order as one shared paid Stripe credit grant for the selected linux/macos platforms, " <>
      "not a separate grant per platform. Each platform consumes the shared credit at its own usage rate. " <>
      "paid_cents is the upfront price in cents; credit_multiplier is a decimal string from 1 to 2 with at most " <>
      "four fractional digits (for example 1.5). Set covers_cache to true only when the order also prepays remote " <>
      "cache usage: the same grant then also pays for the cache egress and request Prices, at the same multiplier, and " <>
      "those Prices are added to the subscription if missing. Omit it for a runner-only order. starts_on and expires_on are inclusive ISO dates. " <>
      "invoice_id identifies the existing upfront Stripe invoice (in_...), which may be draft, open or paid. " <>
      "For an order paid in monthly instalments, set instalments (2–12) and pass the FIRST instalment's invoice as " <>
      "invoice_id: its subtotal times instalments must equal paid_cents, and it must come from a separate Stripe " <>
      "subscription marked with metadata tuist_runner_prepaid_instalments=true. The whole paid_cents is credited at " <>
      "activation, however many instalments are paid; later instalments are collected by Stripe, not tracked here. " <>
      "starts_on cannot be in the future. " <>
      "Ends the runner trial prospectively while preserving trial usage and the free monthly allowance, and schedules " <>
      "a billing-cycle boundary at the end of the term so post-term usage cannot consume this credit. " <>
      "Does not issue, send or pay the upfront invoice, renew the contract, or change per-platform runner capacity. " <>
      "Requires feature_flags:write over MCP. Read get_tuist_runner_billing first and pass its revision as " <>
      "expected_revision, a reason (1–1000 characters) and a unique change_id UUID. Each exact mutation requires the " <>
      "caller's approval: the first call returns an Atlas approval link; ask the person you work for to approve it, " <>
      "then repeat identical arguments to run once. Never approve it yourself. Returns the same billing state as the read. " <>
      "Writes never retry automatically. A failed activation may have partial Stripe effects: re-read and reconcile " <>
      "using the SAME change_id and identical payload, with fresh approval. Never blindly mint a new change_id. " <>
      "A stale revision (409) requires inspection and a new decision, not blind replay with a new revision."
  end

  def execute(conn, args) do
    TuistAccounts.activate_runner_prepaid_pool(Tool.current_user(conn), args, TuistFeatureFlags.execution_opts(conn))
  end
end
