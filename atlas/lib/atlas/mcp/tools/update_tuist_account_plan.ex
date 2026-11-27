defmodule Atlas.MCP.Tools.UpdateTuistAccountPlan do
  @moduledoc "Changes a Tuist account's billing plan through the audited internal API, as the ops account page does."

  use Atlas.MCP.Tool,
    name: "update_tuist_account_plan",
    schema: Atlas.TuistAccounts.update_plan_schema(),
    output_schema: Atlas.TuistAccounts.plan_output_schema()

  alias Atlas.MCP.Tool
  alias Atlas.TuistAccounts
  alias Atlas.TuistFeatureFlags

  @impl EMCP.Tool
  def description do
    "Change a Tuist account's billing plan in Stripe, as the ops account page's buttons do. These create or change real " <>
      "Stripe subscriptions and change what the customer can use. operation: upgrade_to_enterprise creates (or switches the " <>
      "live subscription to) the invoice-billed monthly Enterprise subscription that carries usage and runner prices; " <>
      "contract fees are invoiced separately. It is refused when the account is already on Enterprise, and needs the Stripe " <>
      "customer's name, email and address: pass billing_details only when the customer lacks them " <>
      "(error billing_details_required). start_open_source works only without a live subscription. cancel_at_period_end " <>
      "cancels a live Pro, Enterprise or Open Source subscription at the end of its period; access is kept until then. " <>
      "schedule_pro switches a live Enterprise or Open Source subscription to Pro at starts_at (a future UTC timestamp " <>
      "ending in Z, at most 366 days ahead), through a Stripe subscription schedule: the plan stays as it is until then, " <>
      "and from starts_at the subscription carries the Pro prices, starts a new billing cycle and charges the customer's " <>
      "default payment method. It is refused without a default payment method (error payment_method_required, ask the " <>
      "customer to add a card) and when the subscription is already Pro or set to cancel (no_schedulable_subscription). " <>
      "switch_to_usd recreates a live $0 Enterprise subscription priced in another currency, such as EUR, in USD, so it " <>
      "can carry the USD-only runner prices: the old one is cancelled without proration and replaced on the same customer " <>
      "with the Enterprise items, collection method and renewal date. It is refused with no_switchable_subscription (not " <>
      "a live Enterprise subscription), already_usd, billable_subscription (it carries metered items or seats), " <>
      "open_invoice, or usd_prices_missing. " <>
      "Requires feature_flags:write. Read get_tuist_account_plan first and supply its revision as expected_revision, a reason " <>
      "and a unique change_id UUID. A stale revision is rejected (409), including after a Stripe webhook or ops page change: " <>
      "re-read before deciding again. Writes never retry automatically; after an ambiguous failure, re-read the plan, and " <>
      "repeat with the SAME change_id and payload, which returns the recorded result when it was applied. Returns the plan " <>
      "after the change. Each write needs the approval of the person you work for: the first call files a request and " <>
      "returns a link, the person approves it in Atlas, and the same call with identical arguments then runs once. " <>
      "Never approve it yourself."
  end

  def execute(conn, args) do
    TuistAccounts.update_plan(Tool.current_user(conn), args, TuistFeatureFlags.execution_opts(conn))
  end
end
