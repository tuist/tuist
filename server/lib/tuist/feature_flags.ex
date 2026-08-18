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
  Whether the demand-driven Kura lifecycle may archive this account's
  inactive instances (`Tuist.Kura.Lifecycle`).

  Off until an operator enables `:kura_archival`, so a sweep can never run
  against demand data that has not been seeded yet. Once on, FunWithFlags
  precedence gives the rollback the spec requires: an actor gate switches one
  account off and a group gate switches a whole plan off, both while the
  boolean gate keeps archival on for everyone else. Provisioning is never
  gated by this flag, so disabling archival during an incident does not also
  stop archived accounts from getting their instances back.
  """
  def kura_archival_enabled?(account) do
    FunWithFlags.enabled?(:kura_archival, for: account)
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

  # An account's groups are its effective billing plan, so a flag can be
  # switched for a whole tier — `:kura_archival` off for `air` during an
  # incident, say — without enumerating accounts. FunWithFlags only consults
  # this for flags that actually carry group gates, so flags gated by actor or
  # boolean alone pay nothing for it.
  defimpl FunWithFlags.Group, for: Tuist.Accounts.Account do
    def in?(account, group) do
      to_string(Tuist.Billing.effective_plan(account)) == to_string(group)
    end
  end

  defimpl FunWithFlags.Actor, for: Tuist.Projects.Project do
    def id(%{id: id}) do
      "project:#{id}"
    end
  end
end
