defmodule TuistWeb.OpsAccountHelpers do
  @moduledoc """
  Shared view helpers for the /ops account index and the per-account
  detail page. Pure functions only — both LiveViews `import` this so
  the same plan/status/type rendering shows up everywhere.
  """
  alias Tuist.Accounts.Account

  def account_type(%Account{organization_id: organization_id}) when not is_nil(organization_id), do: "Organization"
  def account_type(%Account{user_id: user_id}) when not is_nil(user_id), do: "User"
  def account_type(_), do: "Unknown"

  def current_plan(%Account{subscriptions: [%{plan: plan} | _]}), do: plan
  def current_plan(_), do: :air

  def plan_label(:air), do: "Air"
  def plan_label(:pro), do: "Pro"
  def plan_label(:enterprise), do: "Enterprise"
  def plan_label(:open_source), do: "Open Source"
  def plan_label(_), do: "Unknown"

  def plan_color(:air), do: "neutral"
  def plan_color(:pro), do: "primary"
  def plan_color(:enterprise), do: "success"
  def plan_color(:open_source), do: "information"
  def plan_color(_), do: "neutral"

  # `cancel_at_period_end` takes priority — a subscription flagged for
  # cancellation still reports `status: "active"` until the period ends.
  # Accounts without a subscription are on the Air plan, which is always
  # active (there's nothing to cancel).
  def subscription_status(%Account{subscriptions: [%{cancel_at_period_end: true} | _]}), do: :cancelled
  def subscription_status(%Account{subscriptions: [%{status: "trialing"} | _]}), do: :trialing
  def subscription_status(_), do: :active

  def status_label(:active), do: "Active"
  def status_label(:trialing), do: "Trialing"
  def status_label(:cancelled), do: "Cancelled"

  def status_color(:active), do: "success"
  def status_color(:trialing), do: "information"
  def status_color(:cancelled), do: "warning"
end
