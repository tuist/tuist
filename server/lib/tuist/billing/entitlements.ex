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
    not Environment.tuist_hosted?() or plan_allows?(current_plan(account), feature)
  end

  # Enterprise gets everything.
  defp plan_allows?(:enterprise, _feature), do: true

  # GitHub Enterprise Server connection — Enterprise only.
  defp plan_allows?(_plan, :github_enterprise_server), do: false

  # Self-hosting cache nodes (running your own Kura nodes) — Enterprise only.
  defp plan_allows?(_plan, :self_hosted_cache), do: false

  defp plan_allows?(_plan, _feature), do: false

  defp current_plan(%Account{} = account) do
    case Billing.get_current_active_subscription(account) do
      %{plan: plan} when is_atom(plan) -> plan
      _ -> :air
    end
  end

  defp current_plan(_), do: :air
end
