defmodule Tuist.FeatureFlags do
  @moduledoc false

  alias Tuist.Environment

  @doc """
  Whether the Runners dashboard (and its sub-pages) should be visible
  for the given account. Canary and production require an explicit
  `:runners` FunWithFlags toggle for the actor. Development, test, and
  staging default to enabled.

  This is also the source of truth for co-located private Kura cache
  infrastructure, so enabling runners provides the cache without a second
  operator-managed switch.
  """
  def runners_enabled?(account) do
    not runner_flag_required?() or FunWithFlags.enabled?(:runners, for: account)
  end

  @doc false
  def runners_enabled?(account, %FunWithFlags.Flag{} = flag) do
    not runner_flag_required?() or FunWithFlags.Flag.enabled?(flag, for: account)
  end

  defp runner_flag_required?, do: Environment.env() in [:can, :prod]

  @doc """
  Whether the Kura surface (the per-account Kura servers, the
  self-hosted cache management, and the Usage dashboard) should be
  visible for the given account. Self-hosted deployments (including
  dev/test, which are also not `tuist_hosted?`) always see it, mirroring
  `Tuist.Billing.Entitlements` where the deployment's license is the
  entitlement; the hosted server gates it behind the `:kura` FunWithFlags
  toggle for the actor. Callers should use this rather than checking the
  flag inline so the sidebar entry, the LiveView guards, and the settings
  page all answer the same question.
  """
  def kura_enabled?(account) do
    not Environment.tuist_hosted?() or FunWithFlags.enabled?(:kura, for: account)
  end

  @doc """
  Whether automatic Kura claim sizing is paused fleet-wide. Sizing applies its
  own proposals by default, so this is the stop button rather than an opt-in:
  enabling it leaves the sweep writing proposals for operators to confirm by
  hand. Deliberately global — the per-account off switch is the operator
  claim override.
  """
  def kura_claim_sizing_paused? do
    FunWithFlags.enabled?(:kura_claim_sizing_paused)
  end

  defimpl FunWithFlags.Actor, for: Tuist.Accounts.User do
    def id(%{id: id}) do
      "user:#{id}"
    end
  end

  defimpl FunWithFlags.Actor, for: Tuist.Accounts.Account do
    def id(%{id: id}) do
      "account:#{id}"
    end
  end

  defimpl FunWithFlags.Actor, for: Tuist.Projects.Project do
    def id(%{id: id}) do
      "project:#{id}"
    end
  end
end
