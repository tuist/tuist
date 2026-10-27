defmodule Tuist.Billing.Entitlements do
  @moduledoc """
  Plan-level feature entitlements.

  `allows?(account, feature)` returns true when the account's current
  active subscription grants access to a feature. Self-hosted Tuist
  deployments grant every feature unconditionally — the deployment's
  Enterprise license is the entitlement, so there's nothing to gate at
  the application layer.

  Add a feature by adding a `plan_allows?/2` clause for it. Default is
  to deny on the hosted Tuist server, so unknown feature names fail closed.
  """

  alias Tuist.Accounts.Account
  alias Tuist.Billing
  alias Tuist.Environment

  @doc """
  Returns true when the account's plan grants access to `feature`.
  """
  def allows?(account, feature) do
    MapSet.member?(allowed_features(account, [feature]), feature)
  end

  @doc """
  Returns the requested features granted by the account's current plan.

  The plan is resolved once for the complete feature set. When subscriptions
  are preloaded on the account, the lookup stays in memory so batch callers do
  not issue one subscription query per account.
  """
  def allowed_features(_account, []), do: MapSet.new()

  def allowed_features(account, features) when is_list(features) do
    if Environment.tuist_hosted?() do
      plan = resolve_plan(account)

      features
      |> Enum.filter(&plan_allows?(plan, &1))
      |> MapSet.new()
    else
      MapSet.new(features)
    end
  end

  # Enterprise gets everything.
  defp plan_allows?(:enterprise, _feature), do: true

  # GitHub Enterprise Server connection — Enterprise only.
  defp plan_allows?(_plan, :github_enterprise_server), do: false

  # Self-hosting cache nodes (running your own Kura nodes) — Enterprise only.
  defp plan_allows?(_plan, :self_hosted_cache), do: false

  # Guaranteed egress floor on the shared bare-metal cache boxes — Enterprise
  # only. The default pattern is bursty, so non-enterprise tenants run best-effort
  # under the Cilium burst ceiling and pack densely; enterprise tenants reserve a
  # scheduler-bin-packed slice of the box's egress budget.
  defp plan_allows?(_plan, :guaranteed_egress_floor), do: false

  defp plan_allows?(_plan, _feature), do: false

  defp resolve_plan(%Account{} = account), do: Billing.effective_plan(account)
  defp resolve_plan(_), do: :air
end
