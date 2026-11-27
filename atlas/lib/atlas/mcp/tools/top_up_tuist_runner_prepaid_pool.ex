defmodule Atlas.MCP.Tools.TopUpTuistRunnerPrepaidPool do
  @moduledoc "Tops up a Tuist account's live prepaid runner pool through Tuist's audited internal API."

  use Atlas.MCP.Tool,
    name: "top_up_tuist_runner_prepaid_pool",
    schema: Atlas.TuistAccounts.top_up_runner_prepaid_pool_schema(),
    output_schema: Atlas.TuistAccounts.runner_billing_output_schema()

  alias Atlas.MCP.Tool
  alias Atlas.TuistAccounts
  alias Atlas.TuistFeatureFlags

  @impl EMCP.Tool
  def description do
    "Top up the live prepaid runner pool of a Tuist account (one activated with activate_tuist_runner_prepaid_pool, " <>
      "already started and ending after today) with more paid credit. grants lists one entry per platform (linux, " <>
      "macos; each at most once and covered by the pool), each with paid_cents (what was paid for that platform, in " <>
      "cents) and its own credit_multiplier (a decimal string from 1 to 2 with at most four fractional digits: the " <>
      "on-demand price per minute divided by the top-up's price). Each entry becomes its own Stripe credit grant scoped " <>
      "to that platform, expiring with the pool and spent before it, so a top-up priced differently per platform must " <>
      "be split between platforms when sold. When the pool was activated with covers_cache, the linux grant also pays " <>
      "for remote cache usage at its own multiplier; a top-up with no linux entry adds no cache credit. invoice_id is the existing Stripe invoice (in_...) charging for the " <>
      "top-up: the customer's, in USD, with a subtotal equal to the sum of paid_cents, and not already used by an " <>
      "activation or another top-up. Does not issue, send or pay the invoice, or change the pool's term. Refused with " <>
      "no_live_pool, platform_not_in_pool, invoice_does_not_match or invoice_already_used. " <>
      "Requires feature_flags:write over MCP. Read get_tuist_runner_billing first and pass its revision as " <>
      "expected_revision, a reason (1–1000 characters) and a unique change_id UUID. Each exact mutation requires the " <>
      "caller's approval: the first call returns an Atlas approval link; ask the person you work for to approve it, " <>
      "then repeat identical arguments to run once. Never approve it yourself. Returns the same billing state as the read. " <>
      "Writes never retry automatically. A failed top-up may have granted some platforms: re-read and reconcile using " <>
      "the SAME change_id and identical payload, with fresh approval, which never grants a platform twice. Never blindly " <>
      "mint a new change_id. A stale revision (409) requires inspection and a new decision, not blind replay with a new revision."
  end

  def execute(conn, args) do
    TuistAccounts.top_up_runner_prepaid_pool(Tool.current_user(conn), args, TuistFeatureFlags.execution_opts(conn))
  end
end
